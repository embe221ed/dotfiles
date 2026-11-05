-- Tmux-style keys from interdotensional/templates/tmux/parts/.
-- Press and release Ctrl+B, then press the next key.
-- Rex windows within a session are displayed as tabs in the macOS app.
local function context_window(ctx, view)
  for index, window in ipairs(view.windows or {}) do
    if ctx.block_id then
      for _, layer in ipairs(window.layers or {}) do
        for _, block in ipairs(layer.blocks or {}) do
          if block.block_id == ctx.block_id then return index, window end
        end
      end
    elseif window.window_id == view.active_window_id then
      return index, window
    end
  end
  error("The originating Rex window no longer exists", 0)
end

local function context_view(ctx)
  if not ctx.session_id then error("Select a Rex session first", 0) end
  local view, err = rex.session.view { session_id = ctx.session_id }
  if not view then error(err or "Cannot read the Rex session", 0) end
  local index, window = context_window(ctx, view)
  return view, index, window
end

rex.bind("ctrl+b>c", "client.tab.new")
rex.bind("ctrl+b>,", "client.tab.rename")
rex.bind("ctrl+b>r", "pane.rename") -- comma still renames the tab.
rex.bind("ctrl+b>shift+1", "pane.move_to_new_tab") -- !
rex.bind("ctrl+b>o", "pane.focus_next")
rex.bind("ctrl+b>shift+4", "session.rename") -- $
rex.bind("ctrl+b>shift+/", "client.palette.toggle") -- ?; searchable help/actions
rex.bind("ctrl+b>d", "pane.float")

-- client.tab.next/previous cross session boundaries. Derive the target from
-- the initiating pane (including floats), then select it in this client.
-- session.focus_next_window changes server state but doesn't switch Mac tabs.
for _, navigation in ipairs({
  { key = "n", name = "tmux_next_window", delta = 1, title = "Next Window in Session" },
  { key = "p", name = "tmux_previous_window", delta = -1, title = "Previous Window in Session" },
}) do
  rex.action {
    name = navigation.name,
    title = navigation.title,
    category = "Navigation",
    run = function(ctx)
      local view, index = context_view(ctx)
      local target = view.windows[(index - 1 + navigation.delta) % #view.windows + 1]
      rex.client.queue("session.select", {
        session_id = ctx.session_id, window_id = target.window_id,
      })
    end,
  }
  rex.bind("ctrl+b>" .. navigation.key, navigation.name)
end

-- Match tmux's base-index=1. Native client.tab.goto can include other sessions.
-- An absent number is a no-op, never a jump into another session.
for number = 1, 9 do
  local name = "tmux_window_" .. number
  rex.action {
    name = name, title = "Window " .. number .. " in Session", category = "Navigation",
    run = function(ctx)
      local view = context_view(ctx)
      local target = view.windows[number]
      if target then
        rex.client.queue("session.select", {
          session_id = ctx.session_id, window_id = target.window_id,
        })
      end
    end,
  }
  rex.bind("ctrl+b>" .. number, name)
end

-- Match ~/.tmux.conf: | splits right, - splits down (rather than % and ").
-- Rex matches unshifted keys, so | is Shift+Backslash on this keyboard layout.
rex.bind("ctrl+b>shift+\\", "pane.split", { direction = "right" })
rex.bind("ctrl+b>-", "pane.split", { direction = "down" })

-- One prefix per movement. Persistent navigation is opt-in with prefix+Enter.
-- Exclusive modes ignore unbound keys; leave with q or Escape before typing.
rex.mode("panes", { exclusive = true })
rex.bind("ctrl+b>enter", "client.mode.enter", { name = "panes" })
for _, movement in ipairs({
  { key = "h", direction = "left" },
  { key = "j", direction = "down" },
  { key = "k", direction = "up" },
  { key = "l", direction = "right" },
}) do
  local focus = { direction = movement.direction }
  -- Rex measures this in percent of the split, rather than tmux's two cells.
  local resize = { direction = movement.direction, amount = 2 }
  rex.bind("ctrl+b>" .. movement.key, "pane.focus", focus)
  rex.bind("ctrl+b>ctrl+" .. movement.key, "pane.resize", resize)
  rex.bind("ctrl+b>shift+" .. movement.key, "pane.resize", resize)
  rex.bind("ctrl+b>alt+" .. movement.key, "pane.move." .. movement.direction)
  -- Use Rex's compact native groups for stable hint sizing on mode changes.
  rex.bind("panes/" .. movement.key, "pane.focus." .. movement.direction)
  rex.bind("panes/shift+" .. movement.key, "pane.resize", resize)
  rex.bind("panes/ctrl+" .. movement.key, "pane.resize", resize)
  rex.bind("panes/alt+" .. movement.key, "pane.move." .. movement.direction)
end
rex.bind("ctrl+b>z", "pane.zoom")
rex.bind("panes/z", "pane.zoom")
rex.bind("ctrl+b>=", "pane.balance")
rex.bind("panes/=", "pane.balance")
rex.bind("ctrl+b>m", "pane.minimize_all_floating")
rex.bind("panes/q", "client.mode.exit_all")
rex.bind("panes/escape", "client.mode.exit_all")
rex.bind("panes/enter", "client.mode.exit_all")
rex.bind("panes/ctrl+c", "client.mode.exit_all")
rex.bind("panes/d", "pane.float")

-- Native scrollback search. Rex has no tmux-fuzzback or vi copy-mode yet.
rex.bind("ctrl+b>/", "client.find.open")
rex.bind("shift+pageup", "client.scroll.page_up")
rex.bind("shift+pagedown", "client.scroll.page_down")

-- Native history browsing until Rex gains vi selection. Plain typing is blocked.
rex.mode("history", { exclusive = true })
rex.bind("ctrl+b>[", "client.mode.enter", { name = "history" })
for _, key in ipairs({ "k", "pageup", "ctrl+u" }) do
  rex.bind("history/" .. key, "client.scroll.page_up")
end
for _, key in ipairs({ "j", "pagedown", "ctrl+d" }) do
  rex.bind("history/" .. key, "client.scroll.page_down")
end
rex.bind("history/shift+k", "client.prompt.previous")
rex.bind("history/shift+j", "client.prompt.next")
rex.bind("history/n", "client.find.next")
rex.bind("history/shift+n", "client.find.previous")
for _, key in ipairs({ "q", "escape", "enter", "ctrl+c", "f12" }) do
  rex.bind("history/" .. key, "client.mode.exit_all")
end
for _, item in ipairs({
  { key = "/", name = "tmux_history_find", title = "Find in History", action = "client.find.open" },
  { key = "y", name = "tmux_history_copy", title = "Copy Selection and Leave History", action = "pane.copy" },
}) do
  rex.action {
    name = item.name, title = item.title, category = "History",
    run = function()
      rex.client.queue("client.mode.enter", { name = "history" })
      rex.client.queue("client.mode.exit_all")
      rex.client.queue(item.action)
    end,
  }
  rex.bind("history/" .. item.key, item.name)
end

-- Forward the prefix to terminal programs (including an inner tmux).
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })

