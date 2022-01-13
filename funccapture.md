
The function capture helper allows you to capture a regular Lua function and use it for the `init` and `update` functions for simulations. It also captures upvalues used by this function allowing you to use functions and values from outside the `init` and `update` functions. In other words, you can use libraries and reuse your functions for multiple simulations.

```lua
local func_capture = require("__simhelper__.funccapture")

-- ...

  {
    type = "tips-and-tricks-item",
    name = "nixie-tubes",
    tag = "[entity=nixie-tube]",
    category = "nixie-tubes",
    is_title = true,
    order = "zz-00",
    dependencies = {"circuit-network"},
    simulation = {
      save = "__nixie-tubes__/simulations/nixiesim.zip",
      init = func_capture.capture(function()
        local bp="0eNq1lVtugzAQRfcy36aKzZu/dBtVhIA47UhgkDFRoogFdCHdWFdSG9QEKYRH1fwgbMbncsejmQukecMriUJBdAHMSlFD9HaBGt9Fkps9da44RICKF0BAJIVZCTwht1STcmgJoNjzE0S03RHgQqFC3lO6xTkWTZFyqQPGzhOoylofKYVR0xjLeXEJnPULa1tyB2HLIO4kxF4GYZMQZxnEnoS4yyCbG4SAviUlyzxO+UdyxFKaoAxl1qCK9bf99eQBZa3iu7s8olSN3rlK9xHWFnp4rRJTDxajju8EtucEZruoEpkoowbfn1/Q9rGCZ0atNnhqHpLvh3ePekXtdteOmfeWmaeTGfRHIFZdJHk+VVs6oWOwYA3MnoGFa2BsBkY3a2h0jkbX0DZD2vPq7/VZ9cce1B+9NZNfWUsLpSg6obtEsPk8HDBXXD5oojPGG+OaMttxPT8Ih311hVf6yKv9R6/0f71u77z+zajb+dQTp5tM0WCQETjqv+qcsECXUMh8FgaB5+v28QOiY0wL"
        game.tick_paused = false
        game.camera_alt_info = true
        local result = {game.surfaces[1].create_entities_from_blueprint_string
        {
          string = bp,
          position = {0, 0},
        }}
        remote.call("nixie-tubes", "RebuildNixies")
      end),
      update = func_capture.capture(function()

      end),
    }
  },
```

## Quriks and Pitfalls

### Captured current State

When capturing, it captures the current state of every upvalue and every upvalue of upvalues, and so on. This means that any changes to the values that it captured after they got captured will not have effect on the captured function.

### Custom Lua Globals

It doesn't capture the global environment `_ENV` (so global variables). When the captured function is loaded and run in the simulation it will be in a new Lua state with a fresh `_ENV`. That means it is recommended to not use _non default globals_, but instead put them into a local and capture those as upvalues, that way they will be captured.

However if any of the captured functions use globals where you cannot change them to "not use custom globals" you will have to restore the global yourself.

For example here we have to manually restore the global `util` because `some_library_function` is using it as a global.
```lua
-- some_lib.lua
require("util")

local function some_library_function(arg)
  -- using 'util' as a global
  return util.copy(arg)
end

return {
  some_library_function = some_library_function,
}
```
```lua
-- somewhere in data stage where you define your simulations
local func_capture = require("__simhelper__.funccapture")
local some_lib = require("some_lib")
local util = require("util") -- put 'util' into a local

-- ...

{ -- in your simulation definition
  init = func_capture.capture(function()
    -- have to restore the global 'util' using the 
    -- captured local 'util' as an upvalue in order 
    -- for the library function to have access to 'util'
    util = util

    local my_data = {}
    local data_copy = some_lib.some_library_function(my_data)
  end),
}
```

But again, if nothing that gets captured is using non default globals you simply don't have to worry about this.

### Custom Captures and Restorers

In some weird cases it can happen that it captures an upvalue that was meant to be a global. For example:
```lua
local settings = settings
-- ...
{
  init = func_capture.capture(function()
    local my_setting_value = settings.global["my_setting"].value
    -- use my_setting_value
  end),
}
```
This ends up capturing the data stage `settings` table as an upvalue, and restores it in control stage, which means it would only have `startup` settings.

In this case there are 3 ways to solve this issue:
1. Just don't do that. Don't put something you don't want to capture in a local and then capture it as an upvalue.
2. Similar to 1, use `_ENV.settings` instead
3. If that's not possible, you can define custom restorers like this:
```lua
local settings = settings
-- ...
{
  init = func_capture.capture(function()
    local my_setting_value = settings.global["my_setting"].value
    -- use my_setting_value
  end, { -- a list of restorers
    {
      upvalue_name = "settings",
      restore_as_global = {"settings"},
    }
  }),
}
```

Any upvalue with the name `settings` will then be restored as defined by `restore_as_global` instead, and doesn't get captured.

`restore_as_global` takes an array of keys (strings, numbers or booleans) to index into `_ENV` with. Examples:
- `{"settings"}`: will restore as `_ENV["settings"]`
- `{"foo", "bar"}`: will resoter as `_ENV["foo"]["bar"]`
