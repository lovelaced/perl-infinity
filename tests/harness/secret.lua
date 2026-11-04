-- tests/harness/secret.lua
-- Secret value simulation (parity doc §2.2). A secret is a newproxy userdata whose
-- payload lives in a weak side table. Every operation tainted WoW code may not do
-- on a secret raises an error; concatenation yields another secret string.
--
-- What it can't catch (see parity doc §2.4): truth tests on secret booleans (a proxy
-- is always truthy), `secret == 5` (Lua only calls __eq for two userdata), and secrets
-- used as table keys. Lint rules L1-L3 and the SavedVariables serializer cover those.

local Secret = { taint = "PerlInfinity" }

local store = setmetatable({}, { __mode = "k" })        -- proxy -> { kind, v }
local secretTables = setmetatable({}, { __mode = "k" }) -- tables flagged secret
local proto = newproxy(true)
local mt = getmetatable(proto)

local realType, realToString, realToNumber = type, tostring, tonumber
-- keep the original even if this file is loaded twice
local realFormat = rawget(string, "_realFormat") or string.format
rawset(string, "_realFormat", realFormat)

local function fail(msg, level)
  error(realFormat("%s (execution tainted by '%s')", msg, Secret.taint), level or 3)
end
Secret.fail = fail

local function deny(op)
  return function() fail("attempt to " .. op .. " a secret value", 3) end
end
for _, k in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm" }) do
  mt[k] = deny("perform arithmetic on")
end
mt.__lt = deny("compare")
mt.__le = deny("compare")
mt.__eq = deny("compare") -- only reached for proxy == proxy; proxy == 5 is plain false
mt.__index = deny("index")
mt.__newindex = deny("index")
mt.__call = deny("call")
mt.__len = deny("get length of")
mt.__tostring = function(p) local s = store[p]; return "<secret:" .. (s and s.kind or "?") .. ">" end
mt.__metatable = "secret"

function Secret.is(v)
  return realType(v) == "userdata" and store[v] ~= nil
end
local isSecret = Secret.is

function Secret.raw(v)
  local s = isSecret(v) and store[v]
  if s then return s.v end
  return v
end

function Secret.kind(v)
  local s = isSecret(v) and store[v]
  return s and s.kind
end

-- Secret.new(kind, v): secret nil is plain nil (WoW lets you nil-test secrets).
function Secret.new(kind, v)
  if v == nil then return nil end
  if isSecret(v) then return v end
  local p = newproxy(proto)
  store[p] = { kind = kind or realType(v), v = v }
  return p
end

function Secret.wrap(v)
  if v == nil or isSecret(v) then return v end
  return Secret.new(realType(v), v)
end

function Secret.wrapAll(...)
  local n = select("#", ...)
  if n == 0 then return end
  local t = { ... }
  for i = 1, n do t[i] = Secret.wrap(t[i]) end
  return unpack(t, 1, n)
end

function Secret.anySecret(...)
  for i = 1, select("#", ...) do if isSecret((select(i, ...))) then return true end end
  return false
end

