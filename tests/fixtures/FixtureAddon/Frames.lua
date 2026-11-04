-- Fixture frames: a secure unit button with secret-safe sinks, a party header,
-- an aura container, and LibEditMode registration.
local _, ns = ...

local CreateFrame, UIParent = CreateFrame, UIParent
local UnitHealth, UnitHealthMax, UnitName = UnitHealth, UnitHealthMax, UnitName
local RegisterUnitWatch = RegisterUnitWatch

ns.Frames = {}
local Frames = ns.Frames

FixtureUnitButtonMixin = {}
local M = FixtureUnitButtonMixin

function M:OnLoad()
	self.Health:SetMinMaxValues(0, 1)
	self.loaded = true
end

function M:OnAttributeChanged(name, value)
	if name == "unit" then
		self.unit = value
		-- frames created visible never get OnShow, so register here too
		if value and self:IsVisible() then self:OnShow() end
	end
end

function M:OnShow()
	if not self.unit then return end
	self:RegisterUnitEvent("UNIT_HEALTH", self.unit)
	self:RegisterUnitEvent("UNIT_MAXHEALTH", self.unit)
	self:RegisterUnitEvent("UNIT_NAME_UPDATE", self.unit)
	self:SetScript("OnEvent", self.Update)
	self:Update()
end

function M:OnHide() self:UnregisterAllEvents() end

-- Secrets go straight into sinks.
function M:Update()
	local unit = self.unit
	if not unit then return end
	self.Health:SetMinMaxValues(0, UnitHealthMax(unit))
	self.Health:SetValue(UnitHealth(unit))
	self.Name:SetText(UnitName(unit))
end

function Frames:Build()
	local player = CreateFrame("Button", "FixturePlayerFrame", UIParent, "FixtureUnitButtonTemplate")
	player:SetPoint("CENTER", UIParent, "CENTER", -200, -100)
	player:SetAttribute("unit", "player")
	Frames.player = player

	local target = CreateFrame("Button", "FixtureTargetFrame", UIParent, "FixtureUnitButtonTemplate")
	target:SetPoint("CENTER", UIParent, "CENTER", 200, -100)
	target:SetAttribute("unit", "target")
	RegisterUnitWatch(target)
	Frames.target = target

	local header = CreateFrame("Frame", "FixturePartyHeader", UIParent, "SecureGroupHeaderTemplate")
	header:SetAttribute("template", "FixtureUnitButtonTemplate")
	header:SetAttribute("showParty", true)
	header:SetAttribute("showPlayer", true)
	header:SetAttribute("point", "TOP")
	header:SetAttribute("yOffset", -4)
	header:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -200)
	header:Show()
	Frames.party = header

	local auras = CreateFrame("AuraContainer", nil, player, "CustomAuraContainerTemplate")
	auras:SetPoint("TOPLEFT", player, "BOTTOMLEFT", 0, -2)
	auras:SetUnit("player")
	auras:AddAuraGroup("buffs", "HELPFUL", {
		maxFrameCount = 8,
		initializeFrame = function(button)
			local icon = button:CreateTexture(nil, "ARTWORK")
			button:SetIcon(icon)
		end,
	})
	Frames.auras = auras

	local LEM = ns.LibEditMode
	if LEM then
		LEM:AddFrame(player, function(_, layoutName, point, x, y)
			FixtureDB.positions = FixtureDB.positions or {}
			FixtureDB.positions[layoutName] = { point = point, x = x, y = y }
		end, { point = "CENTER", x = -200, y = -100 }, "Fixture player")
		LEM:RegisterCallback("layout", function(layoutName) Frames.layout = layoutName end)
	end
end
