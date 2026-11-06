-- Capture on Rex's existing connection, then start Neovim without a shell.
local M = {}
local chunk_bytes = 983040

local function executable(name)
  local path = (os.getenv("PATH") or "") .. ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
  for directory in path:gmatch("[^:]+") do
    local candidate = directory .. "/" .. name
    local file = io.open(candidate, "rb")
    if file then file:close(); return candidate end
  end
  if name == "rex" then
    for _, parent in ipairs({ "/Applications", (os.getenv("HOME") or "") .. "/Applications" }) do
      for _, app in ipairs({ "Rex Beta.app", "Rex.app" }) do
        local candidate = parent .. "/" .. app .. "/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
        local file = io.open(candidate, "rb")
        if file then file:close(); return candidate end
      end
    end
  end
  error("Copy mode needs " .. name .. " on PATH", 0)
end

local function terminal(ctx, method, args)
  local value, err = rex.call("com.superlogical.terminal." .. method, {
    session_id = ctx.session_id, block_id = ctx.block_id, args = args,
  })
  if not value then error(err or ("Cannot " .. method .. " this terminal"), 0) end
  return value
end

local function capture(ctx, file)
  local first = terminal(ctx, "format", {
    format = "text", trim = true, unwrap = true, max_bytes = chunk_bytes,
  })
  assert(type(first.content) == "string", "Rex returned no terminal text")
  assert(file:write(first.content))
  local offset = #first.content
  if first.id and not first.eof then
    while true do
      local part = terminal(ctx, "blob_read", {
        id = first.id, offset = offset, max_bytes = chunk_bytes,
      })
      assert(type(part.data) == "string", "Rex returned no scrollback chunk")
      assert(file:write(part.data))
      offset = offset + #part.data
      if part.eof then break end
      assert(#part.data > 0, "Rex stopped returning scrollback before its end")
    end
  end
end

function M.setup(options)
  local pending_zoom = {}
  local nvim, rex_binary
  local home = os.getenv("XDG_CONFIG_HOME")
  if not home or home == "" then home = assert(os.getenv("HOME")) .. "/.config" end
  local editor = options.editor or (home .. "/rex/copy-editor.lua")

  rex.action {
    name = "tmux_copy_restore", title = "Restore Copy Mode Zoom", category = "History",
    run = function(ctx)
      if not ctx.block_id then return end
      local origin = pending_zoom[ctx.block_id]
      pending_zoom[ctx.block_id] = nil
      if not origin or origin.session_id ~= ctx.session_id then return end
      local view = rex.session.view { session_id = ctx.session_id }
      for _, window in ipairs(view and view.windows or {}) do
        -- Never follow a moved pane, or replace focus/zoom changed by the user.
        if window.window_id == origin.window_id and window.focused_block_id == ctx.block_id
            and not window.zoomed_block_id then
          for _, layer in ipairs(window.layers or {}) do
            for _, block in ipairs(layer.blocks or {}) do
              if layer.state ~= "minimized" and block.block_id == origin.block_id then
                local restored, err = rex.session.zoom_block {
                  session_id = ctx.session_id, block_id = origin.block_id, zoom = true,
                }
                if not restored then error(err or "Cannot restore copy mode zoom", 0) end
                return
              end
            end
          end
        end
      end
    end,
  }

  rex.action {
    name = "tmux_copy_mode", title = "Keyboard Copy Mode", category = "History",
    description = "Select terminal history with Vim keys; y or Enter copies and closes",
    run = function(ctx)
      if not ctx.block_id then error("Open copy mode from a terminal pane", 0) end
      local _, _, window = options.context_view(ctx)
      -- Repeated presses in the overlay must not recursively capture Neovim.
      for _, layer in ipairs(window.layers or {}) do
        for _, block in ipairs(layer.blocks or {}) do
          if block.block_id == ctx.block_id and block.label == "copy-mode" then return end
        end
      end
      nvim = nvim or executable("nvim")
      if window.zoomed_block_id then rex_binary = rex_binary or executable("rex") end
      -- On the same Mac, pbcopy confirms delivery before the float closes.
      -- Never use the server's clipboard for an app connected over a network.
      local clipboard
      local caller = ctx.client_id and rex.call("client.inspect", { client_id = ctx.client_id })
      local principal = caller and caller.client and caller.client.principal
      if principal and principal.kind == "peer" and principal.transport == "unix"
          and (principal.path == nil or (type(principal.path) == "table" and next(principal.path) == nil)) then
        local found, binary = pcall(executable, "pbcopy")
        if found then clipboard = binary end
      end
      local config, config_error = io.open(editor, "rb")
      if not config then error(config_error or "Missing copy-editor.lua; rerun install.sh", 0) end
      config:close()
      -- Rex's os.tmpname only returns a name. mktemp creates the file atomically
      -- with mode 0600; run it directly, without a shell or another Rex CLI.
      local tempdir = os.getenv("TMPDIR")
      if not tempdir or tempdir == "" then tempdir = "/tmp" end
      local temporary, temp_error = rex.exec { "mktemp", tempdir .. "/rex-copy.XXXXXXXX" }
      if not temporary or not temporary.ok then
        error(temp_error or (temporary and temporary.stderr) or "Cannot create the copy snapshot", 0)
      end
      local path = temporary.stdout:gsub("[\r\n]+$", "")
      assert(path ~= "", "mktemp returned no snapshot path")
      local file
      local ok, result = pcall(function()
        file = assert(io.open(path, "wb"))
        capture(ctx, file)
        assert(file:close()); file = nil
        local settings = rex.json.encode { path = path, clipboard = clipboard,
          restore = window.zoomed_block_id and rex_binary or nil }
        local created, err = rex.session.new_layer {
          session_id = ctx.session_id, window_id = window.window_id,
          bounds = { 0.04, 0.04, 0.92, 0.92 }, focus = true,
          layout = rex.layout.block {
            flavor = "com.superlogical.terminal.shell", label = "copy-mode",
            options = { shell = "none", command = {
              nvim, "--noplugin", "-i", "NONE", "-n", "-R",
              "--cmd", "lua vim.g.rex_copy = vim.json.decode(" .. string.format("%q", settings) .. ")",
              "-u", editor, "--", path,
            } },
          },
        }
        if not created then error(err or "Cannot open copy mode", 0) end
        if window.zoomed_block_id and created.block_ids and created.block_ids[1] then
          pending_zoom[created.block_ids[1]] = {
            session_id = ctx.session_id, window_id = window.window_id,
            block_id = window.zoomed_block_id,
          }
        end
        return created
      end)
      if not ok then
        if file then pcall(function() file:close() end) end
        os.remove(path)
        error(result, 0)
      end
      return result
    end,
  }
end

return M
