-- Exercise the real config against a small Rex API double. No server is used.
-- Usage: lua rex/test-config.lua [path/to/init.lua]
local config = arg[1] or "rex/init.lua"
local passed = 0

local function equal(actual, expected, message)
  assert(actual == expected, (message or "unexpected value") .. ": "
    .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function fixture(options)
  options = options or {}
  local state = { actions = {}, bindings = {}, modes = {}, queue = {}, calls = {}, logs = {} }
  local ctx
  local rex = { session = {}, client = {}, layout = {} }
  local function record(method, args)
    state.calls[#state.calls + 1] = { method = method, args = args }
  end
  function rex.bind(key, action, args)
    state.bindings[#state.bindings + 1] = { key = key, action = action, args = args }
  end
  function rex.bindings()
    local copy = {}
    for i, binding in ipairs(state.bindings) do copy[i] = binding end
    return copy
  end
  function rex.unbind(binding)
    for i, candidate in ipairs(state.bindings) do
      if candidate == binding then table.remove(state.bindings, i); return 1 end
    end
    error("unbinding an unknown binding")
  end
  function rex.mode(name, args) state.modes[name] = args end
  function rex.action(action)
    assert(not state.actions[action.name], "duplicate action " .. action.name)
    state.actions[action.name] = action
  end
  function rex.client.queue(action, args)
    state.queue[#state.queue + 1] = { action = action, args = args }
  end
  function rex.invoke(name)
    local ok, result = pcall(state.actions[name].run, ctx)
    if ok then return result else return nil, result end
  end
  function rex.session.view(args)
    record("view", args)
    return state.view, state.view_error
  end
  function rex.call(method, args)
    equal(method, "com.superlogical.terminal.process")
    record("process", args)
    return state.process, "no process metadata"
  end
  function rex.layout.block(args) return { block = args } end
  for _, method in ipairs({ "new_layer", "set_layer_state", "zoom_block" }) do
    rex.session[method] = function(args)
      record(method, args)
      if state.mutation_error then return nil, state.mutation_error end
      return { revision = 1 }
    end
  end
  function rex.log(level, message)
    state.logs[#state.logs + 1] = { level = level, message = message }
  end
  local env = setmetatable({
    rex = rex,
    os = { getenv = function(name)
      equal(name, "INTERDIMUX_ROOT")
      return options.root
    end },
    io = { open = function(path)
      state.integration_path = path
      if options.integration then return { close = function() end } end
    end },
    dofile = function()
      if options.integration == "syntax" then error("fixture syntax error") end
      return { setup = function(args)
        state.setup = args
        rex.action { name = "interdimux", run = function() error("fixture launch error") end }
        rex.bind("ctrl+b>f", "interdimux")
        rex.bind("ctrl+b>g", "interdimux_dashboard")
        if options.integration == "partial" then error("fixture setup error") end
        rex.bind(args.agent_next_key, "interdimux_agent_next")
      end }
    end,
  }, { __index = _G })
  assert(loadfile(config, "t", env))()
  function state.run(name, context)
    ctx = context or { session_id = "session", block_id = "b1" }
    state.queue, state.calls = {}, {}
    local ok, result = pcall(state.actions[name].run, ctx)
    -- Rex commits client actions only when the server callback succeeds.
    if not ok then state.queue = {} end
    return ok, result
  end
  function state.binding(key)
    local found
    for _, binding in ipairs(state.bindings) do
      if binding.key == key then assert(not found, "duplicate binding " .. key); found = binding end
    end
    return found
  end
  state.view = { active_window_id = "w2", windows = {
    { window_id = "w1", layers = {
      { layer_id = "t1", kind = "tiled", blocks = { { block_id = "b1" } } },
      { layer_id = "f1", kind = "floating", blocks = { { block_id = "float1" } } },
    } },
    { window_id = "w2", layers = {
      { kind = "tiled", blocks = { { block_id = "b2" } } },
    } },
    { window_id = "w3", layers = {
      { kind = "tiled", blocks = { { block_id = "b3" } } },
    } },
  } }
  return state
end

local function scratch(state, state_name)
  local layer = { layer_id = "scratch-layer", kind = "floating", state = state_name,
    blocks = { { block_id = "scratch-block", label = "scratch",
      flavor = "com.superlogical.terminal.shell" } } }
  table.insert(state.view.windows[1].layers, layer)
  return layer
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if not ok then io.stderr:write("FAIL: " .. name .. ": " .. tostring(err) .. "\n"); os.exit(1) end
  passed = passed + 1
end

test("navigation follows its origin, including floats, and wraps", function()
  local s = fixture()
  for _, case in ipairs({
    { "tmux_next_window", "b1", "w2" }, { "tmux_next_window", "float1", "w2" },
    { "tmux_previous_window", "b1", "w3" }, { "tmux_next_window", "b3", "w1" },
    { "tmux_previous_window", "b3", "w2" },
  }) do
    assert(s.run(case[1], { session_id = "session", block_id = case[2] }))
    equal(#s.calls, 1, "navigation API calls")
    equal(#s.queue, 1)
    equal(s.queue[1].action, "session.select")
    equal(s.queue[1].args.session_id, "session")
    equal(s.queue[1].args.window_id, case[3])
  end
end)

test("numbered windows are local and absent numbers do nothing", function()
  local s = fixture()
  for number = 1, 9 do
    assert(s.run("tmux_window_" .. number))
    equal(#s.calls, 1)
    equal(#s.queue, number <= 3 and 1 or 0)
    if number <= 3 then equal(s.queue[1].args.window_id, "w" .. number) end
  end
end)

test("palette context uses the active window", function()
  local s = fixture()
  assert(s.run("tmux_next_window", { session_id = "session" }))
  equal(s.queue[1].args.window_id, "w3")
end)

test("stale and missing origins never fall back to another window", function()
  local s = fixture()
  for _, name in ipairs({ "tmux_next_window", "tmux_window_1", "tmux_scratch" }) do
    for _, ctx in ipairs({ {}, { session_id = "session", block_id = "deleted" } }) do
      local ok = s.run(name, ctx)
      assert(not ok); equal(#s.queue, 0)
      assert(#s.calls <= 1, "stale origin caused a mutation")
    end
  end
  s.view, s.view_error = nil, "disconnected"
  local ok, err = s.run("tmux_next_window")
  assert(not ok); equal(err, "disconnected")
end)

test("scratch inherits foreground or child cwd and targets its origin", function()
  for _, process in ipairs({ { foreground = { cwd = "/project" } }, { child = { cwd = "/project" } } }) do
    local s = fixture(); s.process = process
    assert(s.run("tmux_scratch"))
    equal(#s.calls, 3)
    local args = s.calls[3].args
    equal(args.window_id, "w1"); equal(args.session_id, "session"); equal(args.focus, true)
    equal(args.layout.block.options.cwd, "/project")
    equal(args.layout.block.label, "scratch")
    equal(args.bounds[3], 0.7)
  end
end)

test("scratch tolerates missing process metadata", function()
  local s = fixture()
  assert(s.run("tmux_scratch"))
  equal(s.calls[3].args.layout.block.options.cwd, nil)
  assert(s.run("tmux_scratch", { session_id = "session" }))
  equal(#s.calls, 2)
  equal(s.calls[2].args.window_id, "w2")
end)

test("scratch reuses its layer without starting or inspecting a process", function()
  local s = fixture(); local layer = scratch(s)
  for _, case in ipairs({
    { "b1", nil, "normal", true },
    { "scratch-block", nil, "minimized", false },
    { "scratch-block", "minimized", "normal", true },
  }) do
    layer.state = case[2]
    assert(s.run("tmux_scratch", { session_id = "session", block_id = case[1] }))
    equal(#s.calls, 2); equal(s.calls[2].method, "set_layer_state")
    equal(s.calls[2].args.layer_id, "scratch-layer")
    equal(s.calls[2].args.state, case[3]); equal(s.calls[2].args.focus, case[4])
  end
end)

test("ambiguous scratch labels fail without touching either process", function()
  local s = fixture(); scratch(s); scratch(s)
  local ok, err = s.run("tmux_scratch")
  assert(not ok and tostring(err):find("More than one scratch", 1, true))
  equal(#s.calls, 1)
end)

test("scratch restores zoom only while its return pane remains in the tab", function()
  for _, origin_survives in ipairs({ true, false }) do
    local s = fixture(); scratch(s)
    s.view.windows[1].zoomed_block_id = "b1"
    assert(s.run("tmux_scratch"))
    s.view.windows[1].zoomed_block_id = nil
    if not origin_survives then s.view.windows[1].layers[1].blocks = {} end
    assert(s.run("tmux_scratch", { session_id = "session", block_id = "scratch-block" }))
    equal(#s.calls, origin_survives and 3 or 2)
    if origin_survives then
      equal(s.calls[3].method, "zoom_block")
      equal(s.calls[3].args.block_id, "b1"); equal(s.calls[3].args.zoom, true)
    end
    -- A later unzoomed visit must not restore stale zoom.
    assert(s.run("tmux_scratch", { session_id = "session", block_id = "float1" }))
    assert(s.run("tmux_scratch", { session_id = "session", block_id = "scratch-block" }))
    equal(#s.calls, 2)
  end
end)

test("scratch creation and toggle failures remain visible", function()
  local s = fixture(); s.mutation_error = "host unavailable"
  local ok, err = s.run("tmux_scratch")
  assert(not ok); equal(err, "host unavailable")
  scratch(s)
  ok, err = s.run("tmux_scratch")
  assert(not ok); equal(err, "host unavailable")
end)

test("native menu actions exit before opening prompts or splitting", function()
  local s = fixture()
  for _, case in ipairs({
    { "tmux_menu_rename_pane", "pane.rename" },
    { "tmux_menu_split_right", "pane.split.right" },
    { "tmux_history_find", "client.find.open" },
    { "tmux_history_copy", "pane.copy" },
  }) do
    assert(s.run(case[1])); equal(#s.queue, 3)
    equal(s.queue[1].action, "client.mode.enter")
    equal(s.queue[2].action, "client.mode.exit_all")
    equal(s.queue[3].action, case[2])
  end
  assert(s.run("tmux_menu_cancel")); equal(#s.queue, 2)
end)

test("server menu actions preserve context and report failures", function()
  local s = fixture()
  assert(s.run("tmux_menu_scratch", { session_id = "session", block_id = "b3" }))
  equal(s.calls[3].args.window_id, "w3"); equal(#s.queue, 2)
  s.mutation_error = "host unavailable"
  local ok, err = s.run("tmux_menu_scratch")
  assert(not ok); equal(err, "host unavailable"); equal(#s.queue, 0)
end)

test("optional integration missing, syntax and partial failures fall back cleanly", function()
  for _, integration in ipairs({ false, "syntax", "partial" }) do
    local s = fixture { integration = integration }
    equal(s.binding("ctrl+b>f").action, "pane.go_to")
    equal(s.binding("ctrl+b>w").action, "pane.go_to")
    equal(s.binding("ctrl+b>g").action, "client.palette.toggle")
    equal(s.binding("ctrl+b>c").action, "client.tab.new")
    equal(s.binding("ctrl+b>tab").action, "client.sidebar.activity.toggle")
    if integration then equal(#s.logs, 1); equal(s.logs[1].level, "warn") end
    assert(s.run("tmux_menu_navigator"))
    equal(s.queue[3].action, "pane.go_to")
  end
end)

test("integration root and setup options are preserved", function()
  for _, root in ipairs({ "", "/custom/checkout" }) do
    local s = fixture { integration = "success", root = root }
    equal(s.setup.root, root == "" and "/opt/tools/interdimux" or root)
    equal(s.setup.dashboard_ui, "terminal")
    equal(s.binding("ctrl+b>tab").action, "interdimux_agent_next")
    equal(s.binding("ctrl+b>w").action, "interdimux")
    local ok, err = s.run("tmux_menu_navigator")
    assert(not ok and tostring(err):find("fixture launch error", 1, true))
    equal(#s.queue, 0)
  end
end)

print("PASS: " .. passed .. " Lua behavioral scenarios")
