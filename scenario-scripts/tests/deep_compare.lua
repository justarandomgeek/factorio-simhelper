
---cSpell:ignore userdata, upval, upvals, nups, bytecode, metatable

-- deep compare compares the contents of 2 values

-- tables are compared by identity,
-- if not equal then by their contents including iteration order

-- functions are compared by identity,
-- if not equal then by bytecode and all their upvals

local deep_compare
local difference_type = {
  value_type = 1,
  function_bytecode = 2,
  primitive_value = 3,
  size = 4,
}
do
  local visited
  local location_stack
  local location_stack_size
  local compare_tables
  local difference

  local function create_location()
    return table.concat(location_stack, nil, 1, location_stack_size)
  end

  local function create_difference(diff_type, left, right)
    difference = {
      type = diff_type,
      location = create_location(),
      left = left,
      right = right,
    }
  end

  local function compare_values(left, right)
    -- compare nil, boolean, string, number (including NAN)
    if left == right or (left ~= left and right ~= right) then
      return true
    end
    if visited[left] then
      return true
    end
    visited[left] = true
    local left_type = type(left)
    local right_type = type(right)
    if left_type ~= right_type then
      create_difference(difference_type.value_type, left, right)
      return false
    end
    if left_type == "thread" then
      error("How did you even get a thread?")
    elseif left_type == "userdata" then
      -- TODO: check if that's even true, but it doesn't really matter right now
      error("Cannot compare userdata")
    elseif left_type == "function" then
      if string.dump(left) ~= string.dump(right) then
        create_difference(difference_type.function_bytecode, left, right)
        return false
      end
      -- compare upvals
      location_stack_size = location_stack_size + 1
      for i = 1, debug.getinfo(left, "u").nups do
        local name, left_value = debug.getupvalue(left, i)
        local _, right_value = debug.getupvalue(right, i)
        location_stack[location_stack_size] = "[upval #"..i.." ("..name..")]"
        if not compare_values(left_value, right_value) then
          return false
        end
      end
      location_stack_size = location_stack_size - 1
      return true
    elseif left_type == "table" then
      return compare_tables(left, right)
    end
    create_difference(difference_type.primitive_value, left, right)
    return false
  end

  function compare_tables(left, right)
    local left_key, left_value = next(left)
    local right_key, right_value = next(right)
    location_stack_size = location_stack_size + 1
    local kvp_num = 0
    while left_key ~= nil do
      kvp_num = kvp_num + 1

      location_stack[location_stack_size] = "[key #"..kvp_num.."]"
      if right_key == nil then
        -- TODO: add more info about table sizes
        create_difference(difference_type.size, left, right)
        return false
      end
      if not compare_values(left_key, right_key) then
        return false
      end

      -- TODO: improve key representation
      location_stack[location_stack_size] = "["..tostring(left_key).." (value #"..kvp_num..")]"
      if not compare_values(left_value, right_value) then
        return false
      end

      left_key, left_value = next(left, left_key)
      right_key, right_value = next(right, right_key)
    end
    location_stack_size = location_stack_size - 1
    if right_key ~= nil then
      -- TODO: add more info about table sizes
      create_difference(difference_type.size, left, right)
      return false
    end

    local left_meta = debug.getmetatable(left)
    local right_meta = debug.getmetatable(right)
    if left_meta ~= nil or right_meta ~= nil then
      assert(type(left_meta) == "table", "Unexpected metatable type '"..type(left_meta).."'")
      assert(type(right_meta) == "table", "Unexpected metatable type '"..type(right_meta).."'")
      location_stack_size = location_stack_size + 1
      location_stack[location_stack_size] = "[metatable]"
      local result = compare_values(left_meta, right_meta)
      location_stack_size = location_stack_size - 1
      return result
    end

    return true
  end

  function deep_compare(left, right)
    visited = {}
    location_stack = {"ROOT"}
    location_stack_size = 1
    local result = compare_values(left, right)
    location_stack = nil
    visited = nil
    local difference_result = difference
    difference = nil
    return result, difference_result
  end
end

return {
  deep_compare = deep_compare,
  difference_type = difference_type,
}
