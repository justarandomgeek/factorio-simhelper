
---cSpell:ignore upvalue, upval, upvals, userdata, funcs, nups, funccapture

---@class TableField
---@field key Value
---@field value Value

---@class Upvalue
---@field value Value
---@field upval_index integer|nil
---the expression to get this upvalue
---@field upval_id string

---@class Value
---@field type '"nil"'|'"number"'|'"string"'|'"boolean"'|'"table"'|'"function"'|'"custom"'
---for everything except functions, tables and _ENV
---@field value any
---for functions
---@field func function
---for functions
---@field upvals Upvalue[]
---for tables; nil when `is_env`
---@field fields TableField[]|nil
---for tables
---@field is_env boolean
---for tables and functions
---@field ref_index integer|nil
---the expression to get this table or function
---@field ref_id string
---index to resume at for an unfinished table due to not yet generated reference values as keys
---@field resume_at integer|nil
---for custom
---@field custom_expr string

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

local function generate_expr(keys)
  local result = {"_ENV"}
  for i, value in ipairs(keys) do
    local value_type = type(value)
    if not supported_key_types[value_type] then
      error("Expressions indexing into '_ENV' (global) can only use strings, numbers and booleans as keys.")
    end
    result[i + 1] = "["..(value_type == "string" and string.format("%q", value) or tostring(value)).."]"
  end
  return table.concat(result)
end

local function get_c_func_lut()
  if __funccapture_c_function_lut then
    return __funccapture_c_function_lut
  end
  local c_func_lut = {}
  local visited = {}
  local key_stack = {}
  local function walk(value)
    if type(value) == "function" then
      local info = debug.getinfo(value, "S")
      if info.what == "C" then
        c_func_lut[value] = generate_expr(key_stack)
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
  __funccapture_c_function_lut = c_func_lut
  return c_func_lut
end

