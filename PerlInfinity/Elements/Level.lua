-- Level box, class icon, and (on target and focus) the elite marker and
-- creature type. None of these values are secret.
local _, ns = ...

local Media, Classes = ns.Media, ns.Classes
local L = ns.L

local UnitLevel, UnitClassification, UnitIsPlayer, UnitClass, UnitCreatureType =
	UnitLevel, UnitClassification, UnitIsPlayer, UnitClass, UnitCreatureType

local Level = ns.Element("Level", {
	unitEvents = { "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED", "UNIT_NAME_UPDATE" },
	events = { "PLAYER_LEVEL_UP" },
})

local ELITE = { worldboss = true, elite = true, rareelite = true }
local CLASSIFICATION_TEXT = {
	worldboss = L.CLASS_BOSS,
	elite = L.CLASS_ELITE,
	rareelite = L.CLASS_RARE_ELITE,
	rare = L.CLASS_RARE,
}

function Level.Enabled(frame)
	return frame.LevelBox ~= nil
end

function Level.Create(frame)
	local icon = frame.Content:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(Classes.ICON_TEXTURE)
	frame.ClassIcon = icon

	if frame.spec.eliteMarker then
		-- The X-Perl dragon wraps the portrait for elites, bosses and rares.
		local dragon = frame.Content:CreateTexture(nil, "OVERLAY")
		dragon:SetSize(128, 128)
		frame.EliteDragon = dragon

		local classification = frame.Content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		frame.ClassificationText = classification

		local typeBox = ns.Box.Create(frame.Content)
		typeBox:SetSize(68, 22)
		local typeText = typeBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		typeText:SetPoint("CENTER", 0, 1)
		typeText:SetWordWrap(false)
		typeText:SetWidth(64)
		typeBox.Text = typeText
		frame.TypeBox = typeBox
	end
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

	if frame.EliteDragon then
		local portrait = frame.PortraitBox
		local anchor = (portrait and portrait:IsShown()) and portrait or frame.NameBox
		frame.EliteDragon:ClearAllPoints()
		frame.EliteDragon:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 37, 13)
		frame.ClassificationText:ClearAllPoints()
		frame.ClassificationText:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 5)
		frame.eliteStyle = conf.elite
		frame.TypeBox:ClearAllPoints()
		frame.TypeBox:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 2)
		frame.TypeBox:SetShown(conf.creatureType)
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

	if frame.EliteDragon then
		local dragon = frame.EliteDragon
		local style = frame.eliteStyle
		local label = not isPlayer and CLASSIFICATION_TEXT[classification]
		if style == "dragon" and label then
			dragon:SetTexture(classification == "rare" and Media.RARE or Media.ELITE)
			if classification == "rareelite" then
				dragon:SetVertexColor(1, 1, 1)
			else
				dragon:SetVertexColor(1, 0.82, 0)
			end
			dragon:Show()
		else
			dragon:Hide()
		end
		frame.ClassificationText:SetText(style == "text" and label or "")
	end
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
	if frame.TypeBox then
		frame.TypeBox.Text:SetText(isPlayer and "" or (UnitCreatureType(unit) or ""))
	end
end

function Level.Preview(frame, sample)
	ShowLevel(frame, sample.level, sample.classification or "normal", sample.class ~= nil, sample.class)
	if frame.TypeBox then
		frame.TypeBox.Text:SetText(sample.creatureType or "")
	end
end
