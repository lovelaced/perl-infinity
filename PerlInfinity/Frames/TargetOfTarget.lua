-- The four small frames: target of target, target of target of target,
-- focus target and pet target. They share one look (ns.db.small) and each
-- has its own on/off switch and size.
--
-- These units have no events of their own; their frames are refreshed when
-- the parent changes target and polled for health while they're visible.
local _, ns = ...

local Frames = ns.Frames
local L = ns.L

local ELEMENTS = { "Health", "Power", "Name", "Level", "Auras", "Range", "Status", "RaidIcon" }

local function LayoutOptions(_, conf)
	return {
		width = 136 + conf.width,
		percent = conf.percent,
		power = conf.power,
		thick = false,
		extras = 0,
	}
end

local function Define(kind, unit, refresh, sampleName)
	Frames:Define(kind, {
		unit = unit,
		layout = "Small",
		movable = true,
		hostile = true,
		conf = function()
			return ns.db.small
		end,
		enabled = function()
			return ns.db.small[kind].enabled
		end,
		scale = function()
			return ns.db.small[kind].scale
		end,
		layoutOptions = LayoutOptions,
		elements = ELEMENTS,
		refreshEvents = refresh,
		combatFeedback = false,
		sample = function()
			return {
				name = sampleName,
				level = 60,
				reaction = "friendly",
				health = 3100, maxHealth = 4400,
				power = 1200, maxPower = 3000, powerToken = "MANA",
				auras = { { spell = 1243 } },
			}
		end,
	})
end

Define("targettarget", "targettarget", { "PLAYER_TARGET_CHANGED" }, L.SAMPLE_TOT)
Define("targettargettarget", "targettargettarget", { "PLAYER_TARGET_CHANGED" }, L.SAMPLE_TOTOT)
Define("focustarget", "focustarget", { "PLAYER_FOCUS_CHANGED" }, L.SAMPLE_FOCUS_TARGET)
Define("pettarget", "pettarget", { "UNIT_PET" }, L.SAMPLE_PET_TARGET)
