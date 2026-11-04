-- Your threat on your target or focus: X-Perl's needle gauge over the
-- portrait, or a thin bar over the name. Threat between you and your target
-- is usually readable; when the game keeps the exact numbers secret (some
-- boss fights) the gauge shows the color only.
local _, ns = ...

local Media = ns.Media

local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local issecretvalue = issecretvalue

local Threat = ns.Element("Threat", {
	unitEvents = { "UNIT_THREAT_LIST_UPDATE" },
	events = { "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_REGEN_ENABLED" },
})

-- The needle swings across the top half of the gauge.
local NEEDLE_LEFT, NEEDLE_RIGHT = math.rad(90), math.rad(-90)

function Threat.Enabled(frame, conf)
	return conf.threat ~= nil and conf.threat ~= "off"
end

function Threat.Create(frame)
	local holder = CreateFrame("Frame", nil, frame.Content)
	holder:SetFrameLevel(frame.Content:GetFrameLevel() + 8)
	frame.ThreatHolder = holder

	local gauge = holder:CreateTexture(nil, "ARTWORK")
	gauge:SetTexture(Media.GAUGE)
	gauge:SetSize(56, 28)
	gauge:SetTexCoord(0, 1, 0, 0.5)
	frame.ThreatGauge = gauge

	local needle = holder:CreateTexture(nil, "OVERLAY")
	needle:SetTexture(Media.PATH .. "GaugeCircleNeedle")
	needle:SetSize(56, 56)
	needle:SetPoint("CENTER", gauge, "BOTTOM", 0, 0)
	frame.ThreatNeedle = needle

	local bar = CreateFrame("StatusBar", nil, holder)
	bar:SetStatusBarTexture(Media.WHITE)
	bar:SetMinMaxValues(0, 100)
	frame.ThreatBar = bar

	local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.ThreatText = text
end

function Threat.Configure(frame, conf)
	frame.threatMode = conf.threat
	local gauge, bar, text = frame.ThreatGauge, frame.ThreatBar, frame.ThreatText
	gauge:ClearAllPoints()
	bar:ClearAllPoints()
	text:ClearAllPoints()
	local anchor = (frame.PortraitBox and frame.PortraitBox:IsShown()) and frame.PortraitBox or frame.NameBox
	if conf.threat == "gauge" then
		gauge:SetPoint("BOTTOM", anchor, "TOP", 0, -6)
		text:SetPoint("BOTTOM", gauge, "BOTTOM", 0, 2)
		gauge:Show()
		frame.ThreatNeedle:Show()
		bar:Hide()
	else
		bar:SetPoint("BOTTOMLEFT", frame.NameBox, "TOPLEFT", 4, -3)
		bar:SetPoint("BOTTOMRIGHT", frame.NameBox, "TOPRIGHT", -4, -3)
		bar:SetHeight(3)
		text:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 1)
		bar:Show()
		gauge:Hide()
		frame.ThreatNeedle:Hide()
	end
	frame.ThreatHolder:Show()
end

function Threat.Disable(frame)
	frame.ThreatHolder:Hide()
end

local function Show(frame, status, percent)
	if not status then
		frame.ThreatHolder:Hide()
		return
	end
	frame.ThreatHolder:Show()
	local r, g, b = GetThreatStatusColor(status)
	frame.ThreatBar:SetStatusBarColor(r, g, b)
	frame.ThreatText:SetFormattedText("%.0f%%", percent or 0)
	frame.ThreatBar:SetValue(percent or 0)
	if frame.threatMode == "gauge" then
		if percent and not issecretvalue(percent) then
			local fraction = math.min(math.max(percent / 100, 0), 1)
			frame.ThreatNeedle:SetRotation(NEEDLE_LEFT + (NEEDLE_RIGHT - NEEDLE_LEFT) * fraction)
			frame.ThreatNeedle:Show()
		else
			frame.ThreatNeedle:Hide()
		end
	end
end

function Threat.Update(frame, unit)
	local _, status, percent = UnitDetailedThreatSituation("player", unit)
	if issecretvalue(status) then
		-- No readable status: show the number only, in neutral color.
		if not percent then
			frame.ThreatHolder:Hide()
			return
		end
		frame.ThreatHolder:Show()
		frame.ThreatText:SetFormattedText("%.0f%%", percent)
		frame.ThreatBar:SetValue(percent)
		frame.ThreatNeedle:Hide()
		return
	end
	Show(frame, status, percent)
end

function Threat.Preview(frame, sample)
	Show(frame, sample.threat and 1 or nil, sample.threat)
end

