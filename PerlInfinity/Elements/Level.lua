-- Level box, class icon, and (on target and focus) the marks for elites,
-- rares and bosses, plus the creature type. None of these values are secret.
local _, ns = ...

local Media, Classes, Box = ns.Media, ns.Classes, ns.Box
local L = ns.L

local UnitLevel, UnitClassification, UnitIsPlayer, UnitClass, UnitCreatureType =
	UnitLevel, UnitClassification, UnitIsPlayer, UnitClass, UnitCreatureType

local Level = ns.Element("Level", {
	unitEvents = { "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED", "UNIT_NAME_UPDATE" },
	events = { "PLAYER_LEVEL_UP" },
})

local ELITE = { worldboss = true, elite = true, rareelite = true }

local GOLD = { r = 1, g = 0.82, b = 0 }
local SILVER = { r = 1, g = 1, b = 1 }
local ICE = { r = 0.55, g = 0.85, b = 1 }
local BOSS_RED = { r = 1, g = 0.35, b = 0.25 }

-- How each kind of enemy is marked. Elites get a gold dragon and gold edges.
-- Rares are easy to walk past, so they also get a label in every style and
-- an icy glow that pulses around the frame.
local MARKS = {
	elite = { label = L.CLASS_ELITE, art = Media.ELITE, tint = GOLD, edge = GOLD },
	worldboss = { label = L.CLASS_BOSS, art = Media.ELITE, tint = GOLD, edge = BOSS_RED, alwaysLabel = true },
	rare = { label = L.CLASS_RARE, art = Media.RARE, tint = SILVER, edge = ICE, alwaysLabel = true, pulse = true },
	rareelite = { label = L.CLASS_RARE_ELITE, art = Media.ELITE, tint = SILVER, edge = ICE, alwaysLabel = true, pulse = true },
}

-- Boxes whose edges take the mark's color.
local EDGED = { "NameBox", "StatsBox", "PortraitBox", "LevelBox", "TypeBox", "ComboBox" }

local DRAGON_SIZE = 128
-- The dragon art is grey; a second copy added on top brings the tint up
-- from dull brass to a bright gold or silver.
local SHINE = 0.8
local RARE_PULSE = 0.6 -- seconds from bright to dim
local TAB_PADDING = 16

function Level.Enabled(frame)
	return frame.LevelBox ~= nil
end

local function CreateMarks(frame)
	local content = frame.Content

	local holder = CreateFrame("Frame", nil, content)
	holder:SetAllPoints()
	Box.Raise(holder, content, Box.LEVEL.DRAGON)
	local dragon = holder:CreateTexture(nil, "ARTWORK")
	dragon:SetSize(DRAGON_SIZE, DRAGON_SIZE)
	local shine = holder:CreateTexture(nil, "OVERLAY")
	shine:SetBlendMode("ADD")
	shine:SetAlpha(SHINE)
	shine:SetAllPoints(dragon)
	holder:Hide()
	frame.Dragon, frame.DragonArt, frame.DragonShine = holder, dragon, shine

	-- A small tab above the name: "Rare", "Elite", "Boss".
	local tab = Box.Create(content)
	Box.Raise(tab, content, Box.LEVEL.FRONT)
	tab:SetHeight(18)
	local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER", 0, 1)
	tab.Text = text
	tab:Hide()
	frame.MarkTab = tab

	frame.MarkGlow = Box.Glow(content, content)

	local typeBox = Box.Create(content)
	Box.Raise(typeBox, content, Box.LEVEL.FRONT)
	typeBox:SetSize(68, 22)
	local typeText = typeBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	typeText:SetPoint("CENTER", 0, 1)
	typeText:SetWordWrap(false)
	typeText:SetWidth(64)
	typeBox.Text = typeText
	frame.TypeBox = typeBox
end

function Level.Create(frame)
	local icon = frame.Content:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(Classes.ICON_TEXTURE)
	frame.ClassIcon = icon
	if frame.spec.eliteMarker then
		CreateMarks(frame)
	end
end

local function ConfigureMarks(frame, conf)
	local portrait = frame.PortraitBox
	local hasPortrait = portrait ~= nil and portrait:IsShown()
	local anchor = hasPortrait and portrait or frame.NameBox

	-- Head over the portrait's top edge, tail under its bottom, wing out
	-- past its right side and below the level box.
	frame.DragonArt:ClearAllPoints()
	frame.DragonArt:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 37, 27)
	frame.MarkTab:ClearAllPoints()
	frame.MarkTab:SetPoint("BOTTOMLEFT", frame.NameBox, "TOPLEFT", 8, -3)
	-- Below: under the portrait, or with no portrait under the bars, never
	-- on them. Above: over the end of the name, clear of the combo points
	-- above the portrait and the Elite or Rare tag at the name's start.
	frame.TypeBox:ClearAllPoints()
	if conf.creatureTypePosition == "above" then
		frame.TypeBox:SetPoint("BOTTOMRIGHT", frame.NameBox, "TOPRIGHT", -4, -2)
	else
		frame.TypeBox:SetPoint("TOPRIGHT", hasPortrait and portrait or frame.StatsBox, "BOTTOMRIGHT", 0, 2)
	end
	frame.showCreatureType = conf.creatureType
	if not conf.creatureType then
		frame.TypeBox:Hide()
	end

	-- With no portrait there's nothing for the dragon to wrap, so the label
	-- stands in for it.
	local style = conf.elite
	if style == "dragon" and not hasPortrait then
		style = "text"
	end
	frame.eliteStyle = style
	frame.mark = false -- draw the mark again on the next update
