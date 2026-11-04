-- Read-only checks of what the game hands addons on this build: which values
-- are secret, which APIs, templates, atlases and spells exist. Used by the
-- self-test and by the passive census (first fight in each kind of place).
-- Results are short strings, never the values themselves.
local _, ns = ...

local Probes = {}
ns.Probes = Probes

local issecretvalue = issecretvalue

-- "secret", "nil", "plain:<type>", or "error:<message>".
local function Classify(ok, ...)
	if not ok then
		local message = ...
		if issecretvalue(message) then
			return "error:<secret>"
		end
		return "error:" .. tostring(message):sub(1, 120)
	end
	local value = ...
	if value == nil then
		return "nil"
	end
	if issecretvalue(value) then
		return "secret"
	end
	return "plain:" .. type(value)
end

function Probes.Run(fn, ...)
	return Classify(pcall(fn, ...))
end

local MATRIX = {
	{ "UnitHealth", function(u) return UnitHealth(u) end },
	{ "UnitHealthMax", function(u) return UnitHealthMax(u) end },
	{ "UnitHealthPercent", function(u) return UnitHealthPercent(u, true) end },
	{ "UnitHealthMissing", function(u) return UnitHealthMissing(u, true) end },
	{ "UnitPower", function(u) return UnitPower(u) end },
	{ "UnitPowerMax", function(u) return UnitPowerMax(u) end },
	{ "UnitPowerType", function(u) return UnitPowerType(u) end },
	{ "UnitName", function(u) return UnitName(u) end },
	{ "UnitClass", function(u) return select(2, UnitClass(u)) end },
	{ "UnitGUID", function(u) return UnitGUID(u) end },
	{ "UnitLevel", function(u) return UnitLevel(u) end },
	{ "UnitIsAFK", function(u) return UnitIsAFK(u) end },
	{ "UnitIsPVP", function(u) return UnitIsPVP(u) end },
	{ "UnitIsDeadOrGhost", function(u) return UnitIsDeadOrGhost(u) end },
	{ "UnitInRange", function(u) return UnitInRange(u) end },
	{ "UnitIsGroupLeader", function(u) return UnitIsGroupLeader(u) end },
	{ "UnitGroupRolesAssigned", function(u) return UnitGroupRolesAssigned(u) end },
	{ "GetRaidTargetIndex", function(u) return GetRaidTargetIndex(u) end },
	{ "UnitThreatSituation", function(u) return UnitThreatSituation("player", u) end },
	{ "UnitCastingInfo", function(u) return UnitCastingInfo(u) end },
	{ "UnitIsUnit.target", function(u) return UnitIsUnit("target", u) end },
	{ "UnitIsCharmed", function(u) return UnitIsCharmed(u) end },
	{ "UnitGetIncomingHeals", function(u) return UnitGetIncomingHeals(u) end },
	{ "UnitGetTotalAbsorbs", function(u) return UnitGetTotalAbsorbs(u) end },
	{ "GetReadyCheckStatus", function(u) return GetReadyCheckStatus(u) end },
	{ "UnitHasIncomingResurrection", function(u) return UnitHasIncomingResurrection(u) end },
	{ "AuraByIndex", function(u) return C_UnitAuras.GetAuraDataByIndex(u, 1, "HELPFUL") end },
	{ "ShouldIdentityBeSecret", function(u) return C_Secrets.ShouldUnitIdentityBeSecret(u) end },
}

local UNITS = { "player", "target", "targettarget", "pet", "focus", "party1", "raid1" }

local GLOBAL = {
	{ "HasSecretRestrictions", function() return C_Secrets.HasSecretRestrictions() end },
	{ "ShouldAurasBeSecret", function() return C_Secrets.ShouldAurasBeSecret() end },
	{ "GetComboPoints", function() return GetComboPoints("player", "target") end },
	{ "ComboSecrecy", function() return C_Secrets.GetPowerTypeSecrecy(Enum.PowerType.ComboPoints) end },
	{ "ManaSecrecy", function() return C_Secrets.GetPowerTypeSecrecy(Enum.PowerType.Mana) end },
	{ "EnergySecrecy", function() return C_Secrets.GetPowerTypeSecrecy(Enum.PowerType.Energy) end },
	{ "RageSecrecy", function() return C_Secrets.GetPowerTypeSecrecy(Enum.PowerType.Rage) end },
	{ "PetHappiness", function() return C_PetInfo.GetPetHappiness() end },
	{ "TotemInfo", function() return GetTotemInfo(1) end },
	{ "LootMethod", function() return C_PartyInfo.GetLootMethod() end },
	{ "InChatLockdown", function() return C_ChatInfo.InChatMessagingLockdown() end },
}

-- Secrecy of each API for each unit that exists right now.
function Probes.Matrix()
	local matrix = {}
	for _, unit in ipairs(UNITS) do
		if UnitExists(unit) then
			local row = {}
			for _, probe in ipairs(MATRIX) do
				row[probe[1]] = Probes.Run(probe[2], unit)
			end
			matrix[unit] = row
		end
	end
	local global = {}
	for _, probe in ipairs(GLOBAL) do
		global[probe[1]] = Probes.Run(probe[2])
	end
	matrix.global = global
	return matrix
end

---------------------------------------------------------------------------
-- Existence checks
---------------------------------------------------------------------------

