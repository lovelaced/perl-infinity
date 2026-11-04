-- tests/harness/world.lua
-- Scenario state: units (by GUID, reached through unit tokens incl. compound tokens),
-- roster, combat/instance/encounter and forced restrictions, plus helpers that mutate
-- state and fire the events the real client would (world:damage("target", 120) fires
-- UNIT_HEALTH for every token that points at that unit).

local World = {}
World.__index = World

World.CLASSES = {
  WARRIOR = { id = 1, name = "Warrior", power = 1 }, PALADIN = { id = 2, name = "Paladin", power = 0 },
  HUNTER = { id = 3, name = "Hunter", power = 0 }, ROGUE = { id = 4, name = "Rogue", power = 3 },
  PRIEST = { id = 5, name = "Priest", power = 0 }, SHAMAN = { id = 7, name = "Shaman", power = 0 },
  MAGE = { id = 8, name = "Mage", power = 0 }, WARLOCK = { id = 9, name = "Warlock", power = 0 },
  DRUID = { id = 11, name = "Druid", power = 0 },
}
World.POWER_TOKENS = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY", [4] = "COMBO_POINTS", [27] = "HAPPINESS" }
World.RESTRICTION = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 }

local guidCounter = 0
local function newGUID(isPlayer)
  guidCounter = guidCounter + 1
  if isPlayer then return string.format("Player-1-%08X", guidCounter) end
  return string.format("Creature-0-1-0-1-%d-%010X", 1000 + guidCounter, guidCounter)
end

function World.new(h)
  local w = setmetatable({ h = h }, World)
  w:reset()
  return w
end

function World:reset()
  self.units, self.tokens = {}, {}
  self.inCombat, self.inEncounter, self.challenge, self.pvpMatch = false, false, false, false
  self.instanceType = "none"
  self.forced = {}
  self.group = nil            -- nil | "party" | "raid"
  self.lootMethod = 0         -- Enum.LootMethod.Freeforall
  self.masterLooterPartyID, self.masterLooterRaidID = nil, nil
  self.neverSecretPower = {}  -- field mode: power types measured as never secret
  self.fieldOverrides = {
    -- forever-bugs #166: readable out of combat, secret in combat
    GetRaidTargetIndex = function(w) return w:restrictionActive("Combat") end,
  }
  self.readyCheck = nil
  self.comboPoints = 0
  self.xp, self.xpMax, self.exhaustion, self.resting = 1200, 8800, 0, false
  self.watchedFaction = nil
  self.totems = {}
  self.petHappiness = nil
  self.shapeshiftForm = 0
  self.ranges = {}
  self.spellRange = {}
  self:addUnit("player", { name = "Testplayer", class = "DRUID", level = 60, isPlayer = true,
    health = 4000, maxHealth = 4000, power = 3000, maxPower = 3000, powerType = 0, reaction = 5 })
end

---------------------------------------------------------------------------
-- Units and tokens
---------------------------------------------------------------------------
function World:addUnit(token, spec)
  spec = spec or {}
  local u = {
    exists = true, connected = true, visible = true, inRange = true,
    level = 60, classification = "normal", reaction = 4, health = 1000, maxHealth = 1000,
    power = 100, maxPower = 100, auras = {}, threat = {}, raidTarget = nil, role = "NONE",
    incomingHeals = 0, absorbs = 0, healAbsorbs = 0,
  }
  for k, v in pairs(spec) do u[k] = v end
  if u.isPlayer == nil then u.isPlayer = (u.class ~= nil and not u.npc) end
  if u.playerControlled == nil then u.playerControlled = u.isPlayer or u.isPet or false end
  if u.isPlayer and u.class and not spec.powerType then
    u.powerType = World.CLASSES[u.class] and World.CLASSES[u.class].power or 0
  end
  u.powerType = u.powerType or 0
  u.name = u.name or (u.isPlayer and "Player" or "Creature")
  u.guid = u.guid or newGUID(u.isPlayer)
  self.units[u.guid] = u
  if token then self.tokens[token] = u.guid end
  return u
end

-- Point a token at an existing unit (by token or GUID); nil clears the token.
function World:alias(token, target)
  if target == nil then self.tokens[token] = nil; return end
  local u = self.units[target] or self:get(target)
  self.tokens[token] = u and u.guid
end

function World:isCompound(token)
  return type(token) == "string" and token ~= "target" and token:match("target$") ~= nil
end

