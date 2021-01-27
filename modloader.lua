-- mod must either not use event filters, or be prepared to receive unfiltered events
-- mod should use all `__modname__` qualified requires to ensure correct resolution
-- mod must handle having an empty `global` in on_load or have it transplanted to `level.__modloader[modname]`


local modloader = {
  env = { _ENV=_ENV }
}

function modloader.load(modname)
  local modevents = {
    events = {},
    on_nth_tick = {},
  }
  local env = _ENV

  -- on_event needs to be redirected to the events table, print warning when ignoring filters
  local function on_event(event,f,filters)
    local etype = type(event)
    if etype == "number" then
      if filters then
        log("ignored filters") --TODO: print something more useful
      end
      modevents.events[event] = f
    elseif etype == "string" then
      modevents.events[event] = f
    elseif etype == "table" then
      for _,e in pairs(event) do
        on_event(e,f)
      end
    else
      error({"","Invalid Event type ",etype},2)
    end
  end
  local modpackages = {}
  local sandbox = setmetatable({
    script = setmetatable({
      -- on_init/on_load need redirect, mod needs to handle possibly being added by on_load the first time if added in an update!
      on_init = function(f)
        modevents.on_init = f
      end,
      on_load = function(f)
        modevents.on_load = f
      end,
      on_event = on_event,
      -- on_nth_tick needs to be redirected to events table
      on_nth_tick = function(n,f)
        modevents.on_nth_tick[n] = f
      end,
      on_configuration_changed = function(f)
        modevents.on_configuration_changed = f
      end,
      get_event_handler = function (event)
        return modevents.events[event]
      end,
    },{
      __debugline = "<modloader script proxy for "..modname..">",
      __debugtype = "modloader.LuaBootstrap",
      __index = script,
    }),
    require = function(path)
      local realpackage = package.loaded
      package.loaded = modpackages
      local result = require(path)
      package.loaded = realpackage
      return result
    end,
    package = setmetatable({loaded = modpackages},{__index = package})
  },{
    __debugline = "<modloader _ENV for "..modname..">",
    __index = function(t,k)
      if k == "global" then
        local global = env.global
        local mods = global.__modloader
        if not mods then
          mods = {}
          global.__modloader = mods
        end
        local mod = mods[modname]
        if not mod then
          mod = {}
          mods[modname] = mod
        end
        return mod
      else
        return env[k]
      end
    end,
    __newindex = function(t,k,v)
      if k == "global" then
        local global = env.global
        local mods = global.__modloader
        if not mods then
          mods = {}
          global.__modloader = mods
        end
        mods[modname] = v
      else
        rawset(t,k,v)
      end
    end,
  })
  modloader.env[modname] = sandbox
  
  -- check for an existing hook:
  local oldhook,oldmask,oldcount = debug.gethook()
  -- this hook is only a call hook, which means losing a few line events,
  -- but only between here and the start of the main chunk of the required file
  -- there are no return hooks in that time, and the two call hooks are
  -- passed on to the original hook handler via tailcall
  debug.sethook(function(event)
    local info = debug.getinfo(2,"fu")
    -- skip the call to require itself...
    if info.func == require then
      if oldhook and oldmask and oldmask:match("c") then
        -- tailcall the original hook to preserve call event
        return oldhook(event)
      end
      return
    end
    -- on the main chunk, replace it's _ENV upval with sandbox
    local f = info.func
    for i = 1,info.nups do -- this *should* always be upval 1 but just to be sure...
      local name = debug.getupvalue(f,i)
      if name == "_ENV" then
        -- replace its _ENV with the sandbox
        debug.upvaluejoin(f,i,function() return sandbox end,1)
        break
      end
    end

    -- then restore previous hook and pass along the event
    debug.sethook(oldhook,oldmask,oldcount)
    if oldhook and oldmask and oldmask:match("c") then
      -- and tailcall the original hook to preserve call event
      return oldhook(event)
    end
  end,"c")
  require("__"..modname.."__/control.lua")
  return modevents
end

return modloader