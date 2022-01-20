
local runner = require("__simhelper__.scenario-scripts.tests.test_runner")
local tests = runner.tests
local assert = runner.assert
local assert_equals = runner.assert_equals
local assert_not_equals = runner.assert_not_equals

local func_capture = require("__simhelper__.funccapture")
local capture = func_capture.capture

tests["pure function"] = {
  run = function()
    local captured = capture(function()
      return 100
    end)
    local loaded = assert(load(captured))
    local result = loaded()
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
  tests["primitive "..(data.label or data.type).." upval"] = {
    run = function()
      local value = data.value
      local captured = capture(function()
        return value
      end)
      local loaded = assert(load(captured))
      local result = loaded()
      assert_equals(value, result)
    end,
  }
end

tests["special string upval"] = {
  run = function()
    local bytes = {}
    for i = 0, 255 do
      bytes[i + 1] = i
    end
    local value = string.char(table.unpack(bytes))
    local captured = capture(function()
      return value
    end)
    local loaded = assert(load(captured))
    local result = loaded()
    assert_equals(value, result)
  end,
}

tests["c function upval"] = {
  run = function()
    local concat = table.concat
    local captured = capture(function()
      return concat
    end)
    local loaded = assert(load(captured))
    local result = loaded()
    assert_equals(table.concat, result)
  end,
}

tests["invalid c function upval"] = {
  run = function()
    local gmatch_iter = string.gmatch("", "")
    capture(function()
      return gmatch_iter
    end)
  end,
  expected_error = "Unable to capture unknown C function",
}

tests["preserve iteration order with back refs"] = {
  run = function()
    local value = {1}
    value[value] = 2
    value.foo = 3
    local captured = capture(function()
      return value
    end)
    local loaded = assert(load(captured))
    local result = loaded()
    assert_not_equals(value, result)
    -- TODO: write custom table comparison, [...]
    -- serpent actually doesn't preserve iteration order in this case, so it's not a good test
    local options = {name = "_"}
    assert_equals(serpent.line(value, options), serpent.line(result, options))
  end,
}

tests["upval in function upval"] = {
  run = function()
    local function upval()
      return 100
    end
    local captured = capture(function()
      return upval()
    end)
    local loaded = assert(load(captured))
    local result = loaded()
    assert_equals(100, result)
  end,
}

tests["upval in function upval loop"] = {
  run = function()
    local func
    local function upval()
      local _ = func
      return 100
    end
    function func()
      return upval()
    end
    local captured = capture(func)
    local loaded = assert(load(captured))
    local result = loaded()
    assert_equals(100, result)
  end,
}

tests["upval deduplication"] = {
  run = function()
    local value = {}
    local function upval1()
      return value
    end
    local function upval2()
      return upval1()
    end
    local captured = capture(function()
      return upval1(), upval2()
    end)
    local loaded = assert(load(captured))
    local result1, result2 = loaded()
    assert_equals(result1, result2)
  end,
}

tests["upval of itself"] = {
  run = function()
    local func
    local function upval()
      return func
    end
    function func()
      return upval()
    end
    local captured = capture(func)
    local loaded = assert(load(captured))
    local restored = loaded()
    assert_equals(restored, restored())
  end,
}
