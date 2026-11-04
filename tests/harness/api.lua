-- tests/harness/api.lua
-- Tag-driven API layer. Every documented global function the addon can reach goes
-- through Api.define, which enforces, from api_tags:
--   * SecretArguments: AllowedWhenUntainted/NotAllowed reject secrets; AllowedWhenTainted
--     accepts them except on NeverSecret arguments.
--   * HasRestrictions -> ADDON_ACTION_FORBIDDEN (returns nothing).
--   * IsProtectedFunction in combat lockdown -> ADDON_ACTION_BLOCKED.
--   * Requires* preconditions (aura access errors, identity access, ...).
--   * Secret returns per SecretReturns / SecretWhen<Pred> / SecretIn<Pred> and the
--     harness mode (open, field, strict), honouring per-field NeverSecret.
-- Functions without a concrete mock get a generic stub returning zero values.

local Secret = require("secret")

local Api = {}

-- Return-secrecy tags that depend on object state, not world state.
local OBJECT_PREDICATES = {
  SecretWhenAnchoringSecret = true, SecretWhenCurveSecret = true,
  SecretWhenLuaTableHasSecretKeys = true, SecretWhenNumericFormatterSecret = true,
}

-- Restricted functions an addon may still call outside lockdown (verified usage).
Api.restrictedAllowedWhen = {
  ["C_ChatInfo.SendChatMessage"] = function(h) return not h.world:chatLockdown() end,
}

local function unitArgIndex(entry)
  for i, a in ipairs(entry.args or {}) do
    local n, t = a[1], a[2] or ""
    if t:match("^UnitToken") or n == "unit" or n == "unitToken" then return i end
  end
end

local function secondUnitArgIndex(entry)
  local first = unitArgIndex(entry)
  if not first then return end
  for i, a in ipairs(entry.args or {}) do
    if i > first and ((a[2] or ""):match("^UnitToken") or (a[1] or ""):lower():match("unit")) then return i end
  end
end

-- Is predicate `pred` true right now for this call?
function Api.predicateHolds(h, pred, entry, args, name)
  local mode, w = h.mode, h.world
  if mode == "open" then return false end
  if mode == "strict" then return true end
  -- field mode: measured 70338 behaviour (parity doc §2.2 table), refined by Session A
  local ui = unitArgIndex(entry)
  local unit = ui and args[ui]
  if Secret.is(unit) then unit = Secret.raw(unit) end
  if pred == "SecretReturns" then
    return w:fieldAlwaysSecret(entry, args, name)
  elseif pred == "SecretWhenUnitAuraRestricted" or pred == "SecretWhenAurasRestricted"
      or pred == "SecretWhenCooldownsRestricted" or pred == "SecretWhenTotemSlotSecret" then
    return w:aurasRestricted()
  elseif pred == "SecretWhenInCombat" then
    return w:restrictionActive("Combat")
  elseif pred == "SecretWhenUnitIdentityRestricted" or pred == "SecretWhenUnitNameIdentityRestricted" then
    return w:identitySecret(unit, pred == "SecretWhenUnitNameIdentityRestricted")
  elseif pred == "SecretWhenUnitHealthMaxRestricted" or pred == "SecretWhenUnitPowerMaxRestricted"
      or pred == "SecretWhenUnitPossessionRestricted" then
    return not w:isPlayerControlled(unit)
  elseif pred == "SecretWhenUnitPowerRestricted" then
    local pi
    for i, a in ipairs(entry.args or {}) do if a[1] == "powerType" then pi = i end end
    local ptype = pi and args[pi]
    if ptype == nil and unit then ptype = w:get(unit) and w:get(unit).powerType end
    return w:powerSecret(unit, ptype)
  elseif pred == "SecretWhenUnitSpellCastRestricted" then
    return not (unit == "player" or unit == "pet" or (unit and w:isUnit(unit, "player")))
  elseif pred == "SecretWhenUnitStatsRestricted" or pred == "SecretWhenLossOfControlInfoRestricted" then
    return unit ~= nil and unit ~= "player"
  elseif pred == "SecretWhenUnitThreatStateRestricted" or pred == "SecretWhenUnitThreatValuesRestricted" then
    local si = secondUnitArgIndex(entry)
    local other = si and args[si]
    return w:threatSecret(unit, other, pred == "SecretWhenUnitThreatValuesRestricted")
  elseif pred == "SecretWhenUnitComparisonRestricted" then
    local si = secondUnitArgIndex(entry)
    local other = si and args[si]
    return w:restrictionActive("Map") and (w:isCompound(unit) or w:isCompound(other))
  elseif pred == "SecretInChatMessagingLockdown" then
    return w:chatLockdown()
  elseif pred == "SecretInActivePvPMatch" then
    return w:restrictionActive("PvPMatch")
  elseif pred == "SecretWhenEncounterEvent" then
    return w:restrictionActive("Encounter")
  end
  return false
end

-- Returns true when this call's returns should be secret.
function Api.returnsSecret(h, entry, args, name)
  if not entry or entry.ReturnsNeverSecret then return false end
  if h.mode == "open" then return false end
  for k in pairs(entry) do
    if type(k) == "string" and not OBJECT_PREDICATES[k]
        and (k == "SecretReturns" or k:match("^SecretWhen") or k:match("^SecretIn")) then
      if Api.predicateHolds(h, k, entry, args, name) then return true end
    end
  end
  return false
end

local function wrapStruct(h, structName, t)
  local fields = h.tags.structs[structName]
  if not fields or type(t) ~= "table" then return t end
  for _, f in ipairs(fields) do
    if not f.NeverSecret and t[f[1]] ~= nil then t[f[1]] = Secret.wrap(t[f[1]]) end
  end
  return t