-- Deep unwrap for test assertions only.
function Secret.rawDeep(v, seen)
  if isSecret(v) then return Secret.raw(v) end
  if realType(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local r = {}
  seen[v] = r
  for k, x in pairs(v) do r[Secret.rawDeep(k, seen)] = Secret.rawDeep(x, seen) end
  return r
end

function Secret.markTable(t, flag)
  if flag == false then secretTables[t] = nil else secretTables[t] = true end
  return t
end
function Secret.isTable(t) return secretTables[t] == true end

-- Concatenation: any secret operand makes the result a secret string.
mt.__concat = function(a, b)
  local ra, rb = Secret.raw(a), Secret.raw(b)
  local ta, tb = realType(ra), realType(rb)
  if (ta ~= "string" and ta ~= "number") or (tb ~= "string" and tb ~= "number") then
    error("attempt to concatenate a " .. (ta ~= "string" and ta ~= "number" and ta or tb) .. " value", 2)
  end
  return Secret.new("string", ra .. rb)
end

---------------------------------------------------------------------------
-- Secret-aware replacements for the sandbox (and the global string.format)
---------------------------------------------------------------------------

-- type(secret) reports the underlying kind, as WoW does.
function Secret.type(v)
  local s = isSecret(v) and store[v]
  if s then return s.kind end
  return realType(v)
end

function Secret.tostring(v)
  if isSecret(v) then return Secret.new("string", realToString(Secret.raw(v))) end
  return realToString(v)
end

function Secret.tonumber(v, base)
  if isSecret(v) then fail("attempt to convert a secret value with tonumber", 3) end
  return realToNumber(v, base)
end

-- string.format: any secret argument makes the result a secret string. Precision on
-- %s with a secret string ("%.3s") is refused, matching 12.0.1.
function Secret.format(fmt, ...)
  local n = select("#", ...)
  local any = isSecret(fmt)
  if not any then
    for i = 1, n do if isSecret((select(i, ...))) then any = true; break end end
  end
  if not any then return realFormat(fmt, ...) end
  local rawFmt = Secret.raw(fmt)
  local args = { ... }
  local argi = 0
  for flags, prec, conv in rawFmt:gmatch("%%([%-%+ #0]*%d*)(%.?%d*)([%a%%])") do
    if conv ~= "%" then
      argi = argi + 1
      if conv == "s" and prec ~= "" and isSecret(args[argi]) then
        fail("invalid format precision (%.Ns) for a secret string", 3)
      end
    end
    local _ = flags
  end
  for i = 1, n do args[i] = Secret.raw(args[i]) end
  return Secret.new("string", realFormat(rawFmt, unpack(args, 1, n)))
end

-- strjoin / string.join / strconcat / table.concat with secrets -> secret string.
function Secret.join(sep, ...)
  local n = select("#", ...)
  local any = isSecret(sep)
  local parts = {}
  for i = 1, n do
    local v = select(i, ...)
    if isSecret(v) then any = true end
    parts[i] = realToString(Secret.raw(v))
  end
  local s = table.concat(parts, realToString(Secret.raw(sep)))
  if any then return Secret.new("string", s) end
  return s
end

function Secret.concat(...) return Secret.join("", ...) end

function Secret.tableConcat(t, sep, i, j)
  local any = isSecret(sep)
  i = i or 1
  j = j or #t
  local parts = {}
  for k = i, j do
    local v = t[k]
    if isSecret(v) then any = true; v = Secret.raw(v) end
    parts[#parts + 1] = v
  end
  local s = table.concat(parts, Secret.raw(sep) or "")
  if any then return Secret.new("string", s) end
  return s
end

---------------------------------------------------------------------------
-- WoW secret helpers exposed to addon code
---------------------------------------------------------------------------
function Secret.installHelpers(env)
  env.issecretvalue = function(v) return isSecret(v) end
  env.canaccessvalue = function(v) return not isSecret(v) end
  env.canaccessallvalues = function(...) return not Secret.anySecret(...) end
  env.hasanysecretvalues = function(...) return Secret.anySecret(...) end
  env.issecrettable = function(t) return realType(t) == "table" and secretTables[t] == true end
  env.canaccesstable = function(t) return not (realType(t) == "table" and secretTables[t] == true) end
  env.canaccesssecrets = function() return false end
  env.dropsecretaccess = function() end
  env.secretwrap = function(...) return Secret.wrapAll(...) end
  env.scrubsecretvalues = function(...)
    local n = select("#", ...)
    local t = { ... }
    for i = 1, n do if isSecret(t[i]) then t[i] = nil end end
    return unpack(t, 1, n)
  end
  env.scrub = function(...)
    local n = select("#", ...)
    local t = { ... }
    for i = 1, n do
      local v = t[i]
      local tv = realType(v)
      if isSecret(v) or not (tv == "number" or tv == "string" or tv == "boolean" or tv == "nil") then t[i] = nil end
    end
    return unpack(t, 1, n)
  end
end

-- Patch the global string.format once, so `("%d"):format(secret)` works through the
-- shared string metatable. Non-secret calls behave exactly like the original.
string.format = Secret.format

return Secret
