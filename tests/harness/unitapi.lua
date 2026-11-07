-- tests/harness/unitapi.lua
-- Concrete Unit*/group/aura/cast/threat/C_Secrets functions computed from the world.
-- Each goes through Api.set, so argument rules and return secrecy come from api_tags;
-- the bodies here only compute plain values.

local Secret = require("secret")
local Api = require("api")
local World = require("world")

local U = {}

function U.install(h)
  local env = h.env
  local w = h.world
  local tags = h.tags
  local raw = Secret.raw
  local function set(name, f) return Api.set(h, name, f) end
  local function get(unit) return w:get(raw(unit)) end
  local function secretNow(name, ...) return Api.returnsSecret(h, tags.functions[name], { ... }, name) end

  ---------------------------------------------------------------------------
  -- Identity
  ---------------------------------------------------------------------------
  set("UnitExists", function(u) return get(u) ~= nil end)
  set("UnitGUID", function(u) local x = get(u); return x and x.guid end)
  set("UnitName", function(u) local x = get(u); if x then return x.name, x.surname end end)
  set("UnitFullName", function(u) local x = get(u); if x then return x.name, x.surname end end)
  set("UnitNameUnmodified", function(u) local x = get(u); if x then return x.name, x.surname end end)
  env.GetUnitName = function(u, showServer)
    local name, server = env.UnitName(u)
    if showServer and server then return name .. "-" .. server end
    return name
  end
  local function classOf(x)
    local token = x.class or "WARRIOR"
    local c = World.CLASSES[token] or World.CLASSES.WARRIOR
    return c.name, token, c.id
  end
  set("UnitClass", function(u) local x = get(u); if x then return classOf(x) end end)
  set("UnitClassBase", function(u) local x = get(u); if x then local _, t, id = classOf(x); return t, id end end)
  set("UnitRace", function(u) local x = get(u); if x then return x.race or "Human", x.race or "Human", 1 end end)
  set("UnitSex", function(u) local x = get(u); if x then return x.sex or 2 end end)
  set("UnitLevel", function(u) local x = get(u); return x and x.level or 0 end)
  set("UnitEffectiveLevel", function(u) local x = get(u); return x and x.level or 0 end)
  set("UnitClassification", function(u) local x = get(u); return x and x.classification or "normal" end)
  set("UnitIsPlayer", function(u) local x = get(u); return x ~= nil and x.isPlayer == true end)
  set("UnitPlayerControlled", function(u) local x = get(u); return x ~= nil and x.playerControlled == true end)
  set("UnitIsUnit", function(a, b) return w:isUnit(raw(a), raw(b)) end)
  set("UnitCreatureType", function(u) local x = get(u); if x then return x.creatureType or (x.isPlayer and "Humanoid" or "Beast"), 7 end end)
  set("UnitCreatureFamily", function(u) local x = get(u); if x then return x.creatureFamily end end)
  set("UnitFactionGroup", function(u) local x = get(u); if x then return x.faction or "Alliance", x.faction or "Alliance" end end)
  set("UnitPVPName", function(u) local x = get(u); return x and x.name end)
  set("UnitIsVisible", function(u) local x = get(u); return x ~= nil and x.visible ~= false end)
  set("UnitPhaseReason", function(u) local x = get(u); return x and x.phaseReason end)

  ---------------------------------------------------------------------------
  -- Health and power
  ---------------------------------------------------------------------------
  set("UnitHealth", function(u) local x = get(u); return x and x.health or 0 end)
  set("UnitHealthMax", function(u) local x = get(u); return x and x.maxHealth or 0 end)
  set("UnitHealthMissing", function(u) local x = get(u); return x and (x.maxHealth - x.health) or 0 end)
  set("UnitHealthPercent", function(u, usePredicted, curve)
    local x = get(u)
    local p = (x and x.maxHealth > 0) and (x.health / x.maxHealth) or 0
    return h.evalCurveResult(curve, p, secretNow("UnitHealthPercent", u, usePredicted, curve))
  end)
  local function powerOf(x, ptype)
    if ptype == nil or ptype == x.powerType then return x.power, x.maxPower end
    if ptype == 4 then return w.comboPoints, 5 end
    if ptype == 27 then return x.happiness or 0, 3 end
    if ptype == 0 and x.mana then return x.mana, x.maxMana or x.maxPower end
    return 0, 0
  end
  set("UnitPower", function(u, ptype) local x = get(u); if not x then return 0 end; return (powerOf(x, ptype)) end)
  set("UnitPowerMax", function(u, ptype) local x = get(u); if not x then return 0 end; local _, m = powerOf(x, ptype); return m end)
  set("UnitPowerType", function(u)
    local x = get(u)
    local t = x and x.powerType or 0
    return t, World.POWER_TOKENS[t] or "MANA"
  end)
  set("UnitPowerPercent", function(u, ptype, unmodified, curve)
    local x = get(u)
    local p = 0
    if x then local cur, max = powerOf(x, ptype); p = max > 0 and cur / max or 0 end
    return h.evalCurveResult(curve, p, secretNow("UnitPowerPercent", u, ptype, unmodified, curve))
  end)
  set("UnitPowerMissing", function(u, ptype) local x = get(u); if not x then return 0 end; local c, m = powerOf(x, ptype); return m - c end)
  set("GetComboPoints", function(unit, target)
    if raw(unit) ~= "player" and raw(unit) ~= "vehicle" then return 0 end
    if not get(target) then return 0 end
    return w.comboPoints
  end)
  set("UnitGetIncomingHeals", function(u) local x = get(u); return x and x.incomingHeals or 0 end)
  set("UnitGetTotalAbsorbs", function(u) local x = get(u); return x and x.absorbs or 0 end)
  set("UnitGetTotalHealAbsorbs", function(u) local x = get(u); return x and x.healAbsorbs or 0 end)
  set("UnitGetDetailedHealPrediction", function(u, healer, calc)
    local x = get(u)
    if not x then return end
    h.fillHealCalculator(calc, x, raw(healer) == "player")
  end)

  ---------------------------------------------------------------------------
  -- States and flags
  ---------------------------------------------------------------------------
  local function flag(name, field)
    set(name, function(u) local x = get(u); return x ~= nil and x[field] == true end)
  end
  flag("UnitIsDead", "dead")
  flag("UnitIsGhost", "ghost")
  flag("UnitIsAFK", "afk")
  flag("UnitOnTaxi", "onTaxi")
  flag("UnitIsDND", "dnd")
  flag("UnitIsPVP", "pvp")
  flag("UnitIsPVPFreeForAll", "ffa")
  flag("UnitIsFeignDeath", "feign")
  flag("UnitIsCharmed", "charmed")
  flag("UnitIsTapDenied", "tapDenied")
  flag("UnitIsPossessed", "possessed")
  set("UnitIsDeadOrGhost", function(u) local x = get(u); return x ~= nil and (x.dead == true or x.ghost == true) end)
  set("UnitIsConnected", function(u) local x = get(u); return x ~= nil and x.connected ~= false end)
  set("UnitAffectingCombat", function(u)
    local x = get(u)
    if not x then return false end
    if x.inCombat ~= nil then return x.inCombat end
    return w.inCombat
  end)
  set("UnitReaction", function(a, b)
    local x, y = get(a), get(b)
    if not x or not y then return nil end
    if x.isPlayer and y.isPlayer then return 5 end
    return (x.guid == w.tokens.player) and y.reaction or x.reaction
  end)
  set("UnitCanAttack", function(a, b)
    local x, y = get(a), get(b)
    if not x or not y then return false end
    local r = (x.guid == w.tokens.player) and y.reaction or x.reaction
    return (r or 4) <= 3 or y.hostile == true
  end)
  set("UnitCanAssist", function(a, b)
    local x, y = get(a), get(b)
    if not x or not y then return false end
    local r = (x.guid == w.tokens.player) and y.reaction or x.reaction
    return (r or 4) >= 5 and y.hostile ~= true
  end)
  set("UnitIsFriend", function(a, b) return env.UnitCanAssist(a, b) end)
  set("UnitIsEnemy", function(a, b) return env.UnitCanAttack(a, b) end)
  set("UnitSelectionColor", function(u)
    local x = get(u)
    local r = x and x.reaction or 4
    if r <= 3 then return 1, 0, 0, 1 elseif r == 4 then return 1, 1, 0, 1 end
    return 0, 1, 0, 1
  end)
  set("UnitHasIncomingResurrection", function(u) local x = get(u); return x ~= nil and x.incomingRes == true end)
  env.C_IncomingSummon = env.C_IncomingSummon or {}
  set("C_IncomingSummon.HasIncomingSummon", function(u) local x = get(u); return x ~= nil and x.incomingSummon ~= nil end)
  set("C_IncomingSummon.IncomingSummonStatus", function(u) local x = get(u); return x and x.incomingSummon or 0 end)

  ---------------------------------------------------------------------------
  -- Group and roster
  ---------------------------------------------------------------------------
  local function rosterIndex(u)
    local x = get(u)
    if not x or not w.roster then return nil end
    for i, r in ipairs(w.roster) do if r.guid == x.guid then return i end end
  end
  env.GetNumGroupMembers = function() return w:numGroupMembers() end
  env.GetNumSubgroupMembers = function() if not w.group then return 0 end; local n = 0
    for tok in pairs(w.tokens) do if tok:match("^party%d$") then n = n + 1 end end; return n end
  env.IsInGroup = function() return w.group ~= nil end
  env.IsInRaid = function() return w.group == "raid" end
  set("UnitInParty", function(u) return w.group ~= nil and rosterIndex(u) ~= nil end)
  set("UnitInRaid", function(u) if w.group == "raid" then return rosterIndex(u) end end)
  set("UnitIsGroupLeader", function(u) local x = get(u); return x ~= nil and x.leader == true end)
  set("UnitIsGroupAssistant", function(u) local x = get(u); return x ~= nil and x.assistant == true end)
  set("UnitIsRaidOfficer", function(u) local x = get(u); return x ~= nil and (x.leader == true or x.assistant == true) end)
  set("UnitGroupRolesAssigned", function(u) local x = get(u); return x and x.role or "NONE" end)
  env.GetRaidRosterInfo = function(i)
    if w.group ~= "raid" or not w.roster or not w.roster[i] then return nil end
    local x = w.units[w.roster[i].guid]
    local cname, token = classOf(x)
    local rank = x.leader and 2 or (x.assistant and 1 or 0)
    return x.name, rank, x.subgroup or w.roster[i].subgroup, x.level, cname, token, "Zone",
      x.connected ~= false, x.dead == true, x.raidRole, x.masterLooter == true, x.role or "NONE"
  end
  env.GetPartyAssignment = function(role, u)
    local x = get(u)
    return x ~= nil and x.raidRole == role
  end
  env.IsMasterLooter = function() return w.lootMethod == 2 and w.masterLooterPartyID == 0 end
  env.GetReadyCheckStatus = function(u)
    local x = get(u)
    return x and x.readyCheck
  end
  env.GetReadyCheckTimeLeft = function() return w.readyCheckLeft or 0 end
  set("GetRaidTargetIndex", function(u) local x = get(u); return x and x.raidTarget end)
  set("C_PartyInfo.GetLootMethod", function() return w.lootMethod, w.masterLooterPartyID, w.masterLooterRaidID end)
  set("UnitInRange", function(u)
    local x = get(u)
    if not x or raw(u) == "player" then return false, false end
    return x.inRange ~= false, true
  end)
  set("CheckInteractDistance", function(u) local x = get(u); return x ~= nil and x.inRange ~= false end)
  env.C_Spell = env.C_Spell or {}
  set("C_Spell.IsSpellInRange", function(spell, u)
    local x = get(u or "target")
    if not x then return nil end
    local r = w.spellRange[raw(u or "target")]
    if r == nil then return x.inRange ~= false end
    return r
  end)
  set("C_Spell.GetSpellName", function(id) if id then return w.spellNames and w.spellNames[id] or ("Spell " .. tostring(raw(id))) end end)
  set("C_Spell.GetSpellTexture", function(id) if id then return 136000 + (tonumber(raw(id)) or 0) % 1000, 136000 end end)
  set("C_Spell.GetSpellInfo", function(id)
    if not id then return nil end
    return { name = env.C_Spell.GetSpellName(id), iconID = 136000, originalIconID = 136000, castTime = 0, minRange = 0, maxRange = 40, spellID = id }
  end)
  set("C_Spell.DoesSpellExist", function(id) return id ~= nil end)
  set("C_Spell.EnableSpellRangeCheck", function(id, on) w.rangeChecks = w.rangeChecks or {}; w.rangeChecks[id] = on end)

  ---------------------------------------------------------------------------
  -- Threat
  ---------------------------------------------------------------------------
  local function threatFor(u, mob)
    local x = get(u)
    if not x then return nil end
    local m = mob and get(mob)
    local t = x.threat[m and m.guid or "*"] or (not mob and x.threatStatus and { status = x.threatStatus }) or nil
    return t
  end
  set("UnitThreatSituation", function(u, mob) local t = threatFor(u, mob); return t and t.status end)
  set("UnitDetailedThreatSituation", function(u, mob)
    local t = threatFor(u, mob)
    if not t then return end
    return t.status >= 2, t.status, t.pct or 0, t.pct or 0, (t.pct or 0) * 100
  end)
  set("GetThreatStatusColor", function(s)
    local c = { [0] = { 0.69, 0.69, 0.69 }, { 1, 1, 0.47 }, { 1, 0.6, 0 }, { 1, 0, 0 } }
    local x = c[s or 0] or c[0]
    return x[1], x[2], x[3]
  end)

  ---------------------------------------------------------------------------
  -- Casts
  ---------------------------------------------------------------------------
  local function castOf(u, channel)
    local x = get(u)
    if not x or not x.casting or (x.casting.channel == true) ~= channel then return nil end
    return x.casting
  end
  set("UnitCastingInfo", function(u)
    local c = castOf(u, false)
    if not c then return end
    return c.name, c.text, c.texture, c.startTime, c.endTime, c.isTradeSkill, c.castID, c.notInterruptible, c.spellId, 1, 0
  end)
  set("UnitChannelInfo", function(u)
    local c = castOf(u, true)
    if not c then return end
    return c.name, c.text, c.texture, c.startTime, c.endTime, c.isTradeSkill, c.notInterruptible, c.spellId, false, 0, 1
  end)
  local function castDuration(u, channel)
    local c = castOf(u, channel)
    if not c then return nil end
    local secret = Api.predicateHolds(h, "SecretWhenUnitSpellCastRestricted", tags.functions.UnitCastingInfo, { u })
    return h.newDuration(c.startTime / 1000, (c.endTime - c.startTime) / 1000, secret)
  end
  set("UnitCastingDuration", function(u) return castDuration(u, false) end)
  set("UnitChannelDuration", function(u) return castDuration(u, true) end)

  ---------------------------------------------------------------------------
  -- Auras
  ---------------------------------------------------------------------------
  -- "PLAYER" means cast by you, your pet or your vehicle, and "!PLAYER" means
  -- anyone else. It doesn't go by isFromPlayerOrPlayerPet, which is about any player.
  local function matches(a, filter)
    local wants = {}
    for token in (filter or "HELPFUL"):upper():gmatch("[^|%s]+") do
      if token:sub(1, 1) == "!" then wants[token:sub(2)] = false else wants[token] = true end
    end
    if wants.HARMFUL then if not a.isHarmful then return false end
    elseif not a.isHelpful then return false end
    if wants.PLAYER ~= nil then
      local mine = a.sourceUnit == "player" or a.sourceUnit == "pet"
      if mine ~= wants.PLAYER then return false end
    end
    if wants.RAID_PLAYER_DISPELLABLE or (wants.RAID and a.isHarmful) then
      if not a.dispelName then return false end
    end
    if wants.CANCELABLE and a.isHarmful then return false end
    return true
  end
  local function auraCopy(a)
    local r = {}
    for k, v in pairs(a) do r[k] = v end
    return r
  end
  local function aurasOf(u, filter)
    local x = get(u)
    local r = {}
    if not x then return r end
    for _, a in ipairs(x.auras) do if matches(a, filter) then r[#r + 1] = a end end
    return r
  end
  set("C_UnitAuras.GetAuraDataByIndex", function(u, i, filter)
    local a = aurasOf(u, filter)[i]
    return a and auraCopy(a)
  end)
  set("C_UnitAuras.GetBuffDataByIndex", function(u, i, filter)
    local a = aurasOf(u, "HELPFUL" .. (filter and ("|" .. filter) or ""))[i]
    return a and auraCopy(a)
  end)
  set("C_UnitAuras.GetDebuffDataByIndex", function(u, i, filter)
    local a = aurasOf(u, "HARMFUL" .. (filter and ("|" .. filter) or ""))[i]
    return a and auraCopy(a)
  end)
  set("C_UnitAuras.GetAuraDataByAuraInstanceID", function(u, id)
    local x = get(u)
    for _, a in ipairs(x and x.auras or {}) do if a.auraInstanceID == raw(id) then return auraCopy(a) end end
  end)
  set("C_UnitAuras.GetUnitAuras", function(u, filter, maxCount)
    local r = {}
    for _, a in ipairs(aurasOf(u, filter)) do
      if maxCount and #r >= maxCount then break end
      r[#r + 1] = auraCopy(a)
    end
    return r
  end)
  set("C_UnitAuras.GetUnitAuraBySpellID", function(u, spellId, filter)
    for _, a in ipairs(aurasOf(u, filter)) do if a.spellId == spellId then return auraCopy(a) end end
  end)
  set("C_UnitAuras.GetPlayerAuraBySpellID", function(spellId)
    for _, a in ipairs(aurasOf("player", "HELPFUL")) do if a.spellId == spellId then return auraCopy(a) end end
    for _, a in ipairs(aurasOf("player", "HARMFUL")) do if a.spellId == spellId then return auraCopy(a) end end
  end)
  set("C_UnitAuras.GetAuraDataBySpellName", function(u, name, filter)
    for _, a in ipairs(aurasOf(u, filter)) do if a.name == name then return auraCopy(a) end end
  end)
  set("C_UnitAuras.GetAuraDuration", function(u, id)
    local x = get(u)
    for _, a in ipairs(x and x.auras or {}) do
      if a.auraInstanceID == raw(id) then
        return h.newDuration(a.expirationTime - a.duration, a.duration, h.mode ~= "open" and w:aurasRestricted() or nil)
      end
    end
  end)

  ---------------------------------------------------------------------------
  -- Player progression, pets, totems, misc
  ---------------------------------------------------------------------------
  set("UnitXP", function() return w.xp end)
  set("UnitXPMax", function() return w.xpMax end)
  set("GetXPExhaustion", function() return w.exhaustion > 0 and w.exhaustion or nil end)
  set("IsResting", function() return w.resting end)
  set("GetRestState", function() return w.exhaustion > 0 and 1 or 2, "Rested", 1 end)
  set("C_Reputation.GetWatchedFactionData", function() return w.watchedFaction end)
  set("C_PetInfo.GetPetHappiness", function()
    if not w:get("pet") or not w.petHappiness then return end
    return w.petHappiness, w.petDamagePct or 100, w.petLoyaltyRate or 0
  end)
  env.GetPetExperience = function() return w.petXP or 0, w.petXPMax or 1000 end
  env.GetPetLoyalty = function() return w.petLoyalty end
  env.GetShapeshiftForm = function() return w.shapeshiftForm or 0 end
  env.GetShapeshiftFormInfo = function(i) return 136000 + i, false, true, i end
  set("GetTotemInfo", function(slot)
    local t = w.totems[slot]
    if not t then return false, "", 0, 0, 0, 1, 0 end
    return true, t.name, t.start, t.duration, t.icon or 136000, 1, t.spellID or 0
  end)
  set("GetTotemDuration", function(slot)
    local t = w.totems[slot]
    return h.newDuration(t and t.start or 0, t and t.duration or 0, h.mode ~= "open" and w:aurasRestricted() or nil)
  end)
  set("GetPVPTimer", function() return w.pvpTimer or -1 end)
  env.GetNumClasses = function() return 11 end
  env.GetClassInfo = function(i)
    for token, c in pairs(World.CLASSES) do if c.id == i then return c.name, token, c.id end end
  end
  set("GetInstanceInfo", function()
    local t = w.instanceType
    return t == "none" and "Elwynn Forest" or "Instance", t, t == "none" and 0 or 1, "", t == "raid" and 40 or 5,
      0, false, t == "none" and 0 or 36, 5, nil
  end)
  set("IsInInstance", function() return w.instanceType ~= "none", w.instanceType end)
  set("C_ChatInfo.InChatMessagingLockdown", function() return w:chatLockdown() end)
  set("C_ChatInfo.SendAddonMessage", function(prefix, msg, chatType, target)
    h.addonMessages = h.addonMessages or {}
    local locked = w:chatLockdown()
    h.addonMessages[#h.addonMessages + 1] = { prefix = prefix, msg = msg, chatType = chatType, target = target, locked = locked }
    local R = env.Enum.SendAddonMessageResult or {}
    return locked and (R.AddOnMessageLockdown or 11) or (R.Success or 0)
  end)
  set("C_ChatInfo.RegisterAddonMessagePrefix", function() return true end)
  set("C_ChatInfo.SendChatMessage", function(msg, chatType)
    h.chatSent = h.chatSent or {}
    h.chatSent[#h.chatSent + 1] = { msg = msg, chatType = chatType }
  end)
  env.GetNetStats = function() return 0, 0, 50, 50 end
  env.IsTargetLoose = function() return false end
  set("C_PlayerInteractionManager.IsReplacingUnit", function() return false end)

  ---------------------------------------------------------------------------
  -- C_Secrets oracles and restriction queries, consistent with the mode
  ---------------------------------------------------------------------------
  local function oracle(name, pred, refFn)
    set(name, function(...)
      if h.mode == "open" then return false end
      return Api.predicateHolds(h, pred, tags.functions[refFn], { ... }, refFn)
    end)
  end
  set("C_Secrets.HasSecretRestrictions", function() return h.mode ~= "open" end)
  set("C_Secrets.ShouldAurasBeSecret", function() return w:aurasSecretForAccess() end)
  set("C_Secrets.ShouldCooldownsBeSecret", function() return w:aurasSecretForAccess() end)
  set("C_Secrets.ShouldUnitStatsBeSecret", function() return h.mode ~= "open" end)
  oracle("C_Secrets.ShouldUnitIdentityBeSecret", "SecretWhenUnitIdentityRestricted", "UnitGUID")
  oracle("C_Secrets.ShouldUnitHealthMaxBeSecret", "SecretWhenUnitHealthMaxRestricted", "UnitHealthMax")
  oracle("C_Secrets.ShouldUnitPowerBeSecret", "SecretWhenUnitPowerRestricted", "UnitPower")
  oracle("C_Secrets.ShouldUnitPowerMaxBeSecret", "SecretWhenUnitPowerMaxRestricted", "UnitPowerMax")
  oracle("C_Secrets.ShouldUnitSpellCastingBeSecret", "SecretWhenUnitSpellCastRestricted", "UnitCastingInfo")
  oracle("C_Secrets.ShouldUnitSpellCastBeSecret", "SecretWhenUnitSpellCastRestricted", "UnitCastingInfo")
  oracle("C_Secrets.ShouldUnitThreatStateBeSecret", "SecretWhenUnitThreatStateRestricted", "UnitThreatSituation")
  oracle("C_Secrets.ShouldUnitThreatValuesBeSecret", "SecretWhenUnitThreatValuesRestricted", "UnitDetailedThreatSituation")
  oracle("C_Secrets.ShouldUnitComparisonBeSecret", "SecretWhenUnitComparisonRestricted", "UnitIsUnit")
  set("C_Secrets.CanCompareUnitTokens", function() return true end)
  for _, n in ipairs({ "ShouldUnitAuraInstanceBeSecret", "ShouldUnitAuraIndexBeSecret", "ShouldUnitAuraSlotBeSecret",
    "ShouldSpellAuraBeSecret", "ShouldTotemSlotBeSecret", "ShouldTotemSpellBeSecret", "ShouldSpellCooldownBeSecret",
    "ShouldActionCooldownBeSecret" }) do
    set("C_Secrets." .. n, function() return w:aurasSecretForAccess() end)
  end
  set("C_Secrets.GetPowerTypeSecrecy", function(ptype)
    local L = env.Enum.SecrecyLevel
    if h.mode == "open" or w.neverSecretPower[ptype] then return L.NeverSecret end
    if h.mode == "strict" then return L.AlwaysSecret end
    return L.ContextuallySecret
  end)
  for _, n in ipairs({ "GetSpellAuraSecrecy", "GetSpellCastSecrecy", "GetSpellCooldownSecrecy" }) do
    set("C_Secrets." .. n, function()
      local L = env.Enum.SecrecyLevel
      if h.mode == "open" then return L.NeverSecret end
      return L.ContextuallySecret
    end)
  end
  local typeNames = {}
  for name, v in pairs(env.Enum.AddOnRestrictionType) do typeNames[v] = name end
  set("C_RestrictedActions.IsAddOnRestrictionActive", function(t) return w:restrictionActive(typeNames[t] or t) end)
  set("C_RestrictedActions.GetAddOnRestrictionState", function(t)
    local S = env.Enum.AddOnRestrictionState
    return w:restrictionActive(typeNames[t] or t) and S.Active or S.Inactive
  end)
  set("C_RestrictedActions.CheckAllowProtectedFunctions", function(obj)
    return not (w.inCombat and obj and h.widgets.isProtected(obj))
  end)
end

return U
