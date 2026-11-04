-- Every setting's default, in one place. Profiles only store what differs
-- from these. The options window (Options/Pages.lua) describes how each one
-- is shown; this file only holds values.
--
-- Colors are "AARRGGBB" hex strings so they save and export cleanly.
local _, ns = ...

local Util = ns.Util

-- Settings shared by every buff and debuff row.
local function AuraDefaults(overrides)
	local auras = {
		buffs = true,
		buffFilter = "all", -- all, mine, castable
		debuffs = true,
		debuffFilter = "all", -- all, mine, dispellable
		onTop = false,
		buffSize = 22,
		debuffSize = 29,
		rows = 3,
	}
	return Util.DeepMerge(auras, overrides or {})
end

-- Settings shared by player, pet, target, focus and party frames.
local function UnitDefaults(overrides)
	local unit = {
		enabled = true,
		scale = 0.8,
		width = 0,
		portrait = true,
		barText = "currentMax", -- none, current, currentMax, missing, missingMax
		percent = true,
		power = true,
		castBar = true,
		auras = AuraDefaults(),
	}
	return Util.DeepMerge(unit, overrides or {})
end

-- Settings for the small frames: target of target and friends.
local function SmallDefaults(overrides)
	return Util.DeepMerge({ enabled = true, scale = 0.7 }, overrides or {})
end