local GLOBALS = {
	"UnitHealthPercent", "UnitHealthMissing", "UnitPowerPercent", "CreateUnitHealPredictionCalculator",
	"UnitGetDetailedHealPrediction", "UnitCastingDuration", "UnitChannelDuration", "GetComboPoints",
	"GetRaidRosterInfo", "GetReadyCheckStatus", "UnitHasIncomingResurrection", "GetPetExperience",
	"GetTotemInfo", "GetTotemDuration", "SetRaidSubgroup", "SwapRaidSubgroup", "GetPartyAssignment",
	"GetNumGroupMembers", "GetNumSubgroupMembers", "IsInRaid", "IsInGroup", "UnitInRange",
	"RegisterUnitWatch", "RegisterAttributeDriver", "AbbreviateNumbers", "BreakUpLargeNumbers",
	"DebuffTypeColor", "CLASS_ICON_TCOORDS", "RAID_CLASS_COLORS", "PowerBarColor", "FACTION_BAR_COLORS",
	"READY_CHECK_READY_TEXTURE", "PET_HAPPINESS1", "GetCreatureDifficultyColor", "IsTargetLoose",
	"GetThreatStatusColor", "UnitDetailedThreatSituation", "SetPortraitTexture", "ScrollUtil",
	"MinimalSliderWithSteppersMixin", "TooltipDataProcessor", "StaticPopup_Show", "ColorPickerFrame",
	"EditModeManagerFrame", "AddonCompartmentFrame", "Settings", "SettingsPanel",
}

local NAMESPACED = {
	{ "C_UnitAuras", "GetAuraDataByIndex" }, { "C_CurveUtil", "CreateColorCurve" },
	{ "C_CurveUtil", "EvaluateColorFromBoolean" }, { "C_Secrets", "HasSecretRestrictions" },
	{ "C_Spell", "IsSpellInRange" }, { "C_Spell", "GetSpellName" }, { "C_SpellBook", "IsSpellKnown" },
	{ "C_PetInfo", "GetPetHappiness" }, { "C_PartyInfo", "GetLootMethod" },
	{ "C_IncomingSummon", "HasIncomingSummon" }, { "C_Reputation", "GetWatchedFactionData" },
	{ "C_DurationUtil", "CreateDurationTextBinding" }, { "C_StringUtil", "CreateSecondsFormatter" },
	{ "C_EncodingUtil", "SerializeCBOR" }, { "C_AddOnProfiler", "GetAddOnMetric" },
	{ "C_RestrictedActions", "IsAddOnRestrictionActive" }, { "C_ClassColor", "GetClassColor" },
}

local TEMPLATES = {
	"CustomAuraContainerTemplate", "SecureGroupHeaderTemplate", "SecureGroupPetHeaderTemplate",
	"SecureUnitButtonTemplate", "SecureActionButtonTemplate", "SettingsFrameTemplate",
	"SettingsCheckboxTemplate", "MinimalSliderWithSteppersTemplate", "SettingsDropdownWithButtonsTemplate",
	"WowStyle2DropdownTemplate", "ColorSwatchTemplate", "SearchBoxTemplate", "InsetFrameTemplate",
	"UIPanelButtonTemplate", "CooldownFrameTemplate", "MinimalScrollBar", "BackdropTemplate",
	"EditModeSystemSelectionTemplate", "PerlInfinityUnitButtonTemplate",
}

local ATLASES = {
	"Options_List_Active", "Options_List_Hover", "Options_CategoryHeader_1", "UI-PetMad", "UI-PetNeutral",
	"UI-PetHappiness", "nameplates-InterruptShield", "Raid-Icon-SummonPending", "checkbox-minimal",
}

local EVENTS = {
	"COMBO_TARGET_CHANGED", "UNIT_HAPPINESS", "UNIT_IN_RANGE_UPDATE", "INCOMING_SUMMON_CHANGED",
	"INCOMING_RESURRECT_CHANGED", "UNIT_PET_EXPERIENCE", "SPELL_RANGE_CHECK_UPDATE",
	"ADDON_RESTRICTION_STATE_CHANGED", "PLAYER_TOTEM_UPDATE", "UNIT_HEAL_PREDICTION",
}

function Probes.Manifest()
	local missing = {}
	for _, name in ipairs(GLOBALS) do
		if _G[name] == nil then
			missing[#missing + 1] = "global:" .. name
		end
	end
	for _, entry in ipairs(NAMESPACED) do
		local space = _G[entry[1]]
		if not space or space[entry[2]] == nil then
			missing[#missing + 1] = "api:" .. entry[1] .. "." .. entry[2]
		end
	end
	for _, name in ipairs(TEMPLATES) do
		if not C_XMLUtil.GetTemplateInfo(name) then
			missing[#missing + 1] = "template:" .. name
		end
	end
	for _, name in ipairs(ATLASES) do
		if not C_Texture.GetAtlasInfo(name) then
			missing[#missing + 1] = "atlas:" .. name
		end
	end
	for _, name in ipairs(EVENTS) do
		if not C_EventUtils.IsEventValid(name) then
			missing[#missing + 1] = "event:" .. name
		end
	end
	for _, id in ipairs(ns.Spells.All()) do
		if not C_Spell.DoesSpellExist(id) then
			missing[#missing + 1] = "spell:" .. id
		end
	end
	return missing
end
