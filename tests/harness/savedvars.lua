-- tests/harness/savedvars.lua
-- WoW-style SavedVariables serializer and parser. Serialization reports a problem for
-- anything the client can't (or must not) save: secret values or keys, functions,
-- userdata (frames carry userdata at [0]), cycles, table keys, NaN/inf.

local Secret = require("secret")

local SV = {}

local function keyRepr(k)
  if type(k) == "string" then return string.format("[%q]", k) end
  if type(k) == "number" then return "[" .. string.format("%.17g", k) .. "]" end
  if type(k) == "boolean" then return "[" .. tostring(k) .. "]" end
end

local function serializeValue(v, path, problems, seen, indent)
  if Secret.is(v) then
    problems[#problems + 1] = path .. ": secret value (" .. tostring(Secret.kind(v)) .. ")"
    return "nil"
  end
  local t = type(v)
  if t == "string" then return string.format("%q", v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then problems[#problems + 1] = path .. ": non-finite number"; return "0" end
    if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
    return string.format("%.17g", v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "nil" then return "nil"
  elseif t == "table" then
    if seen[v] then problems[#problems + 1] = path .. ": cycle"; return "nil" end
    seen[v] = true
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta ~= tb then return ta < tb end
      if ta == "string" or ta == "number" then return a < b end
      return tostring(a) < tostring(b)
    end)
    local parts = { "{\n" }
    for _, k in ipairs(keys) do
      local kp = path .. "[" .. tostring(Secret.is(k) and "<secret>" or k) .. "]"
      if Secret.is(k) then problems[#problems + 1] = kp .. ": secret table key"
      else
        local kr = keyRepr(k)
        if not kr then problems[#problems + 1] = kp .. ": unsupported key type " .. type(k)
        else
          parts[#parts + 1] = indent .. "\t" .. kr .. " = " .. serializeValue(v[k], kp, problems, seen, indent .. "\t") .. ",\n"
        end
      end
    end
    parts[#parts + 1] = indent .. "}"
    seen[v] = nil
    return table.concat(parts)
  else
    problems[#problems + 1] = path .. ": " .. t .. " cannot be saved"
    return "nil"
  end
end

-- Returns text, problems.
function SV.serialize(env, names)
  local problems = {}
  local out = {}
  for _, name in ipairs(names) do
    local v = rawget(env, name)
    out[#out + 1] = name .. " = " .. serializeValue(v, name, problems, {}, "") .. "\n"
  end
  return table.concat(out), problems
end

-- Loads a SavedVariables file body in an empty sandbox; returns { name = value }.
function SV.parse(text, chunkName)
  local fn, err = loadstring(text, chunkName or "=SavedVariables")
  if not fn then error(err) end
  local box = {}
  setfenv(fn, box)
  fn()
  return box
end

return SV