-- Resolve a token (incl. compound "party1target", "targettarget") to a unit record.
function World:get(token)
  if type(token) ~= "string" then return nil end
  token = token:lower()
  local guid = self.tokens[token]
  if guid then return self.units[guid] end
  if self.units[token] then return self.units[token] end
  if #token > 6 and token:sub(-6) == "target" then
    local base = self:get(token:sub(1, -7))
    return base and base.target and self.units[base.target]
  end
  if token:sub(-3) == "pet" and #token > 3 then
    local owner = self:get(token:sub(1, -4))
    return owner and owner.pet and self.units[owner.pet]
  end
  return nil
end

function World:isUnit(a, b)
  local ua, ub = self:get(a), self:get(b)
  return ua ~= nil and ua == ub
end

-- Every base token that currently points at this unit (used for UNIT_* events).
function World:tokensFor(u)
  local r = {}
  for tok, guid in pairs(self.tokens) do if guid == u.guid then r[#r + 1] = tok end end
  table.sort(r)
  return r
end

function World:fireUnit(event, token, ...)
  local u = self:get(token)
  if not u then return end
  for _, tok in ipairs(self:tokensFor(u)) do self.h:fire(event, tok, ...) end
end

function World:isPlayerControlled(token)
  local u = self:get(token)
  return u ~= nil and (u.playerControlled == true)
end

function World:isGrouped(token)
  local u = self:get(token)
  if not u then return false end
  if u.guid == self.tokens.player then return true end
  for tok, guid in pairs(self.tokens) do
    if guid == u.guid and (tok:match("^party%d") or tok:match("^raid%d") or tok == "pet") then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Restrictions and secrecy oracles
---------------------------------------------------------------------------
function World:restrictionActive(kind)
  if self.forced[kind] then return true end
  if kind == "Combat" then return self.inCombat
  elseif kind == "Encounter" then return self.inEncounter
  elseif kind == "ChallengeMode" then return self.challenge
  elseif kind == "PvPMatch" then return self.pvpMatch
  elseif kind == "Map" then return self.instanceType ~= "none"
  elseif kind == "Chat" then return self.instanceType == "party" or self.instanceType == "raid" or self.inEncounter
  end
  return false
end

function World:aurasRestricted()
  return self:restrictionActive("Combat") or self:restrictionActive("Encounter")
    or self:restrictionActive("ChallengeMode") or self:restrictionActive("PvPMatch")
end

-- Used by RequiresUnitAuraAccess and C_Secrets.ShouldAurasBeSecret.
function World:aurasSecretForAccess()
  local mode = self.h.mode
  if mode == "open" then return false elseif mode == "strict" then return true end
  return self:aurasRestricted()
end

function World:chatLockdown()
  return self:restrictionActive("Chat") or self:restrictionActive("Encounter")
    or self:restrictionActive("ChallengeMode") or self:restrictionActive("PvPMatch")
end

function World:identitySecret(token, isName)
  local mode = self.h.mode
  if mode == "open" or token == nil then return false end
  local u = self:get(token)
  if not u then return false end
  if u.playerControlled or self:isGrouped(token) then
    -- compound tokens: secret if any link fails (handled by base resolution above)
    return false
  end
  if isName and self.pvpMatch and u.isPlayer then return false end
  if mode == "strict" then return true end
  return self:restrictionActive("Map") -- field: NPC identity measured secret on instanced maps
end

function World:powerSecret(token, ptype)
  local mode = self.h.mode
  if mode == "open" then return false elseif mode == "strict" then return true end
  if ptype ~= nil and self.neverSecretPower[ptype] then return false end
  return true
end

function World:threatSecret(unit, other, values)
  local mode = self.h.mode
  if mode == "open" then return false elseif mode == "strict" then return true end
  if self.forced.Threat then return true end
  if values and type(other) == "string" and other:match("^boss") then return true end
  return false
end

function World:fieldAlwaysSecret(entry, args, name)
  local o = name and self.fieldOverrides[name]
  if o then return o(self, args) end
  return true
end

---------------------------------------------------------------------------
-- State changes that fire events
---------------------------------------------------------------------------
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

function World:damage(token, amount)
  local u = assert(self:get(token), "no unit " .. tostring(token))
  u.health = clamp(u.health - amount, 0, u.maxHealth)
  if u.health == 0 then u.dead = true end
  self:fireUnit("UNIT_HEALTH", token)
  if self.inCombat or amount > 0 then self:fireUnit("UNIT_COMBAT", token, "WOUND", "", amount, 1) end
end

function World:heal(token, amount)
  local u = assert(self:get(token), "no unit " .. tostring(token))
  u.health = clamp(u.health + amount, 0, u.maxHealth)
  self:fireUnit("UNIT_HEALTH", token)
  self:fireUnit("UNIT_COMBAT", token, "HEAL", "", amount, 1)
end

function World:setHealth(token, cur, max)
  local u = assert(self:get(token))
  if max then u.maxHealth = max; self:fireUnit("UNIT_MAXHEALTH", token) end
  u.health = clamp(cur, 0, u.maxHealth)
  u.dead = u.health == 0 or nil
  self:fireUnit("UNIT_HEALTH", token)
end

function World:setPower(token, cur, max, ptype)
  local u = assert(self:get(token))
  if ptype and ptype ~= u.powerType then u.powerType = ptype; self:fireUnit("UNIT_DISPLAYPOWER", token) end
  if max then u.maxPower = max; self:fireUnit("UNIT_MAXPOWER", token, World.POWER_TOKENS[u.powerType] or "MANA") end
  u.power = clamp(cur, 0, u.maxPower)
  local ptoken = World.POWER_TOKENS[u.powerType] or "MANA"
  self:fireUnit("UNIT_POWER_UPDATE", token, ptoken)
  self:fireUnit("UNIT_POWER_FREQUENT", token, ptoken)
end

function World:kill(token)
  local u = assert(self:get(token))
  u.health, u.dead = 0, true
  self:fireUnit("UNIT_HEALTH", token)
  self:fireUnit("UNIT_FLAGS", token)
end

function World:ghost(token)
  local u = assert(self:get(token))
  u.dead, u.ghost, u.health = true, true, 1
  self:fireUnit("UNIT_HEALTH", token)
  self:fireUnit("UNIT_FLAGS", token)
end

function World:resurrect(token, health)
  local u = assert(self:get(token))
  u.dead, u.ghost = nil, nil
  u.health = health or math.floor(u.maxHealth / 2)
  self:fireUnit("UNIT_HEALTH", token)
  self:fireUnit("UNIT_FLAGS", token)
end

function World:setFlag(token, flag, value)
  local u = assert(self:get(token))
  u[flag] = value
  if flag == "afk" or flag == "dnd" then self:fireUnit("PLAYER_FLAGS_CHANGED", token)
  elseif flag == "connected" then self:fireUnit("UNIT_CONNECTION", token, value)
  elseif flag == "pvp" or flag == "ffa" then self:fireUnit("UNIT_FACTION", token)
  else self:fireUnit("UNIT_FLAGS", token) end
end

function World:setRange(token, inRange)
  local u = assert(self:get(token))
  u.inRange = inRange
  self:fireUnit("UNIT_IN_RANGE_UPDATE", token, inRange)
end

function World:setRaidTarget(token, index)
  local u = assert(self:get(token))
  u.raidTarget = index
  self.h:fire("RAID_TARGET_UPDATE")
end

function World:setThreat(token, mobToken, status, pct)
  local u = assert(self:get(token))
  local mob = mobToken and self:get(mobToken)
  u.threat[mob and mob.guid or "*"] = { status = status, pct = pct or 0 }
  u.threatStatus = status
  self:fireUnit("UNIT_THREAT_SITUATION_UPDATE", token)
  if mobToken then self:fireUnit("UNIT_THREAT_LIST_UPDATE", mobToken) end
end

-- Spawn/replace the player's target (a token or a spec for a new NPC); nil clears it.
function World:setTarget(spec, ownerToken)
  ownerToken = ownerToken or "player"
  local owner = assert(self:get(ownerToken))
  local u
  if type(spec) == "table" then u = self:addUnit(nil, spec)
  elseif type(spec) == "string" then u = self:get(spec) end
  owner.target = u and u.guid
  if ownerToken == "player" then
    self.tokens.target = u and u.guid
    self.h:fire("PLAYER_TARGET_CHANGED")
  end
  self.h:fire("UNIT_TARGET", ownerToken)
  return u
end

function World:setFocus(spec)
  local u
  if type(spec) == "table" then u = self:addUnit(nil, spec) elseif type(spec) == "string" then u = self:get(spec) end
  self.tokens.focus = u and u.guid
  self.h:fire("PLAYER_FOCUS_CHANGED")
  return u
end

function World:summonPet(spec, ownerToken)
  ownerToken = ownerToken or "player"
  local owner = assert(self:get(ownerToken))
  spec = spec or {}
  spec.isPet, spec.playerControlled = true, true
  spec.name = spec.name or "Wolf"
  spec.powerType = spec.powerType or 2
  local pet = self:addUnit(nil, spec)
  owner.pet = pet.guid
  local petToken = ownerToken == "player" and "pet" or ownerToken:gsub("^party(%d)", "partypet%1"):gsub("^raid(%d+)", "raidpet%1")
  self.tokens[petToken] = pet.guid
  self.h:fire("UNIT_PET", ownerToken)
  return pet, petToken
end

function World:dismissPet(ownerToken)
  ownerToken = ownerToken or "player"
  local owner = assert(self:get(ownerToken))
  for tok, guid in pairs(self.tokens) do if guid == owner.pet then self.tokens[tok] = nil end end
  owner.pet = nil
  self.h:fire("UNIT_PET", ownerToken)
end

---------------------------------------------------------------------------
-- Combat, instance, encounter, restrictions
---------------------------------------------------------------------------
local function fireRestriction(w, kind, active)
  local states = w.h.env.Enum and w.h.env.Enum.AddOnRestrictionState
  local typeEnum = w.h.env.Enum and w.h.env.Enum.AddOnRestrictionType
  local t = typeEnum and typeEnum[kind] or World.RESTRICTION[kind]
  local s = states and (active and states.Active or states.Inactive) or (active and 2 or 0)
  w.h:fire("ADDON_RESTRICTION_STATE_CHANGED", t, s)
end

function World:combat(on)
  on = on and true or false
  if on == self.inCombat then return end
  if on then
    fireRestriction(self, "Combat", true)
    self.inCombat = true
    self.h:fire("PLAYER_REGEN_DISABLED")
  else
    self.inCombat = false
    self.h:fire("PLAYER_REGEN_ENABLED")
    fireRestriction(self, "Combat", false)
  end
end

function World:instance(kind)
  self.instanceType = kind or "none"
  self.h:fire("ZONE_CHANGED_NEW_AREA")
  self.h:fire("PLAYER_ENTERING_WORLD", false, false)
  fireRestriction(self, "Map", self.instanceType ~= "none")
end

function World:encounter(on, id, name)
  if on == nil then on = true end
  self.inEncounter = on and true or false
  if on then
    fireRestriction(self, "Encounter", true)
    self.h:fire("ENCOUNTER_START", id or 1, name or "Boss", 1, 5)
  else
    self.h:fire("ENCOUNTER_END", id or 1, name or "Boss", 1, 5, 1)
    fireRestriction(self, "Encounter", false)
  end
end

function World:forceRestriction(kind, on)
  self.forced[kind] = on ~= false or nil
  fireRestriction(self, kind, on ~= false)
end

---------------------------------------------------------------------------
-- Auras and casts
---------------------------------------------------------------------------
local auraInstance = 0
function World:applyAura(token, aura)
  local u = assert(self:get(token))
  auraInstance = auraInstance + 1
  local a = {}
  for k, v in pairs(aura) do a[k] = v end
  a.auraInstanceID = auraInstance
  a.name = a.name or "Aura"
  a.spellId = a.spellId or 1000 + auraInstance
  a.icon = a.icon or 136000
  a.applications = a.applications or a.count or 0
  a.duration = a.duration or 0
  a.expirationTime = a.expirationTime or (a.duration > 0 and self.h.clock + a.duration or 0)
  a.isHelpful = a.isHelpful ~= false and not a.isHarmful
  a.isHarmful = not a.isHelpful
  a.sourceUnit = a.sourceUnit or "player"
  a.isFromPlayerOrPlayerPet = a.isFromPlayerOrPlayerPet
  if a.isFromPlayerOrPlayerPet == nil then a.isFromPlayerOrPlayerPet = (a.sourceUnit == "player" or a.sourceUnit == "pet") end
  u.auras[#u.auras + 1] = a
  self:fireUnit("UNIT_AURA", token, { addedAuras = { a }, isFullUpdate = false })
  return a
end

function World:removeAura(token, idOrName)
  local u = assert(self:get(token))
  for i, a in ipairs(u.auras) do
    if a.auraInstanceID == idOrName or a.name == idOrName or a.spellId == idOrName then
      table.remove(u.auras, i)
      self:fireUnit("UNIT_AURA", token, { removedAuraInstanceIDs = { a.auraInstanceID }, isFullUpdate = false })
      return a
    end
  end
end

function World:startCast(token, spec)
  local u = assert(self:get(token))
  spec = spec or {}
  local c = {
    name = spec.name or "Fireball", text = spec.text or spec.name or "Fireball", texture = spec.texture or 135812,
    startTime = (spec.startTime or self.h.clock) * 1000, castID = spec.castID or ("Cast-" .. tostring(self.h.clock)),
    notInterruptible = spec.notInterruptible or false, spellId = spec.spellId or 133, channel = spec.channel or false,
    isTradeSkill = spec.isTradeSkill or false,
  }
  c.endTime = c.startTime + (spec.duration or 2.5) * 1000
  u.casting = c
  self:fireUnit(c.channel and "UNIT_SPELLCAST_CHANNEL_START" or "UNIT_SPELLCAST_START", token, c.castID, c.spellId)
  return c
end

function World:stopCast(token, how)
  local u = assert(self:get(token))
  local c = u.casting
  u.casting = nil
  if not c then return end
  if how == "interrupt" then self:fireUnit("UNIT_SPELLCAST_INTERRUPTED", token, c.castID, c.spellId)
  elseif how == "fail" then self:fireUnit("UNIT_SPELLCAST_FAILED", token, c.castID, c.spellId)
  elseif c.channel then self:fireUnit("UNIT_SPELLCAST_CHANNEL_STOP", token, c.castID, c.spellId)
  else
    self:fireUnit("UNIT_SPELLCAST_SUCCEEDED", token, c.castID, c.spellId)
    self:fireUnit("UNIT_SPELLCAST_STOP", token, c.castID, c.spellId)
  end
end

function World:setComboPoints(n)
  self.comboPoints = n
  self.h:fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
  self.h:fire("UNIT_POWER_FREQUENT", "player", "COMBO_POINTS")
end

function World:shapeshift(form, powerType)
  local u = self:get("player")
  self.shapeshiftForm = form or 0
  if powerType then u.powerType = powerType end
  self.h:fire("UPDATE_SHAPESHIFT_FORM")
  self.h:fire("UNIT_DISPLAYPOWER", "player")
end

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------
local PARTY_NAMES = { "Alyss", "Borin", "Cyra", "Dorn", "Elwy", "Fenn", "Gale", "Hask" }
local CLASS_CYCLE = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "HUNTER", "PALADIN", "WARLOCK", "SHAMAN", "DRUID" }

local function clearGroupTokens(w)
  for tok in pairs(w.tokens) do
    if tok:match("^party") or tok:match("^raid") then w.tokens[tok] = nil end
  end
end

-- members: array of unit specs (the player is added automatically).
function World:setParty(members)
  clearGroupTokens(self)
  self.group = (#members > 0) and "party" or nil
  self.roster = { { guid = self.tokens.player, subgroup = 1 } }
  local player = self:get("player")
  player.leader = player.leader ~= false and #members > 0 or nil
  for i, spec in ipairs(members) do
    spec.isPlayer = true
    spec.name = spec.name or PARTY_NAMES[i]
    spec.class = spec.class or CLASS_CYCLE[i]
    local u = self:addUnit("party" .. i, spec)
    self.roster[#self.roster + 1] = { guid = u.guid, subgroup = 1 }
  end
  self.h:fire("GROUP_ROSTER_UPDATE")
end

-- n members total including the player; spec(i) may return overrides.
function World:setRaid(n, spec)
  clearGroupTokens(self)
  self.group = "raid"
  self.roster = {}
  local player = self:get("player")
  for i = 1, n do
    local u
    if i == 1 then
      u = player
      self.tokens["raid1"] = u.guid
    else
      local s = spec and spec(i) or {}
      s.isPlayer = true
      s.name = s.name or ("Raider" .. i)
      s.class = s.class or CLASS_CYCLE[(i - 1) % #CLASS_CYCLE + 1]
      u = self:addUnit("raid" .. i, s)
    end
    u.subgroup = u.subgroup or math.floor((i - 1) / 5) + 1
    self.roster[i] = { guid = u.guid, subgroup = u.subgroup }
  end
  -- party tokens point at the other members of the player's subgroup
  local p = 0
  for i = 2, n do
    local u = self.units[self.roster[i].guid]
    if u.subgroup == player.subgroup and p < 4 then p = p + 1; self.tokens["party" .. p] = u.guid end
  end
  self.h:fire("GROUP_ROSTER_UPDATE")
end

function World:leaveGroup()
  clearGroupTokens(self)
  self.group, self.roster = nil, nil
  self.h:fire("GROUP_ROSTER_UPDATE")
end

function World:numGroupMembers()
  if not self.group then return 0 end
  return #self.roster
end

---------------------------------------------------------------------------
-- Clock
---------------------------------------------------------------------------
function World:advance(seconds) return self.h:advance(seconds) end

return World
