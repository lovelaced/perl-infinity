-- What each page of the options window shows, in order. Only structure lives
-- here; every label, tooltip and choice name is in Locale/enUS.lua, keyed by
-- the setting's path.
--
-- Row fields:
--   type        header, text, checkbox, slider, dropdown, multi, color, button
--   path        setting path (Config)
--   key         copy key for rows without a path (headers, buttons)
--   parent      path of the switch this row depends on (grayed out when off)
--   parentNot   the row is grayed out when the parent has this value
--   shownIf     hide the row entirely unless this returns true
--   min/max/step/format    sliders ("percent", "plus", "seconds", or whole numbers)
--   choices     dropdown values (or a function returning { label, value } tables)
local _, ns = ...

local Pages = {}
ns.OptionPages = Pages

local L = ns.L

local function PlayerClassIs(...)
	local classes = { ... }
	return function()
		local _, class = UnitClass("player")
		for _, wanted in ipairs(classes) do
			if class == wanted then
				return true
			end
		end
		return false
	end
end

local function Header(key)
	return { type = "header", key = key }
end

local function Check(path, extra)
	local option = { type = "checkbox", path = path }
	for k, v in pairs(extra or {}) do
		option[k] = v
	end
	return option
end

local function Slider(path, min, max, step, format, extra)
	local option = { type = "slider", path = path, min = min, max = max, step = step, format = format }
	for k, v in pairs(extra or {}) do
		option[k] = v
	end
	return option
end

local function Drop(path, choices, extra)
	local option = { type = "dropdown", path = path, choices = choices }
	for k, v in pairs(extra or {}) do
		option[k] = v
	end
	return option
end

local function Color(path, extra)
	local option = { type = "color", path = path }
	for k, v in pairs(extra or {}) do
		option[k] = v
	end
	return option
end

local function Button(key, onClick, extra)
	local option = { type = "button", key = key, onClick = onClick }
	for k, v in pairs(extra or {}) do
		option[k] = v
	end
	return option
end

local function OpenEditMode()
	ns.Options:Toggle()
	ns.Movers:OpenEditMode()
end

local BAR_TEXT = { "none", "current", "currentMax", "missing", "missingMax" }

-- Buff and debuff rows, shared by frame pages. A page can word its show buffs
-- and show debuffs rows its own way by naming another set of labels.
local function AuraRows(section, labels)
	local auras = section .. ".auras"
	labels = labels or "auras"
	return {
		Header("HEADER_AURAS"),
		Check(auras .. ".buffs", { key = labels .. ".buffs" }),
		Drop(auras .. ".buffFilter", { "all", "mine", "castable" }, { key = "auras.buffFilter", parent = auras .. ".buffs" }),
		Check(auras .. ".debuffs", { key = labels .. ".debuffs" }),
		Drop(auras .. ".debuffFilter", { "all", "mine", "dispellable" }, { key = "auras.debuffFilter", parent = auras .. ".debuffs" }),
		Check(auras .. ".onTop", { key = "auras.onTop" }),
		Slider(auras .. ".buffSize", 12, 40, 1, nil, { key = "auras.buffSize", parent = auras .. ".buffs" }),
		Slider(auras .. ".debuffSize", 12, 48, 1, nil, { key = "auras.debuffSize", parent = auras .. ".debuffs" }),
		Slider(auras .. ".rows", 1, 6, 1, nil, { key = "auras.rows" }),
	}
end

-- The game's own displays and the icons on your frame are separate choices, so
-- you can have either, both or neither, for buffs and debuffs alike.
local function PlayerAuraRows()
	local rows = AuraRows("player", "player.auras")
	table.insert(rows, 2, Check("player.keepBlizzardBuffs"))
	table.insert(rows, 3, Check("player.keepBlizzardDebuffs"))
	-- After the buff filter, before the debuff switch.
	table.insert(rows, 6, Check("player.auras.weaponEnchants"))
	return rows
end