end

function Level.Configure(frame, conf)
	local look = ns.db.look
	local rects = frame.rects
	frame.LevelText:SetShown(look.level)
	frame.LevelBox:SetShown(look.level and rects.level ~= nil)

	local icon = frame.ClassIcon
	icon:ClearAllPoints()
	if rects.class and look.classIcon then
		icon:SetPoint("TOPLEFT", frame.Content, "TOPLEFT", rects.class.x, rects.class.y)
		icon:SetSize(rects.class.w, rects.class.h)
		frame.showClassIcon = true
	else
		frame.showClassIcon = false
		icon:Hide()
	end

	if frame.spec.eliteMarker then
		ConfigureMarks(frame, conf)
	end
end

local function SetEdges(frame, color)
	for _, key in ipairs(EDGED) do
		local box = frame[key]
		if box then
			Box.SetBorderColor(box, color)
		end
	end
end

local function ShowMark(frame, classification, isPlayer)
	local style = frame.eliteStyle
	local mark = not isPlayer and style ~= "none" and MARKS[classification] or nil
	if mark == frame.mark then
		return
	end
	frame.mark = mark
	SetEdges(frame, mark and mark.edge)

	if mark and style == "dragon" then
		local tint = mark.tint
		frame.DragonArt:SetTexture(mark.art)
		frame.DragonArt:SetVertexColor(tint.r, tint.g, tint.b)
		frame.DragonShine:SetTexture(mark.art)
		frame.DragonShine:SetVertexColor(tint.r, tint.g, tint.b)
		frame.Dragon:Show()
	else
		frame.Dragon:Hide()
	end

	local tab = frame.MarkTab
	if mark and (style == "text" or mark.alwaysLabel) then
		local edge = mark.edge
		tab.Text:SetText(mark.label)
		tab.Text:SetTextColor(edge.r, edge.g, edge.b)
		tab:SetWidth(tab.Text:GetStringWidth() + TAB_PADDING)
		Box.SetBorderColor(tab, edge)
		tab:Show()
	else
		tab:Hide()
	end

	if mark and mark.pulse then
		frame.MarkGlow:Start(mark.edge, RARE_PULSE)
	else
		frame.MarkGlow:Stop()
	end
end

local function ShowLevel(frame, level, classification, isPlayer, classToken)
	local text = frame.LevelText
	if level and level > 0 then
		local plus = (not isPlayer and ELITE[classification]) and "+" or ""
		text:SetText(level .. plus)
		local color = GetCreatureDifficultyColor(level)
		text:SetTextColor(color.r, color.g, color.b)
	else
		text:SetText("??")
		text:SetTextColor(1, 0, 0)
	end

	local icon = frame.ClassIcon
	if frame.showClassIcon and isPlayer and classToken then
		local coords = Classes.IconCoords(classToken)
		if coords then
			icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
			icon:Show()
		else
			icon:Hide()
		end
	else
		icon:Hide()
	end

	if frame.spec.eliteMarker then
		ShowMark(frame, classification, isPlayer)
	end
end

-- A rare's glow stops when the frame hides; showing the frame updates it,
-- which starts the glow again if it's still wanted.
function Level.Shown(frame, shown)
	if not shown and frame.MarkGlow then
		frame.MarkGlow:Stop()
	end
end

-- Players have no creature type, and some creatures don't either, so the box
-- only shows when there's something to put in it. A secret type can't be
-- checked, so it shows as given.
local function ShowCreatureType(frame, isPlayer, creatureType)
	local box = frame.TypeBox
	if not box then
		return
	end
	if not frame.showCreatureType or isPlayer then
		box:Hide()
		return
	end
	if issecretvalue(creatureType) then
		box.Text:SetText(creatureType)
		box:Show()
		return
	end
	box.Text:SetText(creatureType or "")
	box:SetShown(creatureType ~= nil and creatureType ~= "")
end

function Level.Update(frame, unit)
	local isPlayer = UnitIsPlayer(unit)
	local classToken
	if isPlayer then
		classToken = select(2, UnitClass(unit))
		if ns.Secret.Is(classToken) then
			classToken = nil
		end
	end
	ShowLevel(frame, UnitLevel(unit), UnitClassification(unit), isPlayer, classToken)
	local creatureType
	if not isPlayer then
		creatureType = UnitCreatureType(unit)
	end
	ShowCreatureType(frame, isPlayer, creatureType)
end

function Level.Preview(frame, sample)
	ShowLevel(frame, sample.level, sample.classification or "normal", sample.class ~= nil, sample.class)
	ShowCreatureType(frame, sample.class ~= nil, sample.creatureType)
end
