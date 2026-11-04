-- Your target and focus: the mirrored X-Perl layout with the portrait on the
-- right, the elite dragon, creature type, and combo points (target only).
local _, ns = ...

local Frames, Media = ns.Frames, ns.Media
local L = ns.L

local ELEMENTS = {
	"Health", "HealPrediction", "Power", "Name", "Level", "Portrait", "Castbar", "Auras",
	"DispelHighlight", "Range", "Threat", "ComboPoints", "Status", "Leader", "RaidIcon", "PvP",
	"CombatFeedback",
}

local function LayoutOptions(_, conf)
	return {
		width = 160 + conf.width,
		portrait = conf.portrait,
		percent = conf.percent,
		power = conf.power,
		thick = ns.db.look.thickHealth,
		extras = 0,
	}
end

local function Sample()
	return {
		name = L.SAMPLE_TARGET,
		level = 11,
		classification = "elite",
		creatureType = L.SAMPLE_CREATURE_TYPE,
		reaction = "hostile",
		health = 640, maxHealth = 1000,
		power = 420, maxPower = 600, powerToken = "MANA",
		icon = 134169,
		combo = 3,
		threat = 70,
		raidIcon = 8,
		cast = L.SAMPLE_ENEMY_CAST,
		auras = {
			{ spell = 589, harmful = true, mine = true },
			{ spell = 772, harmful = true, mine = true },
			{ spell = 11597, harmful = true },
			{ spell = 25646, harmful = true },
			{ spell = 6673 },
			{ spell = 1243, stealable = true },
		},
	}
end

-- X-Perl marks your target's frame with a cyan glow when it's also your
-- focus, and the focus frame with a little eye.
local function DecorateFocus(frame)
	local eye = frame.NameBox:CreateTexture(nil, "OVERLAY")
	eye:SetTexture(Media.EYE)
	eye:SetSize(24, 12)
	eye:SetPoint("RIGHT", frame.NameBox, "LEFT", 4, 0)
end

Frames:Define("target", {
	unit = "target",
	layout = "PortraitRight",
	movable = true,
	eliteMarker = true,
	rangeHand = true,
	hostile = true,
	conf = function()
		return ns.db.target
	end,
	enabled = function()
		return ns.db.target.enabled
	end,
	scale = function()
		return ns.db.target.scale
	end,
	layoutOptions = LayoutOptions,
	elements = ELEMENTS,
	refreshEvents = { "PLAYER_TARGET_CHANGED" },
	sample = Sample,
})

Frames:Define("focus", {
	unit = "focus",
	layout = "PortraitRight",
	movable = true,
	eliteMarker = true,
	rangeHand = true,
	hostile = true,
	conf = function()
		return ns.db.focus
	end,
	enabled = function()
		return ns.db.focus.enabled
	end,
	scale = function()
		return ns.db.focus.scale
	end,
	layoutOptions = LayoutOptions,
	elements = ELEMENTS,
	refreshEvents = { "PLAYER_FOCUS_CHANGED" },
	Decorate = DecorateFocus,
	sample = function()
		local sample = Sample()
		sample.name = L.SAMPLE_FOCUS
		sample.level = 12
		sample.classification = "rareelite"
		sample.combo = nil
		sample.raidIcon = 1
		return sample
	end,
})

-- Target sounds, which disappear along with Blizzard's target frame.
local Sounds = ns:NewModule("TargetSounds")

local function OnTargetChanged(_, event)
	local unit = event == "PLAYER_FOCUS_CHANGED" and "focus" or "target"
	-- Blizzard's frame plays these itself while it's still around.
	if not ns.db.general.targetSounds or not ns.BlizzardHide:IsHidden(unit) then
		return
	end
	if UnitExists(unit) then
		if C_PlayerInteractionManager and C_PlayerInteractionManager.IsReplacingUnit and C_PlayerInteractionManager.IsReplacingUnit() then
			return
		end
		if UnitIsEnemy(unit, "player") then
			PlaySound(SOUNDKIT.IG_CREATURE_AGGRO_SELECT)
		elseif UnitIsFriend("player", unit) then
			PlaySound(SOUNDKIT.IG_CHARACTER_NPC_SELECT)
		else
			PlaySound(SOUNDKIT.IG_CREATURE_NEUTRAL_SELECT)
		end
	elseif not IsTargetLoose() then
		PlaySound(SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT)
	end
end

function Sounds:Login()
	ns.Events:On("PLAYER_TARGET_CHANGED", self, OnTargetChanged)
	ns.Events:On("PLAYER_FOCUS_CHANGED", self, OnTargetChanged)
end
