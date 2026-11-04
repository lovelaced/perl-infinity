-- The edges of the screen pulse red when your health is low, and flash when
-- you lose control of your character. Your health is secret, so the game
-- decides whether you're under the threshold: a step curve over your health
-- percent gives the overlay's alpha directly.
local _, ns = ...

local Secret = ns.Secret

local UnitHealthPercent = UnitHealthPercent

local LowHealth = ns.Element("LowHealth", {
	unitEvents = { "UNIT_HEALTH", "UNIT_MAXHEALTH" },
	events = { "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" },
})

local overlay, controlOverlay

local function Pulse(texture)
	local group = texture:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local alpha = group:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0.35)
	alpha:SetDuration(0.8)
	return group
end

local function Overlay(file)
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetAllPoints()
	holder:SetFrameStrata("BACKGROUND")
	local texture = holder:CreateTexture(nil, "BACKGROUND")
	texture:SetTexture(file)
	texture:SetBlendMode("ADD")
	texture:SetAllPoints()
	holder.Texture = texture
	holder.Pulse = Pulse(texture)
	holder:SetAlpha(0)
	return holder
end

function LowHealth.Enabled(frame)
	return frame.kind == "player" and not frame.preview and ns.db.alerts.lowHealth
end

function LowHealth.Create()
	if not overlay then
		overlay = Overlay("Interface\\FullScreenTextures\\LowHealth")
		controlOverlay = Overlay("Interface\\FullScreenTextures\\OutOfControl")
	end
end

function LowHealth.Configure()
	overlay:Show()
	overlay.Pulse:Play()
	controlOverlay:Show()
end

function LowHealth.Disable()
	overlay:SetAlpha(0)
	overlay.Pulse:Stop()
	controlOverlay:SetAlpha(0)
end

function LowHealth.OnUnitEvent(_, event)
	if event == "PLAYER_CONTROL_LOST" then
		controlOverlay:SetAlpha(1)
		controlOverlay.Pulse:Play()
	elseif event == "PLAYER_CONTROL_GAINED" then
		controlOverlay:SetAlpha(0)
		controlOverlay.Pulse:Stop()
	end
end

function LowHealth.Update(_, unit)
	if UnitIsDeadOrGhost(unit) then
		overlay:SetAlpha(0)
		return
	end
	local fraction = ns.db.alerts.lowHealthPercent / 100
	overlay:SetAlpha(UnitHealthPercent(unit, true, Secret.ShowBelow(fraction)))
end
