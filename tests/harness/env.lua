-- tests/harness/env.lua
-- Builds a fresh sandbox _G for one harness run: Lua 5.1 stdlib, WoW's Lua extras
-- (strsplit, wipe, tinsert, bit, debugstack, ...), secret-aware type/tostring/
-- tonumber/format, error handling the WoW way, and C_Timer on the fake clock.

local Secret = require("secret")

local Env = {}

local function copy(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

local function strtrim(s, chars)
  if Secret.is(s) then Secret.fail("attempt to trim", 3) end
  chars = chars or " \t\r\n"
  local p = "[" .. chars:gsub("[%]%%%-%^]", "%%%0") .. "]"
  return (s:gsub("^" .. p .. "+", ""):gsub(p .. "+$", ""))
end

local function strsplit(sep, str, limit)
  if Secret.is(str) or Secret.is(sep) then Secret.fail("attempt to split", 3) end
  local out, n, pos = {}, 0, 1
  local sepPattern = "[" .. sep:gsub("[%]%%%-%^]", "%%%0") .. "]"
  while true do
    if limit and n == limit - 1 then out[#out + 1] = str:sub(pos); break end
    local s, e = str:find(sepPattern, pos)
    if not s then out[#out + 1] = str:sub(pos); break end
    out[#out + 1] = str:sub(pos, s - 1)
    n = n + 1
    pos = e + 1
  end
  return unpack(out)
end

local function wipe(t)
  for k in pairs(t) do t[k] = nil end
  return t
end

function Env.new(h)
  local env = {}
  env._G = env

  for _, k in ipairs({ "assert", "error", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget",
    "rawset", "select", "setmetatable", "getmetatable", "unpack", "xpcall", "collectgarbage", "gcinfo",
    "loadstring", "newproxy" }) do
    env[k] = _G[k]
  end
  env.type, env.tostring, env.tonumber = Secret.type, Secret.tostring, Secret.tonumber
  env.loadstring = function(src, chunkName)
    local fn, err = loadstring(src, chunkName)
    if fn then setfenv(fn, env) end
    return fn, err
  end
  env.setfenv, env.getfenv = setfenv, getfenv

  -- string: shared metatable means method calls hit the real string table; format is
  -- patched globally by secret.lua, the rest are the plain Lua functions.
  local str = copy(string)
  str.format = Secret.format
  str.join = Secret.join
  str.split = strsplit
  str.trim = strtrim
  env.string = str

  local tbl = copy(table)
  tbl.wipe = wipe
  tbl.concat = Secret.tableConcat
  tbl.count = function(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
  tbl.isempty = function(t) return next(t) == nil end
  tbl.removemulti = function(t, pos, count)
    for _ = 1, count or 1 do table.remove(t, pos) end
  end
  env.table = tbl
  env.math = copy(math)
  env.bit = require("bit")
  env.coroutine = copy(coroutine)
  env.os = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime }
  env.time, env.date, env.difftime = os.time, os.date, os.difftime

  -- WoW global aliases
  env.strsplit, env.strjoin, env.strtrim, env.strconcat = strsplit, Secret.join, strtrim, Secret.concat
  env.strsplittable = function(sep, s, limit) return { strsplit(sep, s, limit) } end
  env.format = Secret.format
  env.gsub, env.strmatch, env.strfind, env.strsub = string.gsub, string.match, string.find, string.sub
  env.strlen, env.strlower, env.strupper, env.strrep = string.len, string.lower, string.upper, string.rep
  env.strbyte, env.strchar, env.strrev, env.gmatch = string.byte, string.char, string.reverse, string.gmatch
  env.strlenutf8 = function(s) local _, n = s:gsub("[^\128-\191]", ""); return n end
  env.strcmputf8i = function(a, b) a, b = a:lower(), b:lower(); return a < b and -1 or (a > b and 1 or 0) end
  env.tostringall = function(...)
    local n, t = select("#", ...), { ... }
    for i = 1, n do t[i] = Secret.tostring(t[i]) end
    return unpack(t, 1, n)
  end
  env.tinsert, env.tremove, env.sort, env.wipe = table.insert, table.remove, table.sort, wipe
  env.getn = function(t) return #t end
  env.foreach = function(t, f) for k, v in pairs(t) do local r = f(k, v); if r ~= nil then return r end end end
  env.foreachi = function(t, f) for i, v in ipairs(t) do local r = f(i, v); if r ~= nil then return r end end end
  for _, k in ipairs({ "abs", "ceil", "floor", "max", "min", "sqrt", "exp", "log", "log10", "fmod",
    "frexp", "ldexp", "deg", "rad", "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "random" }) do
    env[k] = math[k]
  end
  env.mod = math.fmod
  env.fastrandom = math.random
  env.PI = math.pi

  -- printing goes to the harness log (and stdout when verbose)
  env.print = function(...)
    local n, parts = select("#", ...), {}
    for i = 1, n do parts[i] = tostring(Secret.raw((select(i, ...)))) end
    local line = table.concat(parts, " ")
    h.printed[#h.printed + 1] = line
    if h.verbose then io.write("[print] ", line, "\n") end
  end

  -- error handling: every error is recorded by the harness first, then handed to the
  -- current handler chain, like WoW's script error path.
  -- The default handler records too, so errors an addon catches itself and
  -- forwards to geterrorhandler() (as Perl Infinity's ns.Call does) still fail tests.
  local defaultHandler = function(msg)
    h:reportError(tostring(Secret.raw(msg)), "geterrorhandler", debug.traceback("", 2))
    return msg
  end
  local currentHandler = defaultHandler
  env.geterrorhandler = function() return currentHandler end
  env.seterrorhandler = function(fn)
    h:warn("seterrorhandler called (Perl Infinity must never replace the error handler)")
    currentHandler = fn
  end
  h.dispatchError = function(_, msg, where, stack)
    local handler = currentHandler
    if handler == defaultHandler then
      h:reportError(msg, where, stack)
    else
      h:reportError(msg, where, stack)
      local ok, err = pcall(handler, msg)
      if not ok then h:reportError("error in error handler: " .. tostring(err), "errorhandler") end
    end
  end

  local function tb(msg) return { msg = msg, stack = debug.traceback("", 2) } end
  -- securecall(fn, ...): errors go to the handler and the call returns nothing.
  local function secureCall(fn, ...)
    if type(fn) == "string" then fn = env[fn] end
    local res = { xpcall(fn, tb, ...) }
    if not res[1] then
      local e = res[2]
      h:dispatchError(type(e) == "table" and e.msg or e, "securecall", type(e) == "table" and e.stack or nil)
      return
    end
    return unpack(res, 2, table.maxn(res))
  end
  env.securecall = secureCall
  env.securecallfunction = secureCall
  env.secureexecuterange = function(t, fn, ...)
    for k, v in pairs(t) do secureCall(fn, k, v, ...) end
  end
  env.issecure = function() return false end
  env.issecurevariable = function() return false, h.addonName end
  env.forceinsecure = function() end
  env.hooksecurefunc = function(a, b, c)
    local t, name, hook = a, b, c
    if type(a) == "string" then t, name, hook = env, a, b end
    local orig = t[name]
    if type(orig) ~= "function" then error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 2) end
    t[name] = function(...)
      local r = { orig(...) }
      secureCall(hook, ...)
      return unpack(r, 1, table.maxn(r))
    end
  end

  env.debugstack = function(start, count1, count2)
    local s = debug.traceback("", (start or 1) + 1)
    return (s:gsub("^stack traceback:\n", ""))
  end
  env.debuglocals = function() return "" end
  local profileStart = os.clock()
  env.debugprofilestart = function() profileStart = os.clock() end
  env.debugprofilestop = function() return (os.clock() - profileStart) * 1000 end
  env.GetTime = function() return h.clock end
  env.GetTimePreciseSec = function() return h.clock end
  env.GetServerTime = function() return 1760400000 + math.floor(h.clock) end

  -- C_Timer on the fake clock
  local C_Timer = {}
  local function schedule(delay, fn, iterations, handle)
    if type(fn) ~= "function" then error("C_Timer: callback must be a function", 3) end
    local t = handle or {}
    t._fn, t._delay, t._left, t._at = fn, delay, iterations, h.clock + math.max(delay or 0, 0)
    -- Timers made while timers run wait for the next frame, as in the game.
    t._pass = h.timerPass or 0
    h.timers[#h.timers + 1] = t
    return t
  end
  local TimerMT = { __index = {
    Cancel = function(self) self._cancelled = true end,
    IsCancelled = function(self) return self._cancelled == true end,
  } }
  C_Timer.After = function(delay, fn) schedule(delay, fn, 1) end
  C_Timer.NewTimer = function(delay, fn) return schedule(delay, fn, 1, setmetatable({ _kind = "Timer" }, TimerMT)) end
  C_Timer.NewTicker = function(delay, fn, iterations)
    return schedule(delay, fn, iterations or math.huge, setmetatable({ _kind = "Ticker" }, TimerMT))
  end
  env.C_Timer = C_Timer

  env.GetBuildInfo = function() return "1.60.1", "70338", "Oct 14 2026", 16001, "1.60.1", "Release" end
  env.GetLocale = function() return "enUS" end
  env.IsMacClient = function() return true end
  env.IsWindowsClient = function() return false end
  env.IsLinuxClient = function() return false end

  -- Mixins (FrameXML/Mixin.lua)
  env.Mixin = function(object, ...)
    for i = 1, select("#", ...) do
      local mixin = select(i, ...)
      for k, v in pairs(mixin) do object[k] = v end
    end
    return object
  end
  env.CreateFromMixins = function(...) return env.Mixin({}, ...) end
  env.CreateAndInitFromMixin = function(mixin, ...)
    local o = env.CreateFromMixins(mixin)
    o:Init(...)
    return o
  end

  Secret.installHelpers(env)
  return env
end

-- Runs due timers; returns how many callbacks ran.
function Env.runTimers(h)
  local ran = 0
  local i = 1
  h.timerPass = (h.timerPass or 0) + 1
  local pass = h.timerPass
  while i <= #h.timers do
    local t = h.timers[i]
    if t._cancelled or t._left <= 0 then
      table.remove(h.timers, i)
    elseif t._pass ~= pass and t._at <= h.clock + 1e-9 then
      t._left = t._left - 1
      t._at = t._at + math.max(t._delay or 0, 0.0001)
      ran = ran + 1
      h:protectedCall(t._fn, "C_Timer", t._kind and t or nil)
      if t._left <= 0 or t._cancelled then table.remove(h.timers, i) else i = i + 1 end
    else
      i = i + 1
    end
  end
  return ran
end

return Env
