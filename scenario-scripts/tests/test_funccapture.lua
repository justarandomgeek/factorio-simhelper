
---cSpell:ignore simhelper, funccapture, upval, deduplication

local runner = require("__simhelper__.scenario-scripts.tests.test_runner")
local tests = runner.tests
local assert = runner.assert
local assert_equals = runner.assert_equals
local assert_not_equals = runner.assert_not_equals

local func_capture = require("__simhelper__.funccapture")
local capture = func_capture.capture

local function add_test(test)
  tests[test.name] = test
  local run = test.run
  test.run = function()
    run()
    -- universal teardown
    _ENV.__simhelper_funccapture.c_func_lut_cache = nil
    _ENV.__simhelper_funccapture.next_func_id = 0
    _ENV.__funccapture_result0 = nil
  end
end

add_test{
  name = "pure function",
  run = function()
    -- act
    local captured = capture(function()
      return 100
    end)
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert_equals(100, result)
  end,
}

for _, data in pairs{
  {type = "nil", value = nil},
  {type = "number", value = 150},
  {type = "string", value = "hello world"},
  {label = "true", type = "boolean", value = true},
  {label = "false", type = "boolean", value = false},
}
do
  add_test{
    name = "primitive "..(data.label or data.type).." upval",
    run = function()
      -- arrange
      local value = data.value
      local captured = capture(function()
        return value
      end)
      -- act
      local loaded = assert(load(captured))
      local result = loaded()
      -- assert
      assert_equals(value, result)
    end,
  }
end

add_test{
  name = "special string upval",
  run = function()
    -- arrange
    local bytes = {}
    for i = 0, 255 do
      bytes[i + 1] = i
    end
    local value = string.char(table.unpack(bytes))
    -- act
    local captured = capture(function()
      return value
    end)
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert_equals(value, result)
  end,
}

add_test{
  name = "c function upval",
  run = function()
    -- arrange
    local concat = table.concat
    -- act
    local captured = capture(function()
      return concat
    end)
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert_equals(table.concat, result)
  end,
}

add_test{
  name = "invalid c function upval",
  run = function()
    -- arrange
    local gmatch_iter = string.gmatch("", "")
    -- act
    capture(function()
      return gmatch_iter
    end)
  end,
  expected_error = "Unable to capture unknown C function",
}

add_test{
  name = "preserve iteration order with back refs",
  run = function()
    -- arrange
    local value = {1}
    value[value] = 2
    value.foo = 3
    local captured = capture(function()
      return value
    end)
    -- act
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert_not_equals(value, result)
    -- TODO: write custom table comparison, [...]
    -- serpent actually doesn't preserve iteration order in this case, so it's not a good test
    assert_equals(serpent.dump(value), serpent.dump(result))
  end,
}

add_test{
  name = "upval in function upval",
  run = function()
    -- arrange
    local function upval()
      return 100
    end
    local captured = capture(function()
      return upval()
    end)
    -- act
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert_equals(100, result)
  end,
}

add_test{
  name = "upval in function upval loop",
  run = function()
    -- arrange
    local func
    local function upval()
      local _ = func
      return 100
    end
    function func()
      return upval()
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert_equals(100, result)
  end,
}

add_test{
  name = "upval deduplication",
  run = function()
    -- arrange
    local value = {}
    local function upval1()
      return value
    end
    local function upval2()
      return upval1()
    end
    -- act
    local captured = capture(function()
      return upval1(), upval2()
    end)
    local loaded = assert(load(captured))
    local result1, result2 = loaded()
    -- assert
    assert_equals(result1, result2)
  end,
}

add_test{
  name = "upval of itself",
  run = function()
    -- arrange
    local func
    local function upval()
      return func
    end
    function func()
      return upval()
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local restored = loaded()
    -- assert
    assert_equals(restored, restored())
  end,
}

add_test{
  name = "result func cache",
  run = function()
    -- arrange
    local foo = {}
    local function func()
      return foo
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local restored1 = loaded()
    local restored2 = loaded()
    -- assert
    assert_equals(restored1, restored2)
  end,
}
