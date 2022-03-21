
---cSpell:ignore simhelper, funccapture, upval, deduplication, metatable, metamethod

local runner = require("__simhelper__.scenario-scripts.tests.test_runner")
local tests = runner.tests
local assert = runner.assert
local assert_equals = runner.assert_equals
local assert_nan = runner.assert_nan
local assert_not_equals = runner.assert_not_equals
local assert_contents_equals = runner.assert_contents_equals

local func_capture = require("__simhelper__.funccapture")
local capture = func_capture.capture

local function add_test(test)
  tests[test.name] = test
  local run = test.run
  test.run = function()
    -- universal arrange
    -- this should actually be teardown, but since the given `run` function can
    -- error as part of tests, it's by far easier to just do it before calling it
    local tables_to_ignore = __simhelper_funccapture.tables_to_ignore
    local k = next(tables_to_ignore)
    while k do
      local prev_k = k
      k = next(tables_to_ignore, k)
      if prev_k ~= __simhelper_funccapture then
        tables_to_ignore[prev_k] = nil
      end
    end

    local number_cache = __simhelper_funccapture.number_cache
    k = next(number_cache)
    while k do
      local prev_k = k
      k = next(number_cache, k)
      if prev_k ~= 1/0 and prev_k ~= -1/0 then
        number_cache[prev_k] = nil
      end
    end

    __simhelper_funccapture.c_func_lut_cache = nil
    __simhelper_funccapture.next_func_id = 0
    for i = 0, 1/0 do
      if _ENV["__funccapture_result"..i] then
        rawset(_ENV, "__funccapture_result"..i, nil) -- bypass undefined global check
      else
        break
      end
    end

    run()
  end
end

add_test{
  name = "pure function",
  run = function()
    -- arrange
    local function func()
      return 100
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert_equals(100, result)
  end,
}

for _, data in pairs{
  {label = "nil", value = nil},
  {label = "integer", value = 150},
  {label = "number", value = 1.5}, -- 1.5 in double can't be represented perfectly
  {label = "nan", value = 0/0},
  {label = "inf", value = 1/0},
  {label = "-inf", value = -1/0},
  {label = "string", value = "hello world"},
  {label = "special string", value = (function()
    local bytes = {}
    for i = 0, 255 do
      bytes[i + 1] = i
    end
    return string.char(table.unpack(bytes))
  end)()},
  {label = "true", value = true},
  {label = "false", value = false},
  {label = "_ENV", value = _ENV},
}
do
  add_test{
    name = data.label.." upval",
    run = function()
      -- arrange
      local value = data.value
      local function func()
        return value
      end
      -- act
      local captured = capture(func)
      local loaded = assert(load(captured))
      local result = loaded()
      -- assert
      if data.value ~= data.value then
        assert_nan(result)
      else
        assert_equals(value, result)
      end
    end,
  }
end

add_test{
  name = "c function upval",
  run = function()
    -- arrange
    local concat = table.concat
    local function func()
      return concat
    end
    -- act
    local captured = capture(func)
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
    local function func()
      return gmatch_iter
    end
    -- act
    capture(func)
  end,
  expected_error = "Unable to capture unknown C function",
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
    local function func()
      return upval1(), upval2()
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result1, result2 = loaded()
    -- assert
    assert_equals(result1, result2)
  end,
}

add_test{
  -- test if 2 of the numbers are captured and restored correctly
  name = "number cache",
  run = function()
    -- arrange
    local value1 = 1.5
    local value2 = 1.5
    local function func()
      return value1, value2
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result1, result2 = loaded()
    -- assert
    assert_equals(1.5, result1)
    assert_equals(1.5, result2)
  end,
}

add_test{
  name = "ignore table in _ENV for C func lut",
  run = function()
    -- arrange
    local concat = table.concat
    local function func()
      return concat
    end
    func_capture.ignore_table_in_env(table)
    -- act
    capture(func)
  end,
  expected_error = "Unable to capture unknown C function",
}

