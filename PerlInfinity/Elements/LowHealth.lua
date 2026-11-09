-- The edges of the screen pulse red when your health is low, and flash when
-- you lose control of your character. Your health is secret, so the game
-- decides whether you're under the threshold: a step curve over your health
-- percent gives the overlay's alpha directly.
--
-- The warning is a setting on the General page, so it runs on its own rather
-- than as part of the player frame: it keeps working with that frame off.
--
-- A flight path takes control away too, but that isn't something to warn about.
-- The check runs again on each pulse in case the game marks you as flying just
-- after it tells us you've lost control.
local _, ns = ...

local Secret = ns.Secret

local UnitHealthPercent = UnitHealthPercent
local UnitOnTaxi = UnitOnTaxi

local LowHealth = ns:NewModule("LowHealth")

local overlay, controlOverlay, listener

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

local function StopControlGlow()
	controlOverlay:SetAlpha(0)
	controlOverlay.Pulse:Stop()
end

local function UpdateHealth()
	if UnitIsDeadOrGhost("player") then
		overlay:SetAlpha(0)
		return
	end
	local fraction = ns.db.alerts.lowHealthPercent / 100
	overlay:SetAlpha(UnitHealthPercent("player", true, Secret.ShowBelow(fraction)))
end

local function OnEvent(_, event)
	if event == "PLAYER_CONTROL_LOST" then
		if not UnitOnTaxi("player") then
			controlOverlay:SetAlpha(1)
			controlOverlay.Pulse:Play()
		end
	elseif event == "PLAYER_CONTROL_GAINED" then
		StopControlGlow()
	else
		UpdateHealth()
	end
end

-- Starts or stops the warning to match the settings.
local function Apply()
	local on = ns.db.alerts.lowHealth and true or false
	if on == LowHealth.on then
		if on then
			UpdateHealth()
		end
		return
	end
	LowHealth.on = on
	if on then
		listener:RegisterUnitEvent("UNIT_HEALTH", "player")
		listener:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
		listener:RegisterEvent("PLAYER_CONTROL_LOST")
		listener:RegisterEvent("PLAYER_CONTROL_GAINED")
		overlay:Show()
		overlay.Pulse:Play()
		controlOverlay:Show()
		UpdateHealth()
	else
		listener:UnregisterAllEvents()
		overlay:SetAlpha(0)
		overlay.Pulse:Stop()
		StopControlGlow()
	end
end

function LowHealth:Login()
	overlay = Overlay("Interface\\FullScreenTextures\\LowHealth")
	controlOverlay = Overlay("Interface\\FullScreenTextures\\OutOfControl")
	controlOverlay.Pulse:SetScript("OnLoop", function()
		if UnitOnTaxi("player") then
			StopControlGlow()
		end
	end)
	self.overlay, self.controlOverlay = overlay, controlOverlay
	listener = CreateFrame("Frame")
	listener:SetScript("OnEvent", function(...)
		ns.Call(OnEvent, ...)
	end)
	-- Any change, since a profile switch or a reset swaps the alerts too.
	ns.Config:Subscribe("", self, Apply)
	Apply()
end