ns.Defaults = {
	general = {
		mouseoverHighlight = true,
		unitTooltips = "always", -- always, shift, alt, ctrl, never
		unitTooltipsInCombat = true,
		auraTooltips = "always",
		auraTooltipsInCombat = true,
		fadeTooltips = false,
		readyCheck = true,
		afk = true,
		feignDeath = false,
		targetSounds = true,
		combatFlash = true,
		hitIndicators = true,
		pollInterval = 0.2,
	},

	range = {
		enabled = true,
		mode = "auto", -- auto, yards40
		alpha = 0.5,
		part = "frame", -- frame, name, bars
		icon = false,
	},

	highlight = {
		debuffs = "dispellable", -- off, dispellable, all
		debuffStyle = "both", -- border, background, both
		hots = true,
		hotBars = false,
		shields = true,
		healing = false,
		aggro = true,
		target = false,
	},

	auras = {
		bigOwn = true,
		markStealable = true,
		spirals = "mine", -- off, mine, all
		countdown = "mine", -- off, mine, all
		countdownStart = 20,
	},

	castBars = {
		time = "hidden", -- hidden, inside, outside
	},

	alerts = {
		lowHealth = true,
		lowHealthPercent = 30,
		aggroWarning = true,
	},

	look = {
		frameAlpha = 1,
		textAlpha = 1,
		background = "ff000000",
		backgroundAlpha = 0.85,
		border = "ff808080",
		shading = "vertical", -- off, vertical, horizontal
		shadingStart = "ff404040",
		shadingEnd = "ff1a1a1a",
		texture = "perl",
		texturedBackground = true,
		thickHealth = true,
		smoothBars = false,
		invertBars = false,
		incomingHeals = true,
		incomingHealsColor = "ff00ffff",
		absorbs = true,
		absorbsColor = "ff2454b3",
		healthColor = "gradient", -- gradient, class, custom
		classBrightness = 1,
		healthFull = "ff00ff00",
		healthLow = "ffff0000",
		mana = "ff0000ff",
		rage = "ffff0000",
		energy = "ffffff00",
		focus = "ffff8040",
		happiness = "ff00ff96",
		classNames = true,
		hostile = "ffff0000",
		unfriendly = "ffff8000",
		neutral = "ffffff00",
		friendly = "ff00ff00",
		tapped = "ff808080",
		noReaction = "ffcccccc",
		portraitStyle = "3d", -- 3d, 2d, class
		level = true,
		classIcon = true,
		pvpIcon = true,
		roleIcons = true,
		raidMarker = "corner", -- corner, name
	},

	player = UnitDefaults({
		scale = 0.9,
		tallPortrait = false,
		groupNumber = "above", -- hidden, above, name
		xpBar = false,
		xpRemaining = false,
		repBar = false,
		druidMana = true,
		castLatency = false,
		keepBlizzardCastBar = false,
		totems = true,
	}),

	pet = UnitDefaults({
		scale = 0.7,
		name = true,
		happiness = "unhappy", -- always, unhappy, hidden
		happinessFlash = true,
		xpBar = false,
		auras = AuraDefaults({ buffSize = 18, debuffSize = 18 }),
	}),

	target = UnitDefaults({
		elite = "text", -- text, dragon, none
		creatureType = true,
		reactionBox = false,
		combo = 7, -- bit 1 dots, bit 2 number, bit 3 fill
		comboPosition = "above", -- above, below, left, right
		threat = "off", -- off, gauge, bar
		debuffHighlight = "off", -- off, friendly, enemy, both
	}),

	focus = UnitDefaults({
		elite = "text",
		creatureType = true,
		reactionBox = false,
		threat = "off",
		debuffHighlight = "off",
	}),

	-- The four small frames share their look; each has its own switch and size.
	small = {
		targettarget = SmallDefaults(),
		targettargettarget = SmallDefaults({ enabled = false }),
		focustarget = SmallDefaults(),
		pettarget = SmallDefaults(),
		width = 0,
		barText = "currentMax",
		percent = true,
		power = true,
		auras = AuraDefaults(),
	},

	party = UnitDefaults({
		showPlayer = false,
		inRaid = "keep", -- keep, hide, smallRaid
		direction = "down", -- down, up, right, left
		spacing = 23,
		mirror = false,
		names = true,
		targets = true,
		targetWidth = 120,
		targetHealth = true,
		pets = true,
		petScale = 0.7,
		petAuras = true,
		debuffPosition = "below", -- below, side
		auras = AuraDefaults({ debuffSize = 32, rows = 2 }),
	}),

	raid = {
		enabled = true,
		inParty = false,
		hideInBattlegrounds = false,
		scale = 0.8,
		width = 0,
		sortBy = "group", -- group, class, role
		classOrder = "WARRIOR,ROGUE,HUNTER,MAGE,WARLOCK,PRIEST,DRUID,SHAMAN,PALADIN",
		alphabetical = false,
		direction = "down", -- down, up, right, left
		spacing = 0,
		groupGap = 2,
		titles = true,
		groups = 255, -- bits 1-8
		classes = 511, -- bits 1-9, in classOrder order
		separateGroups = false,
		healthText = "percent", -- none, percent, current, missing
		mana = true,
		manaPercent = true,
		icons = "debuffs", -- none, buffs, debuffs
		iconsFilter = false, -- only what I can cast or dispel
		iconPosition = "inside", -- inside, right, below
		bossDebuff = false,
		bossDebuffAlpha = 0.5,
		pets = true,
		petsAttached = true,
	},

	tanks = {
		enabled = false,
		source = "mainTanks", -- mainTanks, mainTanksOnly, role
		max = 10,
		showTargetTarget = true,
		numbers = false,
		growUp = false,
		healthText = "percent", -- percent, missing, missingMax
		width = 100,
		height = 26,
		alpha = 0.8,
	},

	healers = {
		enabled = false,
		-- Rows show mana as their main number (not shown as settings).
		healthText = "none",
		mana = true,
		manaPercent = true,
		classes = 15, -- bits: priest, druid, shaman, paladin, mage, warlock, hunter
		targets = true,
		growUp = false,
		width = 120,
		height = 12,
		alpha = 1,
	},

	tools = {
		buffHelper = true,
		buffHelperSort = "group", -- group, class, none
		buffHelperVisibleOnly = true,
	},
}

-- Where each movable frame starts in a fresh Edit Mode layout. Positions are
-- stored per Edit Mode layout in PerlInfinityDB.positions, outside profiles.
ns.DefaultPositions = {
	player = { point = "TOPLEFT", x = 12, y = -12 },
	pet = { point = "TOPLEFT", x = 60, y = -100 },
	pettarget = { point = "TOPLEFT", x = 190, y = -100 },
	target = { point = "TOPLEFT", x = 271, y = -12 },
	targettarget = { point = "TOPLEFT", x = 590, y = -12 },
	targettargettarget = { point = "TOPLEFT", x = 720, y = -12 },
	focus = { point = "TOPLEFT", x = 271, y = -200 },
	focustarget = { point = "TOPLEFT", x = 590, y = -200 },
	party = { point = "TOPLEFT", x = 12, y = -170 },
	raid = { point = "TOPLEFT", x = 12, y = -465 },
	raidpets = { point = "TOPLEFT", x = 700, y = -465 },
	tanks = { point = "RIGHT", x = -260, y = 120 },
	healers = { point = "RIGHT", x = -260, y = -60 },
	aggro = { point = "TOP", x = 0, y = -120 },
	totems = { point = "TOPLEFT", x = 60, y = -86 },
}