end

-- Wrap returns according to per-field NeverSecret; struct tables get their fields wrapped.
function Api.wrapReturns(h, entry, n, ...)
  local rets = entry.rets or {}
  local t = { ... }
  for i = 1, n do
    local r = rets[i]
    local v = t[i]
    if v ~= nil and not (r and r.NeverSecret) then
      if type(v) == "table" and r and h.tags.structs[r[2]] then
        t[i] = wrapStruct(h, r[2], v)
      elseif type(v) == "table" and r and r.inner and h.tags.structs[r.inner] then
        for _, item in ipairs(v) do wrapStruct(h, r.inner, item) end
      elseif type(v) ~= "table" and type(v) ~= "function" then
        t[i] = Secret.wrap(v)
      end
    end
  end
  return unpack(t, 1, n)
end

-- Argument rule shared by functions and widget methods.
function Api.checkSecretArgs(label, entry, ...)
  if not entry then return end
  local mode = entry.SecretArguments
  local n = select("#", ...)
  for i = 1, n do
    local v = select(i, ...)
    if Secret.is(v) then
      local a = entry.args and entry.args[i]
      if mode ~= "AllowedWhenTainted" or (a and a.NeverSecret) then
        error(string.format("%s: Object did not allow secret (argument #%d%s)", label, i,
          a and (" '" .. a[1] .. "'") or ""), 3)
      end
    elseif type(v) == "table" and Secret.isTable(v) and mode ~= "AllowedWhenTainted" then
      error(string.format("%s: Object did not allow secret table (argument #%d)", label, i), 3)
    end
  end
end

local function zeroFor(h, r)
  if r.nilable then return nil end
  local t = r[2]
  if t == "number" or t == "luaIndex" or t == "uiUnit" or t == "SingleColorValue" or t == "fileID"
      or t == "time_t" or t:match("^u?int") then
    return 0
  elseif t == "bool" then return false
  elseif t == "string" or t == "cstring" or t == "WOWGUID" or t == "textureAtlas" then return ""
  elseif t == "table" then return {}
  end
  if h.tags.enums[t] then return 0 end
  return nil
end

-- Wrap an implementation with every tag-driven rule. impl may be nil (generic stub).
function Api.define(h, name, impl)
  local entry = h.tags.functions[name]
  local label = name
  local fn = function(...)
    local n = select("#", ...)
    if entry then
      Api.checkSecretArgs(label, entry, ...)
      if entry.HasRestrictions then
        local allow = Api.restrictedAllowedWhen[name]
        if not (allow and allow(h)) then
          h:forbidden(name)
          return
        end
      end
      if entry.IsProtectedFunction and h.world.inCombat then
        h:blockedAction(name)
        return
      end
      if entry.RequiresUnitAuraAccess and h.world:aurasSecretForAccess() then
        error("Auras cannot be accessed when secret while tainted by '" .. h.addonName .. "'", 2)
      end
      if entry.RequiresDeclassifiedUnitIdentity or entry.RequiresUnitIdentityAccess then
        local ui = unitArgIndex(entry)
        local u = ui and select(ui, ...)
        if u and not Secret.is(u) and h.world:identitySecret(u) then
          error(name .. ": unit identity is secret", 2)
        end
      end
    end
    local res
    if impl then
      res = { impl(...) }
    else
      res = {}
      for i, r in ipairs(entry and entry.rets or {}) do res[i] = zeroFor(h, r) end
    end
    local rn = table.maxn(res)
    if entry and rn > 0 and Api.returnsSecret(h, entry, { ... }, name) then
      return Api.wrapReturns(h, entry, rn, unpack(res, 1, rn))
    end
    local _ = n
    return unpack(res, 1, rn)
  end
  h.apiCalls[name] = h.apiCalls[name] or 0
  local function finish(ok, ...)
    if not ok then
      local e = ...
      if type(e) == "string" then e = e:gsub("^[^\n]-tests/harness/[^:]*:%d+: ", "") end
      error(e, 3)
    end
    return ...
  end
  return function(...)
    h.apiCalls[name] = h.apiCalls[name] + 1
    return finish(pcall(fn, ...))
  end
end

-- Install fn as `name` ("Foo" or "C_X.Foo") in the sandbox env.
function Api.set(h, name, impl)
  local ns, key = name:match("^([%w_]+)%.([%w_]+)$")
  local f = Api.define(h, name, impl)
  if ns then
    h.env[ns] = h.env[ns] or {}
    h.env[ns][key] = f
  else
    h.env[name] = f
  end
  return f
end

-- Generic stubs for every documented function not already present.
function Api.installStubs(h)
  local count = 0
  for name in pairs(h.tags.functions) do
    local ns, key = name:match("^([%w_]+)%.([%w_]+)$")
    local exists
    if ns then exists = type(h.env[ns]) == "table" and h.env[ns][key] ~= nil else exists = h.env[name] ~= nil end
    if not exists then
      Api.set(h, name, nil)
      count = count + 1
    end
  end
  return count
end

-- Enum table for the sandbox, from the docs.
function Api.buildEnum(h)
  local Enum = {}
  for name, values in pairs(h.tags.enums) do
    local t = {}
    for k, v in pairs(values) do t[k] = v end
    Enum[name] = t
  end
  local Constants = {}
  for name, values in pairs(h.tags.constants) do
    local t = {}
    for k, v in pairs(values) do t[k] = v end
    Constants[name] = t
  end
  return Enum, Constants
end

return Api