-- F12 routes the prefix directly to an inner tmux, without a second prefix.
-- Escape must be forwarded explicitly, or Rex would leave the mode on Escape.
rex.bind("f12", "client.mode.enter", { name = "tmux-passthrough" })
-- Like an unbound F12 in tmux's pane table, first leave pane mode. A second
-- F12 then enables passthrough. Keep both transitions entirely client-side.
rex.bind("panes/f12", "client.mode.exit_all")
rex.bind("tmux-passthrough/f12", "client.mode.exit")
rex.bind("tmux-passthrough/ctrl+b", "pane.send_key", { key = "ctrl+b" })
rex.bind("tmux-passthrough/escape", "pane.send_key", { key = "escape" })

-- Preview.26 provides a native new-shell float with directory inheritance and
-- the app's shell settings. pane.float instead moves the existing terminal.
rex.bind("ctrl+b>shift+8", "pane.new_floating") -- *

-- One reusable scratch shell per tab. Minimize it without stopping its process;
-- summon it from any pane in that tab. The reserved label makes reloads stateless.
-- Only the return zoom is transient; Rex already remembers the previous layer.
local scratch_zoom = {}
rex.action {
  name = "tmux_scratch", title = "Toggle Scratch Terminal", category = "Pane",
  run = function(ctx)
    local _, _, window = context_view(ctx)
    local key = (ctx.server or "") .. "|" .. ctx.session_id .. "|" .. window.window_id
    local scratch
    for _, layer in ipairs(window.layers or {}) do
      local blocks = layer.blocks or {}
      if layer.kind == "floating" and #blocks == 1
          and blocks[1].label == "scratch"
          and blocks[1].flavor == "com.superlogical.terminal.shell" then
        if scratch then error("More than one scratch terminal in this tab; rename one", 0) end
        scratch = layer
      end
    end
    if scratch then
      local hide = scratch.state ~= "minimized" and scratch.blocks[1].block_id == ctx.block_id
      local result, err = rex.session.set_layer_state {
        session_id = ctx.session_id, layer_id = scratch.layer_id,
        state = hide and "minimized" or "normal", focus = not hide,
      }
      if not result then error(err or "Cannot toggle the scratch terminal", 0) end
      local return_zoom = scratch_zoom[key]
      scratch_zoom[key] = not hide and window.zoomed_block_id or nil
      if hide and return_zoom then
        -- Do not follow a pane that was closed, moved to another tab, or hidden.
        for _, layer in ipairs(window.layers or {}) do
          for _, block in ipairs(layer.blocks or {}) do
            if layer.state ~= "minimized" and block.block_id == return_zoom then
              local restored, zoom_error = rex.session.zoom_block {
                session_id = ctx.session_id, block_id = return_zoom, zoom = true,
              }
              if not restored then rex.log("warn", "Cannot restore scratch return zoom: " .. tostring(zoom_error)) end
            end
          end
        end
      end
      return result
    end
    local process
    if ctx.block_id then
      process = rex.call("com.superlogical.terminal.process", {
        session_id = ctx.session_id, block_id = ctx.block_id, args = {},
      })
    end
    local cwd = process and ((process.foreground or {}).cwd or (process.child or {}).cwd)
    local result, err = rex.session.new_layer {
      session_id = ctx.session_id, window_id = window.window_id,
      bounds = { 0.15, 0.15, 0.7, 0.7 }, focus = true,
      layout = rex.layout.block {
        flavor = "com.superlogical.terminal.shell", label = "scratch", options = { cwd = cwd },
      },
    }
    if not result then error(err or "Cannot create the scratch terminal", 0) end
    scratch_zoom[key] = window.zoomed_block_id
    return result
  end,
}
rex.bind("alt+p", "tmux_scratch")

