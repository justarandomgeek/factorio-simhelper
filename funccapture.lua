log("WARNING: funccapture is no longer supported.")

return {
  capture = function() 
    return [[
      error("funccapture is no longer supported")
    ]]
  end,
  ignore_table_in_env = function() end,
  un_ignore_table_in_env = function() end,
}
