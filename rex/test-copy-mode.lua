-- Capture, launch and restoration contracts without touching a live session.
local directory = (arg[0]:match("^(.*)/") or ".")
local passed = 0
local function fixture(options)
  options = options or {}
  local state = { actions = {}, calls = {}, files = {}, execs = 0 }
  state.window = { window_id = "window:origin", zoomed_block_id = options.zoom and "block:origin",
    layers = { { blocks = { { block_id = "block:origin" } } } } }
  local rex = { session = {}, layout = { block = function(args) return { block = args } end },
    json = { encode = function(settings) state.settings = settings; return "{}" end } }
  function rex.action(action) state.actions[action.name] = action.run end
  function rex.exec(command)
    state.execs = state.execs + 1
    assert(command[1] == "mktemp" and #command == 2, "unexpected startup subprocess")
    return { ok = true, stdout = "/tmp/private-copy\n" }
  end
  function rex.call(method, args)
    if method == "client.inspect" then
      assert(args.client_id == "client:caller")
      return { client = { principal = { kind = "peer", transport = "unix",
        path = options.remote and { "login-server" } or nil } } }
    end
    assert(args.session_id == "session:origin" and args.block_id == "block:origin")
    state.calls[#state.calls + 1] = { method = method, args = args.args }
    if options.capture_error then return nil, "capture failed" end
    if method == "com.superlogical.terminal.format" then
      assert(args.args.unwrap and args.args.trim and args.args.max_bytes > 0)
      return { content = "α\n", id = options.chunked and 42 or nil }
    end
    assert(method == "com.superlogical.terminal.blob_read" and args.args.id == 42)
    assert(args.args.offset == #"α\n", "offset must be bytes, not characters")
    if options.stalled then return { data = "", eof = false } end
    return { data = "tail\n", eof = true }
  end
  function rex.session.new_layer(args)
    state.created = args
    if options.launch_error then return nil, "launch failed" end
    return { block_ids = { "block:copy" }, layer_id = "layer:copy" }
  end
  function rex.session.view() return { windows = { state.window } } end
  function rex.session.zoom_block(args) state.zoom = args; return {} end
  local env = setmetatable({ rex = rex,
    os = { getenv = function(name)
      return ({ HOME = "/home/user", PATH = "/bin" })[name]
    end, remove = function(path) state.files[path] = nil; state.removed = path; return true end },
    io = { open = function(path, mode)
      if mode == "rb" then
        if options.missing_nvim and path:match("/nvim$") then return nil end
        return { close = function() end }
      end
      assert(path == "/tmp/private-copy" and mode == "wb")
      state.files[path] = ""
      return { write = function(_, value) state.files[path] = state.files[path] .. value; return true end,
        close = function() return true end }
    end },
  }, { __index = _G })
  local module = assert(loadfile(directory .. "/copy-mode.lua", "t", env))()
  module.setup { editor = "/config/copy-editor.lua", context_view = function(ctx)
    assert(ctx.session_id == "session:origin")
    if options.stale then error("stale pane") end
    return {}, 1, state.window
  end }
  function state.open()
    return pcall(state.actions.tmux_copy_mode, { client_id = "client:caller",
      session_id = "session:origin", block_id = "block:origin" })
  end
  function state.restore()
    state.actions.tmux_copy_restore { session_id = "session:origin", block_id = "block:copy" }
  end
  return state
end
local function test(name, fn)
  local ok, err = pcall(fn)
  assert(ok, name .. ": " .. tostring(err)); passed = passed + 1
end

test("chunked capture preserves all text and uses a direct Neovim command", function()
  local s = fixture { chunked = true }; assert(s.open())
  assert(s.files["/tmp/private-copy"] == "α\ntail\n" and #s.calls == 2 and s.execs == 1)
  assert(s.created.session_id == "session:origin" and s.created.window_id == "window:origin")
  local opts = s.created.layout.block.options
  assert(opts.shell == "none" and opts.command[1] == "/bin/nvim")
  assert(opts.command[#opts.command - 1] == "--" and opts.command[#opts.command] == s.settings.path)
  assert(not s.settings.restore, "ordinary float closure must not launch a Rex CLI")
  assert(s.settings.clipboard == "/bin/pbcopy")
end)
test("network callers must not copy to the server's clipboard", function()
  local s = fixture { remote = true }; assert(s.open()); assert(not s.settings.clipboard)
end)
test("capture and launch failures clean temporary files", function()
  for _, option in ipairs({ "capture_error", "launch_error", "stalled" }) do
    local s = fixture { [option] = true, chunked = true }
    assert(not s.open()); assert(s.removed == "/tmp/private-copy" and next(s.files) == nil)
    if option ~= "launch_error" then assert(not s.created) end
  end
end)
test("missing dependencies and stale origins fail before capture", function()
  for _, option in ipairs({ "missing_nvim", "stale" }) do
    local s = fixture { [option] = true }
    assert(not s.open()); assert(s.execs == 0 and #s.calls == 0 and not s.created)
  end
end)
test("copy mode does not capture itself", function()
  local s = fixture(); s.window.layers[1].blocks[1].label = "copy-mode"
  assert(s.open()); assert(s.execs == 0 and not s.created)
end)
test("zoom is restored once only to the surviving original pane", function()
  for _, change in ipairs({ "unchanged", "focus", "pane", "window", "zoom" }) do
    local s = fixture { zoom = true }; assert(s.open()); assert(s.settings.restore == "/bin/rex")
    s.window.zoomed_block_id, s.window.focused_block_id = nil, "block:copy"
    if change == "focus" then s.window.focused_block_id = "other" end
    if change == "pane" then s.window.layers = {} end
    if change == "window" then s.window.window_id = "moved" end
    if change == "zoom" then s.window.zoomed_block_id = "other" end
    s.restore(); assert((s.zoom ~= nil) == (change == "unchanged"))
    if s.zoom then assert(s.zoom.block_id == "block:origin" and s.zoom.zoom) end
    s.zoom = nil; s.restore(); assert(not s.zoom)
  end
end)
print("PASS: " .. passed .. " copy mode scenarios")
