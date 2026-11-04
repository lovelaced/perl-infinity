-- Fixture core: boot on ADDON_LOADED/PLAYER_LOGIN, saved variables, slash command.
local addonName, ns = ...

local CreateFrame, UnitHealth, UnitHealthMax = CreateFrame, UnitHealth, UnitHealthMax

ns.Core = { booted = false, events = {} }
local Core = ns.Core

local DEFAULTS = { scale = 1, showParty = true }

local function OnEvent(_, event, arg1)
	Core.events[#Core.events + 1] = event
	if event == "ADDON_LOADED" and arg1 == addonName then
		FixtureDB = FixtureDB or {}
		for k, v in pairs(DEFAULTS) do
			if FixtureDB[k] == nil then FixtureDB[k] = v end
		end
		FixtureCharDB = FixtureCharDB or { logins = 0 }
		FixtureCharDB.logins = FixtureCharDB.logins + 1
	elseif event == "PLAYER_LOGIN" then
		Core.booted = true
		ns.Frames:Build()
	end
end

function Core:Init()
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_LOADED")
	f:RegisterEvent("PLAYER_LOGIN")
	f:SetScript("OnEvent", OnEvent)
	Core.bus = f
end

-- Deliberately wrong code paths the harness must catch (called only by tests).
function Core.BadCompare() return UnitHealth("player") > 0 end
function Core.BadSavedSecret() FixtureDB.lastHealth = UnitHealth("player") end
function Core.BadShown(frame) frame:SetShown(UnitHealthMax("target")) end

SLASH_FIXTURE1 = "/fixture"
SlashCmdList.FIXTURE = function(msg)
	Core.lastSlash = msg
	print("fixture: " .. msg)
end

function FixtureAddon_ToggleBinding(keystate) Core.toggled = keystate end

Core:Init()
