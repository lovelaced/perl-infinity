-- The small settings popup Edit Mode shows when you click a Perl Infinity frame.
-- It uses the same words and controls as Blizzard's own Edit Mode popups
-- (Frame size, Buffs on top...) and reads and writes the same settings as the
-- options window, so the two always agree. "More options" opens the options
-- window on that frame's page.
local _, ns = ...

local QuickSettings = {}
ns.QuickSettings = QuickSettings

local Config = ns.Config
local L = ns.L
local LEM = ns.LibEditMode

local function Percent(value)
	return ("%d%%"):format(math.floor(value * 100 + 0.5))
end

local function Slider(name, path, low, high, step, formatter)
	return {
		kind = LEM.SettingType.Slider,
		name = name,
		default = Config:GetDefault(path),
		minValue = low,
		maxValue = high,
		valueStep = step,
		formatter = formatter,
		get = function()
			return Config:Get(path)
		end,
		set = function(_, value)
			Config:Set(path, value)
		end,
	}
end

local function Checkbox(name, path)
	return {
		kind = LEM.SettingType.Checkbox,
		name = name,
		default = Config:GetDefault(path),
		get = function()
			return Config:Get(path)
		end,
		set = function(_, value)
			Config:Set(path, value)
		end,
	}
end

local function Dropdown(name, path, choices)
	local values = {}
	for i, choice in ipairs(choices) do
		values[i] = { text = choice[2], value = choice[1] }
	end
	return {
		kind = LEM.SettingType.Dropdown,
		name = name,
		default = Config:GetDefault(path),
		values = values,
		get = function()
			return Config:Get(path)
		end,
		set = function(_, value)
			Config:Set(path, value)
		end,
	}
end

local DIRECTIONS = {
	{ "down", L.DIRECTION_DOWN }, { "up", L.DIRECTION_UP }, { "right", L.DIRECTION_RIGHT }, { "left", L.DIRECTION_LEFT },
}

local function UnitSettings(section)
	return {
		Slider(L.EM_FRAME_SIZE, section .. ".scale", 0.5, 2, 0.05, Percent),
		Slider(L.EM_FRAME_WIDTH, section .. ".width", 0, 100, 5),
		Checkbox(L.EM_SHOW_PORTRAIT, section .. ".portrait"),
		Checkbox(L.EM_BUFFS_ON_TOP, section .. ".auras.onTop"),
	}
end

local SETTINGS = {
	player = function()
		return {
			Slider(L.EM_FRAME_SIZE, "player.scale", 0.5, 2, 0.05, Percent),
			Slider(L.EM_FRAME_WIDTH, "player.width", 0, 100, 5),
			Checkbox(L.EM_SHOW_PORTRAIT, "player.portrait"),
		}
	end,
	pet = function()
		return UnitSettings("pet")
	end,
	target = function()
		return UnitSettings("target")
	end,
	focus = function()
		return UnitSettings("focus")
	end,
	targettarget = function()
		return { Slider(L.EM_FRAME_SIZE, "small.targettarget.scale", 0.5, 2, 0.05, Percent) }
	end,
	targettargettarget = function()
		return { Slider(L.EM_FRAME_SIZE, "small.targettargettarget.scale", 0.5, 2, 0.05, Percent) }
	end,
	focustarget = function()
		return { Slider(L.EM_FRAME_SIZE, "small.focustarget.scale", 0.5, 2, 0.05, Percent) }
	end,
	pettarget = function()
		return { Slider(L.EM_FRAME_SIZE, "small.pettarget.scale", 0.5, 2, 0.05, Percent) }
	end,
	party = function()
		return {
			Slider(L.EM_FRAME_SIZE, "party.scale", 0.5, 2, 0.05, Percent),
			Slider(L.EM_FRAME_WIDTH, "party.width", 0, 100, 5),
			Dropdown(L.EM_DIRECTION, "party.direction", DIRECTIONS),
			Slider(L.EM_SPACING, "party.spacing", 0, 60, 1),
			Checkbox(L.EM_FIT_ICONS, "party.fitIcons"),
			Checkbox(L.EM_SHOW_PORTRAIT, "party.portrait"),
			Checkbox(L.EM_MIRROR, "party.mirror"),
		}
	end,
	partytarget = function()
		return { Slider(L.EM_FRAME_WIDTH, "party.targetWidth", 66, 200, 2) }
	end,
	partypet = function()
		return { Slider(L.EM_FRAME_SIZE, "party.petScale", 0.5, 1.5, 0.05, Percent) }
	end,
	raid = function()
		return {
			Slider(L.EM_FRAME_SIZE, "raid.scale", 0.5, 2, 0.05, Percent),
			Slider(L.EM_FRAME_WIDTH, "raid.width", 0, 100, 5),
			Dropdown(L.EM_SORT_BY, "raid.sortBy", {
				{ "group", L.SORT_GROUP }, { "class", L.SORT_CLASS }, { "role", L.SORT_ROLE },
			}),
			Dropdown(L.EM_DIRECTION, "raid.direction", DIRECTIONS),
			Slider(L.EM_SPACING, "raid.spacing", -5, 20, 1),
		}
	end,
	tanks = function()
		return {
			Slider(L.EM_ROWS, "tanks.max", 1, 10, 1),
			Checkbox(L.EM_GROW_UP, "tanks.growUp"),
		}
	end,
	healers = function()
		return {
			Checkbox(L.EM_SHOW_TARGETS, "healers.targets"),
			Checkbox(L.EM_GROW_UP, "healers.growUp"),
		}
	end,
}

-- Which options page "More options" opens for each frame.
local PAGES = {
	targettarget = "small", targettargettarget = "small", focustarget = "small", pettarget = "small",
	partytarget = "party", partypet = "party", raidpets = "raid", tanks = "tools", healers = "tools", layouts = "tools", aggro = "general",
}

function QuickSettings:Attach(mover)
	local key = mover.key
	local build = SETTINGS[key]
	if build then
		LEM:AddFrameSettings(mover, build())
	end
	LEM:AddFrameSettingsButtons(mover, {
		{
			text = L.EM_MORE_OPTIONS,
			click = function()
				ns.Options:Open(PAGES[key] or key)
			end,
		},
	})
end

-- Keeps open Edit Mode popups in step with changes made elsewhere.
function QuickSettings:Refresh()
	for _, key in ipairs({ "player", "pet", "target", "focus", "party", "raid" }) do
		local mover = ns.Movers:Get(key)
		if mover.registered and LEM.RefreshFrameSettings then
			LEM:RefreshFrameSettings(mover)
		end
	end
end