add_test{
  name = "un-ignore table in _ENV for C func lut",
  run = function()
    -- arrange
    local concat = table.concat
    local function func()
      return concat
    end
    func_capture.ignore_table_in_env(table)
    func_capture.un_ignore_table_in_env(table)
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert_equals(table.concat, result)
  end,
}

add_test{
  name = "back reference",
  run = function()
    -- arrange
    local value = {}
    local lib = {value = value}
    local function func()
      return lib, value -- lib first
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local lib_result, value_result = loaded()
    -- assert
    assert(lib_result.value, "Missing back reference.")
    assert_equals(lib_result.value, value_result)
  end,
}

add_test{
  name = "cyclic back reference",
  run = function()
    -- arrange
    local value = {}
    local lib = {value = value}
    value.lib = lib
    local function func()
      return value
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert(result.lib, "Missing lib back reference.")
    assert(result.lib.value, "Missing lib.value back reference.")
    assert_equals(result, result.lib.value)
  end,
}

add_test{
  name = "back reference as key",
  run = function()
    -- arrange
    local value = {}
    local lib = {[value] = true}
    local function func()
      return lib, value -- lib first
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local lib_result, value_result = loaded()
    -- assert
    assert(next(lib_result), "Missing back reference.")
    assert_equals(next(lib_result), value_result)
  end,
}

for _, data in pairs{
  {
    label = "preserve iteration order with back ref",
    value = (function()
      local value = {one = 1}
      value.me = value
      value.foo = 3
      return value
    end)(),
  },
  {
    label = "preserve iteration order with back ref as key",
    value = (function()
      local value = {one = 1}
      value[value] = true
      value.foo = 3
      return value
    end)(),
  },
}
do
  add_test{
    name = data.label,
    run = function()
      -- arrange
      local value = data.value
      local function func()
        return value
      end
      -- act
      local captured = capture(func)
      local loaded = assert(load(captured))
      local result = loaded()
      -- assert
      assert_contents_equals(value, result)
    end,
  }
end

add_test{
  name = "upval in function upval",
  run = function()
    -- arrange
    local function upval()
      return 100
    end
    local function func()
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
  name = "preserve upval id",
  run = function()
    -- arrange
    local value = 1
    local function increment()
      value = value + 1
    end
    local function func()
      increment()
      return value
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert_equals(2, result)
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
    local restored1 = loaded()
    local restored2 = restored1()
    -- assert
    assert_equals(restored1, restored2)
  end,
}

add_test{
  name = "result func cache with 1 function",
  run = function()
    -- arrange
    local foo = {}
    local function func()
      return foo
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result1 = loaded()
    local result2 = loaded()
    -- assert
    assert_equals(result1, result2)
  end,
}

add_test{
  name = "result func cache with 2 functions",
  run = function()
    -- arrange
    local value = {}
    local function foo()
      return value
    end
    local function bar()
      return value
    end
    -- act
    local foo_captured = capture(foo)
    local bar_captured = capture(bar)
    local foo_loaded = assert(load(foo_captured))
    local bar_loaded = assert(load(bar_captured))
    local foo_result1 = foo_loaded()
    local foo_result2 = foo_loaded()
    local bar_result1 = bar_loaded()
    local bar_result2 = bar_loaded()
    -- assert
    assert_equals(foo_result1, foo_result2)
    assert_equals(bar_result1, bar_result2)
    assert_not_equals(foo_result1, bar_result1)
  end,
}

add_test{
  name = "table with metatable upval",
  run = function()
    -- arrange
    local value = setmetatable({}, {})
    local function func()
      return value
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert(getmetatable(result), "Missing metatable.")
  end,
}

add_test{
  name = "table with __pairs metamethod upval",
  run = function()
    -- arrange
    local value = setmetatable({}, {__pairs = function()
      assert(false, "__pairs got called")
    end})
    local function func()
      return value
    end
    -- act
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result = loaded()
    -- assert
    assert(getmetatable(result), "Missing metatable.")
  end,
}
