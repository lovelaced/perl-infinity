-- Combo points on the target frame, for rogues and druids. On Forever combo
-- points belong to the target, as in Classic: GetComboPoints("player",
-- "target"), refreshed when you switch targets (COMBO_TARGET_CHANGED).
--
-- The count may be secret, so each dot is a tiny StatusBar with a range of
-- (i - 1) to i: it's full exactly when you have at least i points, without
-- comparing anything in Lua.
--
-- Like Z-Perl, nothing shows at zero points or on a target you can't attack.
-- When the count is secret we can't tell zero apart, so it stays shown.
local _, ns = ...

local Media, Util = ns.Media, ns.Util

local GetComboPoints, UnitPowerMax = GetComboPoints, UnitPowerMax
local UnitCanAttack, UnitIsDeadOrGhost = UnitCanAttack, UnitIsDeadOrGhost
local COMBO = Enum.PowerType.ComboPoints

local ComboPoints = ns.Element("ComboPoints", {
	unitEvents = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER" },
	eventUnit = "player",
	events = { "COMBO_TARGET_CHANGED" },
})

local MAX = 5
local DOT = 9

function ComboPoints.Enabled(frame, conf)
	if frame.kind ~= "target" or not conf.combo or conf.combo == 0 then
		return false
	end
	local _, class = UnitClass("player")
	return class == "ROGUE" or class == "DRUID"
end

local function Dot(parent)
	local dot = CreateFrame("StatusBar", nil, parent)
	dot:SetSize(DOT, DOT)
	dot:SetStatusBarTexture(Media.WHITE)
	dot:SetStatusBarColor(1, 0.82, 0)
	local background = dot:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("TOPLEFT", -1, 1)
	background:SetPoint("BOTTOMRIGHT", 1, -1)
	background:SetColorTexture(0, 0, 0, 0.8)
	return dot
end

function ComboPoints.Create(frame)
	local holder = CreateFrame("Frame", nil, frame.Content)
	holder:SetFrameLevel(frame.Content:GetFrameLevel() + 6)
	frame.ComboDots = {}
	for i = 1, MAX do
		local dot = Dot(holder)
		dot:SetMinMaxValues(i - 1, i)
		frame.ComboDots[i] = dot
	end
	frame.ComboHolder = holder

	-- Beside the level box, so it also sits in front of the elite dragon's wing.
	local box = ns.Box.Create(frame.Content)
	ns.Box.Raise(box, frame.Content, ns.Box.LEVEL.FRONT)
	box:SetSize(26, 22)
	local number = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	number:SetPoint("CENTER", 0, 1)
	box.Text = number
	frame.ComboBox = box

	local fill = CreateFrame("StatusBar", nil, frame.NameBox)
	fill:SetPoint("TOPLEFT", 4, -4)
	fill:SetPoint("BOTTOMRIGHT", -4, 4)
	fill:SetStatusBarTexture(Media.BarTexture())
	fill:SetStatusBarColor(1, 0.5, 0, 0.45)
	fill:SetFrameLevel(frame.NameBox:GetFrameLevel())
	fill:SetMinMaxValues(0, MAX)
	frame.ComboFill = fill
end

function ComboPoints.Configure(frame, conf)
	local mask = conf.combo
	local dots = Util.HasBit(mask, 1)
	frame.ComboHolder:SetShown(dots)
	frame.ComboBox:SetShown(Util.HasBit(mask, 2))
	frame.ComboFill:SetShown(Util.HasBit(mask, 3))

	local anchor = (frame.PortraitBox and frame.PortraitBox:IsShown()) and frame.PortraitBox or frame.StatsBox
	local position = conf.comboPosition
	local vertical = position == "left" or position == "right"
	for i, dot in ipairs(frame.ComboDots) do
		dot:ClearAllPoints()
		local offset = (i - (MAX + 1) / 2) * (DOT + 3)
		if position == "below" then
			dot:SetPoint("TOP", anchor, "BOTTOM", offset, 2)
		elseif position == "left" then
			dot:SetPoint("RIGHT", anchor, "LEFT", 2, -offset)
		elseif position == "right" then
			dot:SetPoint("LEFT", anchor, "RIGHT", -2, -offset)
		else
			dot:SetPoint("BOTTOM", anchor, "TOP", offset, -2)
		end
		dot:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
	end

	frame.ComboBox:ClearAllPoints()
	if frame.LevelBox then
		frame.ComboBox:SetPoint("TOPLEFT", frame.LevelBox, "TOPRIGHT", -2, 0)
	end
end

function ComboPoints.Disable(frame)
	frame.ComboHolder:Hide()
	frame.ComboBox:Hide()
	frame.ComboFill:Hide()
end

local function Show(frame, points, maxPoints, visible)
	for _, dot in ipairs(frame.ComboDots) do
		dot:SetValue(points)
	end
	frame.ComboBox.Text:SetFormattedText("%d", points)
	frame.ComboFill:SetMinMaxValues(0, maxPoints)
	frame.ComboFill:SetValue(points)
	local alpha = visible and 1 or 0
	frame.ComboHolder:SetAlpha(alpha)
	frame.ComboBox:SetAlpha(alpha)
	frame.ComboFill:SetAlpha(alpha)
end

function ComboPoints.Update(frame)
	local maxPoints = UnitPowerMax("player", COMBO)
	if not maxPoints or (not issecretvalue(maxPoints) and maxPoints <= 0) then
		maxPoints = MAX
	end
	local points = GetComboPoints("player", "target") or 0
	local visible = UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")
	if visible and not issecretvalue(points) then
		visible = points > 0
	end
	Show(frame, points, maxPoints, visible)
end

function ComboPoints.Preview(frame, sample)
	local points = sample.combo or 0
	Show(frame, points, MAX, points > 0)
end