local function Append(list, more)
	for _, item in ipairs(more) do
		list[#list + 1] = item
	end
	return list
end

local function SizeRows(section)
	return {
		Header("HEADER_SIZE"),
		Slider(section .. ".scale", 0.5, 2, 0.05, "percent", { key = "frame.scale" }),
		Slider(section .. ".width", 0, 100, 5, "plus", { key = "frame.width" }),
	}
end

Pages.list = {
	{
		key = "general",
		group = "general",
		preview = "overview",
		sections = { "general", "range", "highlight", "auras", "castBars", "alerts" },
		rows = {
			Header("HEADER_START"),
			{ type = "text", key = "TEXT_START" },
			Button("editMode", OpenEditMode),
			Header("HEADER_MOUSE"),
			Check("general.mouseoverHighlight"),
			Drop("general.unitTooltips", { "always", "shift", "alt", "ctrl", "never" }),
			Check("general.unitTooltipsInCombat", { parent = "general.unitTooltips", parentNot = "never" }),
			Drop("general.auraTooltips", { "always", "never" }),
			Check("general.auraTooltipsInCombat", { parent = "general.auraTooltips", parentNot = "never" }),
			Check("general.fadeTooltips"),
			Header("HEADER_RANGE"),
			Check("range.enabled"),
			Drop("range.mode", { "auto", "yards40" }, { parent = "range.enabled" }),
			Slider("range.alpha", 0.1, 0.9, 0.05, "percent", { parent = "range.enabled" }),
			Drop("range.part", { "frame", "name", "bars" }, { parent = "range.enabled" }),
			Check("range.icon", { parent = "range.enabled" }),
			Header("HEADER_HIGHLIGHTS"),
			Drop("highlight.debuffs", { "off", "dispellable", "all" }),
			Drop("highlight.debuffStyle", { "border", "background", "both" }),
			Check("highlight.hots"),
			Check("highlight.hotBars"),
			Check("highlight.shields"),
			Check("highlight.healing"),
			Check("highlight.aggro"),
			Check("highlight.target"),
			Header("HEADER_AURAS"),
			Check("auras.markStealable"),
			Drop("auras.spirals", { "off", "mine", "all" }),
			Drop("auras.countdown", { "off", "mine", "all" }),
			Slider("auras.countdownStart", 3, 60, 1, "seconds", { parent = "auras.countdown", parentNot = "off" }),
			Header("HEADER_CAST"),
			Drop("castBars.time", { "hidden", "inside", "outside" }),
			Header("HEADER_STATUS"),
			Check("general.readyCheck"),
			Check("general.afk"),
			Check("general.feignDeath"),
			Check("general.targetSounds"),
			Header("HEADER_COMBAT"),
			Check("general.combatFlash"),
			Check("general.hitIndicators"),
			Header("HEADER_ALERTS"),
			Check("alerts.lowHealth"),
			Slider("alerts.lowHealthPercent", 5, 75, 5, "percentWhole", { parent = "alerts.lowHealth" }),
			Check("alerts.aggroWarning"),
			{ type = "text", key = "TEXT_BINDINGS" },
		},
	},
	{
		key = "appearance",
		group = "general",
		preview = "overview",
		sections = { "look" },
		rows = {
			Header("HEADER_FRAMES"),
			Slider("look.frameAlpha", 0.2, 1, 0.05, "percent"),
			Slider("look.textAlpha", 0.2, 1, 0.05, "percent"),
			Color("look.background"),
			Slider("look.backgroundAlpha", 0, 1, 0.05, "percent"),
			Color("look.border"),
			Drop("look.shading", { "off", "vertical", "horizontal" }),
			Color("look.shadingStart", { parent = "look.shading", parentNot = "off" }),
			Color("look.shadingEnd", { parent = "look.shading", parentNot = "off" }),
			Header("HEADER_BARS"),
			Drop("look.texture", function()
				local choices = {}
				for _, texture in ipairs(ns.Media.BarTextureChoices()) do
					choices[#choices + 1] = { label = texture.label, value = texture.key }
				end
				return choices
			end),
			Check("look.texturedBackground"),
			Check("look.thickHealth"),
			Check("look.smoothBars"),
			Check("look.invertBars"),
			Check("look.incomingHeals"),
			Color("look.incomingHealsColor", { parent = "look.incomingHeals" }),
			Check("look.absorbs"),
			Color("look.absorbsColor", { parent = "look.absorbs" }),
			Header("HEADER_HEALTH_COLOR"),
			Drop("look.healthColor", { "gradient", "class", "custom" }),
			Slider("look.classBrightness", 0.5, 1.5, 0.05, "percent", {
				shownIf = function()
					return ns.db.look.healthColor == "class"
				end,
			}),
			Color("look.healthFull", { shownIf = function() return ns.db.look.healthColor == "custom" end }),
			Color("look.healthLow", { shownIf = function() return ns.db.look.healthColor == "custom" end }),
			Header("HEADER_POWER_COLORS"),
			Color("look.mana"),
			Color("look.rage"),
			Color("look.energy"),
			Color("look.focus"),
			Header("HEADER_NAMES"),
			Check("look.classNames"),
			Check("look.centerNames"),
			Color("look.hostile"),
			Color("look.unfriendly"),
			Color("look.neutral"),
			Color("look.friendly"),
			Color("look.tapped"),
			Color("look.noReaction"),
			Header("HEADER_PORTRAITS"),
			Drop("look.portraitStyle", { "3d", "2d", "class" }),
			Check("look.level"),
			Check("look.classIcon"),
			Check("look.pvpIcon"),
			Check("look.roleIcons"),
			Drop("look.raidMarker", { "corner", "name" }),
		},
	},
	{
		key = "player",
		group = "frames",
		preview = "player",
		sections = { "player" },
		rows = Append(Append(Append({
			Check("player.enabled"),
		}, SizeRows("player")), {
			Header("HEADER_LAYOUT"),
			Check("player.portrait", { key = "frame.portrait" }),
			Check("player.tallPortrait", { parent = "player.portrait" }),
			Drop("player.groupNumber", { "hidden", "above", "name" }),
			Check("player.restAnimation"),
			Check("player.restGlow", { parent = "player.restAnimation" }),
			Header("HEADER_BARS"),
			Drop("player.barText", BAR_TEXT, { key = "frame.barText" }),
			Check("player.percent", { key = "frame.percent" }),
			Check("player.debuffHighlight"),
			Check("player.xpBar"),
			Check("player.xpRemaining", { parent = "player.xpBar" }),
			Check("player.repBar"),
			Check("player.druidMana", { shownIf = PlayerClassIs("DRUID") }),
			Check("player.totems", { shownIf = PlayerClassIs("SHAMAN") }),
			Header("HEADER_CAST"),
			Check("player.castBar", { key = "frame.castBar" }),
			Check("player.castLatency", { parent = "player.castBar" }),
			Check("player.keepBlizzardCastBar", { parent = "player.castBar" }),
		}), PlayerAuraRows()),
	},
	{
		key = "pet",
		group = "frames",
		preview = "pet",
		sections = { "pet" },
		rows = Append(Append(Append({
			Check("pet.enabled"),
		}, SizeRows("pet")), {
			Header("HEADER_LAYOUT"),
			Check("pet.portrait", { key = "frame.portrait" }),
			Check("pet.name"),
			Header("HEADER_BARS"),
			Drop("pet.barText", BAR_TEXT, { key = "frame.barText" }),
			Check("pet.percent", { key = "frame.percent" }),
			Check("pet.xpBar", { shownIf = PlayerClassIs("HUNTER") }),
			Drop("pet.happiness", { "always", "unhappy", "hidden" }, { shownIf = PlayerClassIs("HUNTER") }),
			Check("pet.happinessFlash", { parent = "pet.happiness", parentNot = "hidden", shownIf = PlayerClassIs("HUNTER") }),
			Header("HEADER_CAST"),
			Check("pet.castBar", { key = "frame.castBar" }),
		}), AuraRows("pet")),
	},
	{
		key = "target",
		group = "frames",
		preview = "target",
		sections = { "target" },
		rows = Append(Append(Append({
			Check("target.enabled"),
		}, SizeRows("target")), {
			Header("HEADER_LAYOUT"),
			Check("target.portrait", { key = "frame.portrait" }),
			Drop("target.elite", { "dragon", "text", "none" }, { key = "frame.elite" }),
			Check("target.creatureType", { key = "frame.creatureType" }),
			Drop("target.creatureTypePosition", { "below", "above" }, { key = "frame.creatureTypePosition", parent = "target.creatureType" }),
			{ type = "multi", path = "target.combo", choices = { "dots", "number", "fill" }, shownIf = PlayerClassIs("ROGUE", "DRUID") },
			Drop("target.comboPosition", { "above", "below", "left", "right" }, { shownIf = PlayerClassIs("ROGUE", "DRUID") }),
			Drop("target.threat", { "off", "gauge", "bar" }, { key = "frame.threat" }),
			Header("HEADER_BARS"),
			Drop("target.barText", BAR_TEXT, { key = "frame.barText" }),
			Check("target.percent", { key = "frame.percent" }),
			Check("target.power", { key = "frame.power" }),
			Drop("target.debuffHighlight", { "off", "friendly", "enemy", "both" }, { key = "frame.debuffHighlight" }),
			Header("HEADER_CAST"),
			Check("target.castBar", { key = "frame.castBar" }),
		}), AuraRows("target")),
	},
	{
		key = "small",
		group = "frames",
		preview = "small",
		sections = { "small" },
		rows = Append({
			Header("HEADER_SMALL_FRAMES"),
			Check("small.targettarget.enabled"),
			Slider("small.targettarget.scale", 0.5, 2, 0.05, "percent", { key = "frame.scale", parent = "small.targettarget.enabled" }),
			Check("small.targettargettarget.enabled"),
			Slider("small.targettargettarget.scale", 0.5, 2, 0.05, "percent", { key = "frame.scale", parent = "small.targettargettarget.enabled" }),
			Check("small.focustarget.enabled"),
			Slider("small.focustarget.scale", 0.5, 2, 0.05, "percent", { key = "frame.scale", parent = "small.focustarget.enabled" }),
			Check("small.pettarget.enabled"),
			Slider("small.pettarget.scale", 0.5, 2, 0.05, "percent", { key = "frame.scale", parent = "small.pettarget.enabled" }),
			Header("HEADER_SHARED"),
			Slider("small.width", 0, 100, 5, "plus", { key = "frame.width" }),
			Drop("small.barText", BAR_TEXT, { key = "frame.barText" }),
			Check("small.percent", { key = "frame.percent" }),
			Check("small.power", { key = "frame.power" }),
		}, AuraRows("small")),
	},
	{
		key = "focus",
		group = "frames",
		preview = "focus",
		sections = { "focus" },
		rows = Append(Append(Append({
			Check("focus.enabled"),
		}, SizeRows("focus")), {
			Header("HEADER_LAYOUT"),
			Check("focus.portrait", { key = "frame.portrait" }),
			Drop("focus.elite", { "dragon", "text", "none" }, { key = "frame.elite" }),
			Check("focus.creatureType", { key = "frame.creatureType" }),
			Drop("focus.creatureTypePosition", { "below", "above" }, { key = "frame.creatureTypePosition", parent = "focus.creatureType" }),
			Drop("focus.threat", { "off", "gauge", "bar" }, { key = "frame.threat" }),
			Header("HEADER_BARS"),
			Drop("focus.barText", BAR_TEXT, { key = "frame.barText" }),
			Check("focus.percent", { key = "frame.percent" }),
			Check("focus.power", { key = "frame.power" }),
			Drop("focus.debuffHighlight", { "off", "friendly", "enemy", "both" }, { key = "frame.debuffHighlight" }),
			Header("HEADER_CAST"),
			Check("focus.castBar", { key = "frame.castBar" }),
		}), AuraRows("focus")),
	},
	{
		key = "party",
		group = "groups",
		preview = "party",
		sections = { "party" },
		rows = Append(Append(Append({
			Check("party.enabled"),
			Check("party.showPlayer"),
			Drop("party.inRaid", { "keep", "hide", "smallRaid" }),
		}, SizeRows("party")), {
			Header("HEADER_LAYOUT"),
			Drop("party.direction", { "down", "up", "right", "left" }, { key = "frame.direction" }),
			Slider("party.spacing", 0, 60, 1, nil, { key = "frame.spacing" }),
			Check("party.fitIcons"),
			Check("party.mirror"),
			Check("party.portrait", { key = "frame.portrait" }),
			Check("party.names"),
			Header("HEADER_BARS"),
			Drop("party.barText", BAR_TEXT, { key = "frame.barText" }),
			Check("party.percent", { key = "frame.percent" }),
			Check("party.castBar", { key = "frame.castBar" }),
			Header("HEADER_PARTY_TARGETS"),
			Check("party.targets"),
			Slider("party.targetWidth", 66, 200, 2, nil, { parent = "party.targets" }),
			Header("HEADER_PARTY_PETS"),
			Check("party.pets"),
			Slider("party.petScale", 0.5, 1.5, 0.05, "percent", { parent = "party.pets" }),
		}), AuraRows("party")),
	},
	{
		key = "raid",
		group = "groups",
		preview = "raid",
		sections = { "raid" },
		rows = Append({
			Check("raid.enabled"),
			Check("raid.inParty"),
			Check("raid.hideInBattlegrounds"),
		}, Append(SizeRows("raid"), {
			Header("HEADER_ARRANGE"),
			Drop("raid.sortBy", { "group", "class", "role" }),
			Check("raid.alphabetical"),
			Drop("raid.direction", { "down", "up", "right", "left" }, { key = "frame.direction" }),
			Slider("raid.spacing", -5, 20, 1, nil, { key = "frame.spacing" }),
			Slider("raid.groupGap", 0, 40, 1),
			Check("raid.titles"),
			{ type = "multi", path = "raid.groups", choices = function()
				local choices = {}
				for i = 1, 8 do
					choices[i] = { label = L.GROUP_N:format(i) }
				end
				return choices
			end },
			{ type = "multi", path = "raid.classes", choices = function()
				local choices = {}
				for token in ns.db.raid.classOrder:gmatch("[^,]+") do
					choices[#choices + 1] = { label = ns.Classes.Name(token) }
				end
				return choices
			end },
			Header("HEADER_BARS"),
			Drop("raid.healthText", { "none", "percent", "current", "missing" }),
			Check("raid.mana"),
			Check("raid.manaPercent", { parent = "raid.mana" }),
			Header("HEADER_RAID_ICONS"),
			Drop("raid.icons", { "none", "buffs", "debuffs" }),
			Check("raid.iconsFilter", { parent = "raid.icons", parentNot = "none" }),
			Drop("raid.iconPosition", { "inside", "right", "below" }, { parent = "raid.icons", parentNot = "none" }),
			Check("raid.bossDebuff"),
			Slider("raid.bossDebuffAlpha", 0.2, 1, 0.05, "percent", { parent = "raid.bossDebuff" }),
			Header("HEADER_RAID_PETS"),
			Check("raid.pets"),
			Check("raid.petsAttached", { parent = "raid.pets" }),
		})),
	},
	{
		key = "tools",
		group = "groups",
		preview = "tools",
		sections = { "tanks", "healers", "tools" },
		rows = {
			Header("HEADER_TANKS"),
			{ type = "text", key = "TEXT_TANKS" },
			Check("tanks.enabled"),
			Drop("tanks.source", { "mainTanks", "mainTanksOnly", "role" }, { parent = "tanks.enabled" }),
			Slider("tanks.max", 1, 10, 1, nil, { parent = "tanks.enabled" }),
			Check("tanks.showTargetTarget", { parent = "tanks.enabled" }),
			Check("tanks.numbers", { parent = "tanks.enabled" }),
			Check("tanks.growUp", { parent = "tanks.enabled" }),
			Drop("tanks.healthText", { "percent", "missing", "missingMax" }, { parent = "tanks.enabled" }),
			Slider("tanks.width", 50, 125, 5, nil, { parent = "tanks.enabled" }),
			Slider("tanks.height", 27, 50, 1, nil, { parent = "tanks.enabled" }),
			Slider("tanks.alpha", 0.2, 1, 0.05, "percent", { parent = "tanks.enabled" }),
			Header("HEADER_HEALERS"),
			Check("healers.enabled"),
			{ type = "multi", path = "healers.classes", parent = "healers.enabled", choices = function()
				local choices = {}
				for _, token in ipairs(ns.Classes.healerChoices) do
					choices[#choices + 1] = { label = ns.Classes.Name(token) }
				end
				return choices
			end },
			Check("healers.targets", { parent = "healers.enabled" }),
			Check("healers.growUp", { parent = "healers.enabled" }),
			Slider("healers.width", 50, 150, 5, nil, { parent = "healers.enabled" }),
			Slider("healers.height", 32, 55, 1, nil, { parent = "healers.enabled" }),
			Slider("healers.alpha", 0.2, 1, 0.05, "percent", { parent = "healers.enabled" }),
			Header("HEADER_LAYOUTS"),
			{ type = "text", key = "TEXT_LAYOUTS" },
			{
				type = "dropdown",
				key = "tools.layout",
				get = function()
					return ns.RaidLayouts and ns.RaidLayouts.selected
				end,
				set = function(value)
					ns.RaidLayouts.selected = value
				end,
				choices = function()
					return ns.RaidLayouts and ns.RaidLayouts:Choices() or {}
				end,
			},
			Button("layoutSave", function()
				ns.RaidLayouts:AskSave()
			end),
			Button("layoutLoad", function()
				ns.RaidLayouts:Load(ns.RaidLayouts.selected)
			end),
			Button("layoutDelete", function()
				ns.RaidLayouts:Delete(ns.RaidLayouts.selected)
			end),
			Header("HEADER_CHECKS"),
			Button("buffCheck", function()
				ns.BuffCheck:Run()
			end),
			Check("tools.buffHelper"),
			Drop("tools.buffHelperSort", { "group", "class", "none" }, { parent = "tools.buffHelper" }),
			Check("tools.buffHelperVisibleOnly", { parent = "tools.buffHelper" }),
			Button("raidNames", function()
				ns.RaidNames:Show()
			end),
		},
	},
	{
		key = "profiles",
		group = "profiles",
		preview = nil,
		rows = {
			Header("HEADER_PROFILE"),
			{
				type = "dropdown",
				key = "profiles.active",
				get = function()
					return ns.Profiles:Active()
				end,
				set = function(name)
					ns.Profiles:Use(name)
				end,
				choices = function()
					local choices = {}
					for _, name in ipairs(ns.Profiles:List()) do
						choices[#choices + 1] = { label = name, value = name }
					end
					return choices
				end,
			},
			Button("profileNew", function()
				ns.ProfileDialogs:New()
			end),
			{
				type = "dropdown",
				key = "profiles.copyFrom",
				get = function()
					return nil
				end,
				set = function(name)
					ns.ProfileDialogs:Copy(name)
				end,
				choices = function()
					local choices = {}
					for _, name in ipairs(ns.Profiles:List()) do
						if name ~= ns.Profiles:Active() then
							choices[#choices + 1] = { label = name, value = name }
						end
					end
					return choices
				end,
			},
			Button("profileRename", function()
				ns.ProfileDialogs:Rename()
			end),
			Button("profileDelete", function()
				ns.ProfileDialogs:Delete()
			end),
			Button("profileReset", function()
				ns.ProfileDialogs:Reset()
			end),
			Header("HEADER_NEW_CHARACTERS"),
			{
				type = "dropdown",
				key = "profiles.newCharacters",
				get = function()
					return ns.Config:DB().newCharacterProfile
				end,
				set = function(name)
					ns.Config:DB().newCharacterProfile = name
				end,
				choices = function()
					local choices = {}
					for _, name in ipairs(ns.Profiles:List()) do
						choices[#choices + 1] = { label = name, value = name }
					end
					return choices
				end,
			},
			Header("HEADER_SHARE"),
			Button("profileExport", function()
				ns.ProfileDialogs:Export()
			end),
			Button("profileImport", function()
				ns.ProfileDialogs:Import()
			end),
			Header("HEADER_POSITIONS"),
			{ type = "text", key = "TEXT_POSITIONS" },
			Button("positionsReset", function()
				ns.ProfileDialogs:ResetPositions()
			end),
		},
	},
}

Pages.byKey = {}
for _, page in ipairs(Pages.list) do
	Pages.byKey[page.key] = page
end
