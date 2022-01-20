
-- assert functions

local assert_result

local function abort()
  error()
end

local function assert(to_test, msg)
  if not to_test then
    assert_result = {msg = msg}
    abort()
  end
  return to_test
end

local function assert_equals(expected, got)
  if got ~= expected then
    assert_result = {
      msg = "expected '"..tostring(expected).."', got '"..tostring(got).."'",
    }
    abort()
  end
end

local function assert_not_equals(expected, got)
  if got == expected then
    assert_result = {
      msg = "expected and got '"..tostring(got).."' when they should be different",
    }
    abort()
  end
end

-- test runner

---@class Test
---@field run fun()
---A pattern. If provided `run` must error with a message matching the pattern
---@field expected_error string

---@type table<string, Test>
local tests = {}

local function write_result(player_data, test, test_profiler, passed, msg, tooltip)
  player_data.scroll_pane.add{
    type = "label",
    caption = {
      "",
      "[font=default-bold]"..test.name.."[/font] [color="..(passed and "#00FF00" or "#FF0000").."]"..(passed and "passed" or "failed").."[/color] "
      , ""..
      -- "(", test_profiler, ")"..
      (msg and (": "..msg) or ""),
    },
    tooltip = tooltip,
  }
  log{
    "",
    test.name.." "..(passed and "passed" or "failed").." (",
    test_profiler,
    ")"..(msg and (": "..msg) or ""),
  }
end

local function run_tests(player_data)
  local test_profiler = game.create_profiler(true)
  local test_count = 0
  local main_profiler = game.create_profiler()
  for name, test in pairs(tests) do
    test_count = test_count + 1
    test.name = name
    assert_result = nil
    local stacktrace
    test_profiler.reset()
    local success, result = xpcall(test.run, function(msg)
      test_profiler.stop()
      stacktrace = debug.traceback(nil, 2)
      return msg:match("%.lua:%d+: (.*)")
    end)
    test_profiler.stop()
    if success then
      if test.expected_error then
        write_result(player_data, test, test_profiler, false, "expected error '"..test.expected_error.."'")
      else
        write_result(player_data, test, test_profiler, true)
      end
    elseif assert_result then
      write_result(player_data, test, test_profiler, false, assert_result.msg)
    else
      if test.expected_error then
        if result:find(test.expected_error) then
          write_result(player_data, test, test_profiler, true)
        else
          write_result(player_data, test, test_profiler, false, "expected error '"..test.expected_error.."', got '"..result.."'", stacktrace)
        end
      else
        write_result(player_data, test, test_profiler, false, "unexpected error '"..result.."'", stacktrace)
      end
    end
  end
  main_profiler.stop()
  log{"", "Ran "..test_count.." tests in ", main_profiler}
end

-- gui init

script.on_init(function()
  global.players = {}
end)

local function on_res_change(player_data)
  ---@type table
  local style = player_data.frame.style
  ---@type table
  local res = player_data.player.display_resolution
  ---@type number
  style.width = res.width
  ---@type number
  style.height = res.height
end

script.on_event(defines.events.on_player_created, function(event)
  -- I think there was some need for it to be unpaused for syncing breakpoints or so
  game.tick_paused = false
  -- no need for this to autosave
  game.autosave_enabled = false

  ---@type table
  local player = game.get_player(event.player_index)
  ---@type table
  local gvs = player.game_view_settings
  gvs.show_controller_gui = false
  gvs.show_minimap = false
  gvs.show_research_info = false
  gvs.show_entity_info = false
  gvs.show_alert_gui = false
  gvs.update_entity_selection = false
  gvs.show_rail_block_visualisation = false
  gvs.show_side_menu = false
  gvs.show_map_view_options = false
  gvs.show_quickbar = false
  gvs.show_shortcut_bar = false

  ---@type table
  local frame = player.gui.screen.add{
    type = "frame",
    caption = "Tests",
    direction = "vertical",
  }

  ---@type table
  local scroll_pane = frame.add{
    type = "scroll-pane",
    direction = "horizontal",
  }
  scroll_pane.style.horizontally_stretchable = true
  scroll_pane.style.vertically_stretchable = true

  local player_data = {
    player = player,
    scroll_pane = scroll_pane,
    frame = frame,
  }
  global.players[event.player_index] = player_data

  on_res_change(player_data)

  run_tests(player_data)
end)

script.on_event(defines.events.on_player_display_resolution_changed, function(event)
  on_res_change(global.players[event.player_index])
end)

return {
  assert = assert,
  assert_equals = assert_equals,
  assert_not_equals = assert_not_equals,
  tests = tests,
}
