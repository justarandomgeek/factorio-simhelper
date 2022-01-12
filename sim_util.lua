
---cSpell:ignore upval, upvals, userdata, funcs, nups

---@class FunctionData
---@field raw_func function
---@field upvals Upvalue[]

---@class TableField
---@field key Value
---@field value Value

---@class Upvalue
---@field func FunctionData
---@field upval_index integer
---@field value Value

---@class Value
---only sed if this is used as an upvalue
---@field index integer|nil
---only sed if this is used as an upvalue\
---generated from the index: `"_"..index`
---@field id string|nil
---@field type '"nil"'|'"number"'|'"string"'|'"boolean"'|'"table"'|'"function"'
---for everything except functions, tables and _ENV
---@field value any
---for functions
---@field func FunctionData
---for tables; nil when `is_env`
---@field fields TableField[]|nil
---for tables
---@field is_env boolean
---only set if this value is used as an upvalue
---@field upval Upvalue|nil

local function get_c_func_lut()
  if __sim_c_func_lut then
    return __sim_c_func_lut
  end
  -- NOTE: tables and functions as keys are currently not supported,
  -- though with some work at least _some_ of them could be supported.
  -- specifically those where the keys also exist as values somewhere in _ENV
  -- which is honestly not even that likely if someone was using
  -- tables or functions as keys to begin with
  local supported_key_types = {
    ["string"] = true,
    ["number"] = true,
    ["boolean"] = true,
  }
  local c_func_lut = {}
  local visited = {}
  local key_stack = {}
  local function generate_expr()
    local result = {"_ENV"}
    for i, value in ipairs(key_stack) do
      result[i + 1] = "["..(type(value) == "string" and string.format("%q", value) or tostring(value)).."]"
    end
    return table.concat(result)
  end
  local function walk(value)
    if type(value) == "function" then
      local info = debug.getinfo(value, "S")
      if info.what == "C" then
        c_func_lut[value] = generate_expr()
      end
      return
    end
    if type(value) ~= "table" then
      return
    end
    if visited[value] then
      return
    end
    visited[value] = true
    for k, v in pairs(value) do
      if supported_key_types[type(k)] then
        key_stack[#key_stack+1] = k
        walk(v)
        key_stack[#key_stack] = nil
      end
    end
  end
  walk(_ENV)
  -- set it after walking to not walk through our own global
  __sim_c_func_lut = c_func_lut
  return c_func_lut
end

local function sim_func(main_func)
  ---@type table<userdata, Upvalue>
  local upvals = {}
  ---@type Value[]
  local values = {}
  local value_count = 0
  ---@type table<function|table, Value>
  local reference_value_lut = {}

  local add_upval

  local function add_basic(type, value, is_used_as_upval)
    local result = {
      type = type,
      value = value,
    }
    if is_used_as_upval then
      value_count = value_count + 1
      result.index = value_count
      values[value_count] = result
    end
    return result
  end

  local function add_value(value, is_used_as_upval)
    if reference_value_lut[value] then
      return reference_value_lut[value]
    end
    return ({
      ["nil"] = function()
        return add_basic("nil", value, is_used_as_upval)
      end,
      ["number"] = function()
        return add_basic("number", value, is_used_as_upval)
      end,
      ["string"] = function()
        return add_basic("string", value, is_used_as_upval)
      end,
      ["boolean"] = function()
        return add_basic("boolean", value, is_used_as_upval)
      end,
      ["table"] = function()
        if value == _ENV then
          value_count = value_count + 1
          local result = {
            index = value_count,
            type = "table",
            is_env = true,
          }
          values[value_count] = result
          reference_value_lut[value] = result
          return result
        end
        value_count = value_count + 1
        local result = {
          index = value_count,
          type = "table",
          fields = {},
        }
        values[value_count] = result
        reference_value_lut[value] = result
        local field_count = 0
        for k, v in pairs(value) do
          field_count = field_count + 1
          result.fields[field_count] = {
            key = add_value(k),
            value = add_value(v),
          }
        end
        return result
      end,
      ["function"] = function()
        local func = {
          raw_func = value,
          upvals = {},
        }
        value_count = value_count + 1
        local result = {
          index = value_count,
          type = "function",
          func = func,
        }
        values[value_count] = result
        reference_value_lut[value] = result
        local info = debug.getinfo(value, "u")
        for i = 1, info.nups do
          func.upvals[i] = add_upval(func, i)
        end
        return result
      end,
      ["thread"] = function()
        error("How did you even get a 'thread' object?")
      end,
      ["userdata"] = function()
        error("Cannot have a 'userdata' upvalue for a simulation function.")
      end,
    })[type(value)]()
  end

  function add_upval(func, upval_index)
    local id = debug.upvalueid(func.raw_func, upval_index)
    if upvals[id] then
      return upvals[id]
    end
    local name, value = debug.getupvalue(func.raw_func, upval_index)
    local upval = {
      func = func,
      -- upval_index = upval_index,
      value = add_value(value, true),
    }
    upval.value.upval = upval
    upvals[id] = upval
    return upval
  end

  local main_value = add_value(main_func)

  for _, value in pairs(values) do
    value.id = "_"..value.index
  end

  -- generate values into locals

  local function is_reference_type(value)
    return value.type == "table" or value.type == "function"
  end

  local result = {}
  local function generate_value(value, use_reference_ids)
    ({
      ["nil"] = function()
        result[#result+1] = "nil"
      end,
      ["number"] = function()
        result[#result+1] = tostring(value.value)
      end,
      ["string"] = function()
        result[#result+1] = string.format("%q", value.value)
      end,
      ["boolean"] = function()
        result[#result+1] = tostring(value.value)
      end,
      ["table"] = function()
        if use_reference_ids then
          result[#result+1] = value.id
          return
        end
        if value.is_env then
          result[#result+1] = "_ENV"
        else
          result[#result+1] = "{"
          for _, field in pairs(value.fields) do
            if not is_reference_type(field.key) then
              result[#result+1] = "["
              generate_value(field.key)
              result[#result+1] = "]="
              if is_reference_type(field.value) then
                result[#result+1] = "0," -- back reference
              else
                generate_value(field.value)
                result[#result+1] = ","
              end
            end
          end
          result[#result+1] = "}"
        end
      end,
      ["function"] = function()
        if use_reference_ids then
          result[#result+1] = value.id
          return
        end
        local data = debug.getinfo(value.func.raw_func, "S")
        if data.what == "C" then
          local lut = get_c_func_lut()
          local expr = lut[value.func.raw_func]
          if not expr then
            error("Unable to capture unknown c function. Did you remove it from \z
              _ENV or use and store the result of gmatch or ipairs or similar?"
            )
          end
          result[#result+1] = expr
        else
          result[#result+1] = string.format("assert(load(%q,nil,'b'))", string.dump(value.func.raw_func))
        end
      end,
    })[value.type]()
  end

  for _, value in pairs(values) do
    result[#result+1] = "\nlocal "..value.id.."="
    generate_value(value)
  end

  -- create dummy function for upvalue joining

  result[#result+1] = "\n\nlocal function dummy()"
  for _, value in pairs(values) do
    result[#result+1] = value.id
    result[#result+1] = "=nil;"
  end
  result[#result+1] = "end\n\n"

  -- resolve references

  for _, value in pairs(reference_value_lut) do
    if value.type == "table" then
      if not value.is_env then
        for _, field in pairs(value.fields) do
          if is_reference_type(field.key) or is_reference_type(field.value) then
            result[#result+1] = value.id.."["
            generate_value(field.key, true)
            result[#result+1] = "]="
            generate_value(field.value, true)
            result[#result+1] = "\n"
          end
        end
      end
    elseif value.type == "function" then
      for upval_index, upval in pairs(value.func.upvals) do
        result[#result+1] = "debug.upvaluejoin("..value.id..","..upval_index..",dummy,"..upval.value.index..")\n"
      end
    else
      error("A "..value.type.." value was in the reference_value_lut which is just wrong.")
    end
  end

  result[#result+1] = "\nreturn ("..main_value.id.."(...))"

  local result_string = table.concat(result)
  return result_string
end

return {
  sim_func = sim_func,
}