-- Native key hints act as the action menu. Keep it exclusive until the chosen
-- action replies: once=true would let fast following keys reach the terminal
-- while the server is still performing the selected operation.
rex.mode("actions", { exclusive = true })
rex.bind("ctrl+b>a", "client.mode.enter", { name = "actions" })
local function queue_menu_exit()
  -- Menu actions also appear in the command palette. Ensure a mode exists
  -- there, since the client rejects exit_all when no mode is active.
  rex.client.queue("client.mode.enter", { name = "actions" })
  rex.client.queue("client.mode.exit_all")
end
-- Keep the submenu handoff client-side, so the following pane key is handled
-- immediately. Pane exits clear both modes instead of returning to this menu.
rex.bind("actions/m", "client.mode.enter", { name = "panes" })
rex.bind("actions/[", "client.mode.enter", { name = "history" })

local function menu_action(name, key, title, category, target)
  rex.action {
    name = name, title = title, category = category,
    run = function()
      queue_menu_exit()
      if target then
        if target:find(".", 1, true) then
          rex.client.queue(target)
        else
          local _, err = rex.invoke(target)
          if err then error(err, 0) end
        end
      end
    end,
  }
  rex.bind("actions/" .. key, name)
end
menu_action("tmux_menu_split_right", "shift+\\", "Split Pane Right", "Pane", "pane.split.right")
menu_action("tmux_menu_split_down", "-", "Split Pane Down", "Pane", "pane.split.down")
menu_action("tmux_menu_floating", "shift+8", "New Floating Terminal", "Pane", "pane.new_floating")
menu_action("tmux_menu_toggle_float", "d", "Float / Dock Pane", "Pane", "pane.float")
menu_action("tmux_menu_rename_pane", "r", "Rename Pane", "Pane", "pane.rename")
menu_action("tmux_menu_balance", "=", "Balance Splits", "Pane", "pane.balance")
menu_action("tmux_menu_scratch", "p", "Scratch Terminal", "Pane", "tmux_scratch")
menu_action("tmux_menu_new_window", "c", "New Tab", "Tab", "client.tab.new")
menu_action("tmux_menu_rename_window", ",", "Rename Tab", "Tab", "client.tab.rename")
menu_action("tmux_menu_break_pane", "shift+1", "Move Pane to New Tab", "Pane", "pane.move_to_new_tab")
menu_action("tmux_menu_zoom", "z", "Zoom Pane", "Pane", "pane.zoom")
-- Keep cancellation ordered with menu operations handled by the server.
menu_action("tmux_menu_cancel", "q", "Exit Menu", "Keys")
rex.bind("actions/escape", "tmux_menu_cancel")

-- Interdimux owns the navigator and Rex hosting; this checkout selects its install.
local interdimux_root = os.getenv("INTERDIMUX_ROOT")
if not interdimux_root or interdimux_root == "" then interdimux_root = "/opt/tools/interdimux" end
local interdimux_integration = interdimux_root .. "/integrations/rex.lua"
local interdimux_file = io.open(interdimux_integration, "rb")
local interdimux_loaded = false
if interdimux_file then
  interdimux_file:close()
  local binding_count = #rex.bindings()
  local ok, err = pcall(function()
    dofile(interdimux_integration).setup {
      root = interdimux_root, dashboard_ui = "terminal",
      agent_next_key = "ctrl+b>tab",
    }
  end)
  interdimux_loaded = ok
  if not ok then
    local bindings = rex.bindings()
    for index = binding_count + 1, #bindings do rex.unbind(bindings[index]) end
    rex.log("warn", "Interdimux unavailable; using native navigation: " .. tostring(err))
  end
end
if interdimux_loaded then
  rex.bind("ctrl+b>w", "interdimux")
  rex.bind("ctrl+b>e", "interdimux_agents")
  menu_action("tmux_menu_navigator", "w", "Switch Session, Window or Pane", "Navigation", "interdimux")
else
  -- Core navigation remains usable on another machine or during an integration
  -- edit. Overwrite any partial setup bindings if setup raised after binding.
  rex.bind("ctrl+b>f", "pane.go_to")
  rex.bind("ctrl+b>w", "pane.go_to")
  rex.bind("ctrl+b>g", "client.palette.toggle")
  rex.bind("ctrl+b>e", "client.sidebar.activity.toggle")
  rex.bind("ctrl+b>tab", "client.sidebar.activity.toggle")
  menu_action("tmux_menu_navigator", "w", "Go to Anything", "Navigation", "pane.go_to")
end
