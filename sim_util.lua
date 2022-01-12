
-- -- local foo = "fo"
-- local bar
-- (function()
--   local _,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_
--   local foo = "fo"
--   function bar()
--     if false then
--       print()
--     end
--     return foo
--   end
-- end)()
-- -- local function bar()
-- --   print()
-- --   return foo
-- -- end

-- local bar_dumped = string.dump(bar)

-- local disassembler = require("__phobos__.disassembler")

-- local bar_disassembled = disassembler.disassemble(bar_dumped)

-- local bar_loaded = load(bar_dumped, nil, 'b', _ENV)

-- local bar_disassembled_again = disassembler.disassemble(string.dump(bar_loaded))

-- local dummy_upvalue = "fo"
-- local function dummy()
--   dummy_upvalue = nil
-- end

-- debug.upvaluejoin(bar_loaded, 2, dummy, 1)

-- local bar_disassembled_again_again = disassembler.disassemble(string.dump(bar_loaded))

-- print(bar_loaded())

local function sim_func(func)
  local values = {}
  local is_func = {}
  local funcs = {}
  local function add_value(val)
    if values[val] then
      return
    end
    ({
      ["nil"] = function()
        -- I think this is fine doing nothing
      end,
      ["number"] = function()
        values[val] = tostring(val)
      end,
      ["string"] = function()
        values[val] = string.format("%q", val)
      end,
      ["boolean"] = function()
        values[val] = tostring(val)
      end,
      ["table"] = function()
        if val == _ENV then
          values[val] = val
          return
        end
        -- TODO: handle functions inside tables
        -- TODO: and maybe tables inside tables that occur multiple times... if that makes sense
        values[val] = "(function()"..serpent.dump(val).." end)()"
      end,
      ["function"] = function()
        local info = debug.getinfo(val, "u")
        local func_data = {
          create_value_str = string.format("assert(load(%q,nil,'b'))", string.dump(val)),
          func = val,
          upval_values = {},
          upval_count = info.nups,
        }
        values[val] = func_data
        is_func[val] = true
        funcs[#funcs+1] = func_data
        for i = 1, func_data.upval_count do
          local name, value = debug.getupvalue(val, i)
          func_data.upval_values[i] = value
          add_value(value)
        end
      end,
      ["thread"] = function()
        error("How did you even get a 'thread' object?")
      end,
      ["userdata"] = function()
        error("Cannot have a 'userdata' upvalue for a simulation function.")
      end,
    })[type(val)]()
  end

  add_value(func)

  local result = {"\n"}
  local value_indexes = {}
  local value_count
  do
    local i = 1
    for value, string_value in pairs(values) do
      value_indexes[value] = i
      result[#result+1] = "local _"..i.."="
      result[#result+1] = value == _ENV and "_ENV" or (is_func[value] and string_value.create_value_str or string_value)
      result[#result+1] = "\n\n"
      i = i + 1
    end
    value_count = i - 1
  end

  result[#result+1] = "\nlocal function dummy()"
  for i = 1, value_count do
    result[#result+1] = "_"
    result[#result+1] = tonumber(i)
    result[#result+1] = "=nil;"
  end
  result[#result+1] = "end\n\n"

  for _, func_data in ipairs(funcs) do
    local func_local = "_"..value_indexes[func_data.func]
    for i = 1, func_data.upval_count do
      local value = func_data.upval_values[i]
      result[#result+1] = "debug.upvaluejoin("..func_local..","..i..",dummy,"..value_indexes[value]..")\n"
    end
  end

  result[#result+1] = "\nreturn _1(...)"

  local result_string = table.concat(result)
  -- log(result_string)
  return result_string
  -- return string.format("local main_chunk=assert(load(%q,nil,'b'))\nreturn main_chunk(...)", string.dump(func))
end

return {
  sim_func = sim_func,
}
