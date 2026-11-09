-- Your own frame and your pet's.
local _, ns = ...

local Frames = ns.Frames
local L = ns.L

local function PlayerExtras(frame, conf)
	local slots, count = {}, 0
	local _, class = UnitClass("player")
	if class == "DRUID" and conf.druidMana then
		count = count + 1
		slots.druidMana = count
	end
	if conf.xpBar then
		count = count + 1
		slots.xp = count
	end
	if conf.repBar then
		count = count + 1
		slots.rep = count
	end
	frame.extraSlots = slots
	return count
end

Frames:Define("player", {
	unit = "player",
	layout = "PortraitLeft",
	movable = true,
	conf = function()
		return ns.db.player
	end,
	enabled = function()
		return ns.db.player.enabled
	end,
	scale = function()
		return ns.db.player.scale
	end,
	layoutOptions = function(frame, conf)
		return {
			width = 160 + conf.width,
			portrait = conf.portrait,
			tallPortrait = conf.tallPortrait,
			percent = conf.percent,
			power = true,
			thick = ns.db.look.thickHealth,
			extras = PlayerExtras(frame, conf),
		}
	end,
	elements = {
		"Health", "HealPrediction", "Power", "DruidMana", "Experience", "Name", "Level", "Portrait",
		"Castbar", "Status", "Leader", "RaidIcon", "PvP", "StateIcon", "ReadyCheck", "GroupNumber",
		-- Auras comes after Totems: icons below your frame make room for the totem row.
		"CombatFeedback", "Totems", "Auras", "DispelHighlight", "LowHealth",
	},
	refreshEvents = { "PLAYER_ENTERING_WORLD" },
	sample = function()
		local _, class = UnitClass("player")
		local powerToken = select(2, UnitPowerType("player"))
		return {
			unit = "player",
			name = ns.Secret.UnitFullName("player"),
			class = class,
			level = UnitLevel("player"),
			health = 3412, maxHealth = 4120,
			power = 1650, maxPower = 2400, powerToken = powerToken,
			incoming = 300,
			cast = L.SAMPLE_CAST,
			group = 2,
			leader = true,
			resting = true,
			auras = {
				{ spell = 1126, mine = true },
				{ spell = 1243 },
				{ spell = 8122, harmful = true },
				{ spell = 8679, enchant = true },
			},
		}
	end,
})

local function PetExtras(frame, conf)
	frame.extraSlots = conf.xpBar and { xp = 1 } or {}
	return conf.xpBar and 1 or 0
end

Frames:Define("pet", {
	unit = "pet",
	layout = "PortraitLeft",
	movable = true,
	conf = function()
		return ns.db.pet
	end,
	enabled = function()
		return ns.db.pet.enabled
	end,
	scale = function()
		return ns.db.pet.scale
	end,
	layoutOptions = function(frame, conf)
		return {
			width = 110 + conf.width,
			portrait = conf.portrait,
			portraitSize = 50,
			percent = conf.percent,
			power = true,
			thick = ns.db.look.thickHealth,
			extras = PetExtras(frame, conf),
		}
	end,
	elements = {
		"Health", "HealPrediction", "Power", "Experience", "Name", "Level", "Portrait", "Castbar",
		"Auras", "Status", "RaidIcon", "PetHappiness", "CombatFeedback",
	},
	refreshEvents = { "UNIT_PET", "PLAYER_ENTERING_WORLD" },
	sample = function()
		return {
			name = L.SAMPLE_PET,
			level = UnitLevel("player"),
			reaction = "friendly",
			health = 1250, maxHealth = 1600,
			power = 70, maxPower = 100, powerToken = "FOCUS",
			happiness = 2,
			icon = 132203,
			auras = {
				{ spell = 136, mine = true },
			},
		}
	end,
})
