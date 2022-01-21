
---cSpell:ignore simhelper, bytecode, autosave, visualisation, quickbar, subfooter

local deep_compare = require("__simhelper__.scenario-scripts.tests.deep_compare")

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

local function assert_contents_equals(expected, got)
  local equal, difference = deep_compare.deep_compare(expected, got)
  if not equal then
    local msg
    if difference.type == deep_compare.difference_type.value_type then
      msg = "expected type '"..type(difference.left).."', got '"
        ..type(difference.right).."' at "..difference.location
    elseif difference.type == deep_compare.difference_type.function_bytecode then
      msg = "function bytecode differs at "..difference.location
    elseif difference.type == deep_compare.difference_type.primitive_value then
      msg = "expected '"..tostring(difference.left).."', got '"
        ..tostring(difference.right).."' at "..difference.location
    elseif difference.type == deep_compare.difference_type.size then
      msg = "table size differs at "..difference.location
    end
    assert_result = {
      msg = msg,
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

local function write_to_output(player_data, gui_str, log_str, tooltip)
  player_data.scroll_pane.add{
    type = "label",
    tooltip = tooltip,
    -- have to set caption after the fact because a LuaProfiler cannot be
    -- in a property tree which is what `add` is using.
    -- see https://forums.factorio.com/viewtopic.php?p=560263#p560263
  }.caption = gui_str
  log(log_str)
end

local function write_result(player_data, test, test_profiler, passed, msg, tooltip)
  write_to_output(
    player_data,
    {
      "",
      "[font=default-bold]"..test.name.."[/font] [color="..(passed and "#00FF00" or "#FF0000")
        .."]"..(passed and "passed" or "failed").."[/color] (",
      test_profiler,
      ")"..(msg and (": "..msg) or ""),
    },
    {
      "",
      test.name.." "..(passed and "passed" or "failed").." (",
      test_profiler,
      ")"..(msg and (": "..msg) or ""),
    },
    tooltip
  )
end

local function run_tests(player_data)
  local test_profiler = game.create_profiler(true)
  local test_count = 0
  local success_count = 0
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
        success_count = success_count + 1
      end
    elseif assert_result then
      write_result(player_data, test, test_profiler, false, assert_result.msg)
    else
      if test.expected_error then
        if result:find(test.expected_error) then
          write_result(player_data, test, test_profiler, true)
          success_count = success_count + 1
        else
          write_result(player_data, test, test_profiler, false, "expected error '"..test.expected_error.."', got '"..result.."'", stacktrace)
        end
      else
        write_result(player_data, test, test_profiler, false, "unexpected error '"..result.."'", stacktrace)
      end
    end
  end
  main_profiler.stop()

  player_data.subfooter_label.caption = {
    "",
    "Ran "..test_count.." tests in ",
    main_profiler,
    success_count ~= test_count and (", [color=#ff0000]"..(test_count - success_count).." failed[/color]") or ""
  }
  log{
    "",
    "Ran "..test_count.." tests in ",
    main_profiler,
    success_count ~= test_count and (", "..(test_count - success_count).." failed") or ""
  }
end

-- gui init

script.on_init(function()
  global.players = {}
end)

local function on_res_change(player_data)
  local style = player_data.frame.style
  local res = player_data.player.display_resolution
  style.width = res.width
  style.height = res.height
end

script.on_event(defines.events.on_player_created, function(event)
  -- I think there was some need for it to be unpaused for syncing breakpoints or so
  game.tick_paused = false
  -- no need for this to autosave
  game.autosave_enabled = false

  local player = game.get_player(event.player_index)
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

  local frame = player.gui.screen.add{
    type = "frame",
    caption = "Tests",
    direction = "horizontal",
  }

  local inside_shallow_frame = frame.add{
    type = "frame",
    style = "inside_shallow_frame",
    direction = "vertical",
  }

  local scroll_pane = inside_shallow_frame.add{
    type = "scroll-pane",
    style = "scroll_pane_in_shallow_frame",

    -- as you'd guess, this is for being under a sub header,
    -- but for some reason there is hardly any shadow at the bottom
    -- and no shadow on the right next to the scroll bar
    -- could be that this doesn't have shadows
    -- (so it's just got shadows from the parent frame),
    -- while scroll_pane_in_shallow_frame has overlapping shadows
    -- with the parent frame. Maybe
    -- style = "scroll_pane_under_subheader",
  }
  scroll_pane.style.horizontally_stretchable = true
  scroll_pane.style.vertically_stretchable = true
  scroll_pane.style.padding = 4
  scroll_pane.style.extra_padding_when_activated = 0

  local subfooter_frame = inside_shallow_frame.add{
    type = "frame",
    style = "subfooter_frame",
  }
  subfooter_frame.style.horizontally_stretchable = true

  local subfooter_label = subfooter_frame.add{
    type = "label",
    style = "subheader_caption_label",
  }

  local player_data = {
    player = player,
    frame = frame,
    scroll_pane = scroll_pane,
    subfooter_label = subfooter_label,
  }
  global.players[event.player_index] = player_data

  on_res_change(player_data)

  run_tests(player_data)
end)

script.on_event(defines.events.on_player_display_resolution_changed, function(event)
  on_res_change(global.players[event.player_index])
end)

return {
  tests = tests,
  assert = assert,
  assert_equals = assert_equals,
  assert_not_equals = assert_not_equals,
  assert_contents_equals = assert_contents_equals,
}
