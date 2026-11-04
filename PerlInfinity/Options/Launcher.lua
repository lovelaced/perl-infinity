-- A small page in the game's own Options > AddOns list, so people looking
-- there find Perl Infinity. It explains where things live and opens the Perl Infinity
-- window or Edit Mode. It's registered when the addon loads so the game's
-- settings search can find it.
local _, ns = ...

local Launcher = ns:NewModule("Launcher")
local L = ns.L

local function OpenFromSettings(open)
	if SettingsPanel and SettingsPanel:IsShown() then
		HideUIPanel(SettingsPanel)
	end
	open()
end

function Launcher:Init()
	if not Settings or not Settings.RegisterVerticalLayoutCategory then
		return
	end
	local category, layout = Settings.RegisterVerticalLayoutCategory(L.WINDOW_TITLE)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.LAUNCHER_HEADER, L.LAUNCHER_TEXT))
	layout:AddInitializer(CreateSettingsButtonInitializer(L.LAUNCHER_OPTIONS_LABEL, L.LAUNCHER_OPTIONS_BUTTON, function()
		OpenFromSettings(function()
			ns.Options:Open()
		end)
	end, L.LAUNCHER_OPTIONS_TIP, true))
	layout:AddInitializer(CreateSettingsButtonInitializer(L.LAUNCHER_MOVE_LABEL, L.LAUNCHER_MOVE_BUTTON, function()
		OpenFromSettings(function()
			ns.Movers:OpenEditMode()
		end)
	end, L.LAUNCHER_MOVE_TIP, true))
	Settings.RegisterAddOnCategory(category)
	self.category = category
end