local function sim_func(main_func, custom_restorers)
  local custom_restore_lut = {}
  for _, custom_restorer in pairs(custom_restorers) do
    local name = custom_restorer.upvalue_name
    if custom_restore_lut[name] then
      error("Duplicate custom restorer registered for upvalue_name '"..name.."'")
    end
    custom_restore_lut[name] = {
      type = "custom",
      custom_expr = generate_expr(custom_restorer.restore_as_global),
    }
  end

  ---@type table<userdata, Upvalue>
  local upvals = {}
  local upval_count = 0
  ---@type table<function|table, Value>
  local ref_values = {}

  local add_upval

  local function add_basic(type, value)
    return {
      type = type,
      value = value,
    }
  end

  local function add_value(value)
    if ref_values[value] then
      return ref_values[value]
    end
    return ({
      ["nil"] = function()
        return add_basic("nil", value)
      end,
      ["number"] = function()
        return add_basic("number", value)
      end,
      ["string"] = function()
        return add_basic("string", value)
      end,
      ["boolean"] = function()
        return add_basic("boolean", value)
      end,
      ["table"] = function()
        if value == _ENV then
          local result = {
            type = "table",
            is_env = true,
          }
          ref_values[value] = result
          return result
        end
        local result = {
          type = "table",
          fields = {},
        }
        ref_values[value] = result
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
        local result = {
          type = "function",
          func = value,
          upvals = {},
        }
        ref_values[value] = result
        local info = debug.getinfo(value, "u")
        for i = 1, info.nups do
          result.upvals[i] = add_upval(value, i)
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
    local id = debug.upvalueid(func, upval_index)
    if upvals[id] then
      return upvals[id]
    end
    local name, raw_value = debug.getupvalue(func, upval_index)
    local value = custom_restore_lut[name] or add_value(raw_value)
    upval_count = upval_count + 1
    local upval = {
      value = value,
      upval_index = upval_count,
      upval_id = "upvals["..upval_count.."]",
    }
    upvals[id] = upval
    return upval
  end

  local main_value = add_value(main_func)

  -- util functions for generating

  local function is_reference_type(value)
    return value.type == "table" or value.type == "function"
  end

  local unfinished_tables = {}
  local back_reference_tables = {}
  local back_reference_fields = {}

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
          result[#result+1] = value.ref_id
          return
        end
        if value.is_env then
          result[#result+1] = "_ENV"
        else
          if not value.ref_id then
            result[#result+1] = "{"
          end
          for i, field in next, value.fields, value.resume_at and value.resume_at ~= 1 and (value.resume_at - 1) or nil do
            if is_reference_type(field.key) and not field.key.ref_id then
              value.resume_at = i
              unfinished_tables[#unfinished_tables+1] = value
              break
            end
            if value.ref_id then
              result[#result+1] = "\n"..value.ref_id
            end
            result[#result+1] = "["
            generate_value(field.key, true)
            result[#result+1] = "]="
            if is_reference_type(field.value) and not field.value.ref_id then
              assert(not value.ref_id,
                "When finishing the generation of a table, all other references should be generated already"
              )
              result[#result+1] = "0," -- back reference
              back_reference_tables[#back_reference_tables+1] = value
              back_reference_fields[#back_reference_fields+1] = field
            else
              generate_value(field.value, true)
              if not value.ref_id then
                result[#result+1] = ","
              end
            end
          end
          if not value.ref_id then
            result[#result+1] = "}"
          end
        end
      end,
      ["function"] = function()
        if use_reference_ids then
          result[#result+1] = value.ref_id
          return
        end
        local data = debug.getinfo(value.func, "S")
        if data.what == "C" then
          local lut = get_c_func_lut()
          local expr = lut[value.func]
          if not expr then
            error("Unable to capture unknown c function. Did you remove it from \z
              _ENV or use and store the result of gmatch or ipairs or similar?"
            )
          end
          result[#result+1] = expr
        else
          result[#result+1] = string.format("assert(load(%q,nil,'b'))", string.dump(value.func))
        end
      end,
      ["custom"] = function()
        result[#result+1] = value.custom_expr
      end,
    })[value.type]()
  end

  -- generate reference values

  result[#result+1] = "local ref_values={}"
  do
    local i = 0
    for _, value in pairs(ref_values) do
      i = i + 1
      value.ref_index = i
      local ref_id = "ref_values["..i.."]"
      result[#result+1] = "\n"..ref_id.."="
      generate_value(value)
      value.ref_id = ref_id
    end
  end

  -- finish unfinished tables

  result[#result+1] = "\n"
  for _, value in pairs(unfinished_tables) do
    generate_value(value)
  end

  -- finish back references

  result[#result+1] = "\n\n"
  for i = 1, #back_reference_tables do
    local tab = back_reference_tables[i]
    local field = back_reference_fields[i]
    result[#result+1] = tab.ref_id.."["
    generate_value(field.key, true)
    result[#result+1] = "]="
    generate_value(field.value, true)
    result[#result+1] = "\n"
  end

  -- generate dummy functions for upvalue joining

  result[#result+1] = "\nlocal upvals={}"
  for _, upval in pairs(upvals) do
    result[#result+1] = "\ndo local value="
    generate_value(upval.value, true)
    result[#result+1] = " "..upval.upval_id.."=function()return value end end"
  end
  result[#result+1] = "\n\nlocal upvaluejoin=debug.upvaluejoin\n\n"

  -- restore upvals

  for _, value in pairs(ref_values) do
    if value.type == "function" then
      for upval_index, upval in pairs(value.upvals) do
        result[#result+1] = "upvaluejoin("..value.ref_id..","..upval_index..","..upval.upval_id..",1)\n"
      end
    end
  end

  result[#result+1] = "\nreturn "..main_value.ref_id.."(...)"

  local result_string = table.concat(result)
  return result_string
end

return {
  sim_func = sim_func,
}
