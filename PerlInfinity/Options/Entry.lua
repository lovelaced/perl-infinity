-- Ways in: /perlinfinity (and /pinf when nothing else uses it), the minimap AddOns
-- menu, and key bindings. Also the one-time welcome line and the reload
-- prompt when a frame is turned off.
local addonName, ns = ...

local Entry = ns:NewModule("Entry")
local L = ns.L

local PAGES = {
	player = "player", pet = "pet", target = "target", tot = "small", focus = "focus",
	party = "party", raid = "raid", tools = "tools", profiles = "profiles", look = "appearance",
}

local function Help()
	ns.Print(L.HELP_HEADER)
	for _, line in ipairs(L.HELP_LINES) do
		DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100" .. line[1] .. "|r  " .. line[2])
	end
end

local commands = {}

function commands.help()
	Help()
end

function commands.move()
	ns.Movers:OpenEditMode()
end

function commands.profile(name)
	if not name or name == "" then
		ns.Print(L.MSG_PROFILES:format(table.concat(ns.Profiles:List(), ", "), ns.Profiles:Active()))
	elseif ns.Profiles:Use(name) then
		ns.Print(L.MSG_PROFILE_USED:format(name))
	else
		ns.Print(L.MSG_PROFILE_MISSING:format(name))
	end
end

function commands.tanks()
	ns.Config:Set("tanks.enabled", not ns.db.tanks.enabled)
end

function commands.mana()
	ns.Config:Set("healers.enabled", not ns.db.healers.enabled)
end

function commands.buffs()
	ns.BuffCheck:Run()
end

function commands.names()
	ns.RaidNames:Show()
end

function commands.layouts(rest)
	local action, name = (rest or ""):match("^(%S*)%s*(.*)$")
	if action == "save" then
		ns.RaidLayouts:Save(name)
	elseif action == "load" then
		ns.RaidLayouts:Load(name)
	elseif action == "stop" then
		ns.RaidLayouts:Stop()
	else
		ns.Options:Open("tools")
	end
end

function commands.reset(rest)
	if rest == "positions" then
		ns.ProfileDialogs:ResetPositions()
	else
		Help()
	end
end

function commands.selftest(rest)
	ns.SelfTest:Run(rest == "dev")
end

function commands.log(rest)
	if rest == "clear" then
		ns.Log:Clear()
		ns.Print(L.MSG_LOG_CLEARED)
	else
		ns.Print(L.MSG_LOG:format(ns.Log:ErrorCount()))
	end
end

local function OnSlash(message)
	local command, rest = strtrim(message or ""):match("^(%S*)%s*(.*)$")
	command = command:lower()
	if command == "" then
		ns.Options:Toggle()
	elseif PAGES[command] then
		ns.Options:Open(PAGES[command])
	elseif commands[command] then
		commands[command](rest)
	else
		ns.Print(L.MSG_UNKNOWN_COMMAND)
	end
end

-- Minimap AddOns menu (declared in the TOC).
function PerlInfinity_OnAddonCompartmentClick(_, button)
	if button == "RightButton" then
		ns.Movers:OpenEditMode()
	else
		ns.Options:Toggle()
	end
end

function PerlInfinity_OnAddonCompartmentEnter(_, menuButton)
	GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
	GameTooltip_SetTitle(GameTooltip, L.WINDOW_TITLE)
	GameTooltip_AddNormalLine(GameTooltip, L.COMPARTMENT_LEFT)
	GameTooltip_AddNormalLine(GameTooltip, L.COMPARTMENT_RIGHT)
	GameTooltip:Show()
end

function PerlInfinity_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end

-- Key bindings (Bindings.xml).
BINDING_HEADER_PERLINFINITY = L.WINDOW_TITLE
BINDING_NAME_PERLINFINITY_OPTIONS = L.BINDING_OPTIONS
BINDING_NAME_PERLINFINITY_EDITMODE = L.BINDING_EDITMODE
BINDING_NAME_PERLINFINITY_RANGE = L.BINDING_RANGE
BINDING_NAME_PERLINFINITY_RAID = L.BINDING_RAID
BINDING_NAME_PERLINFINITY_RAIDPETS = L.BINDING_RAIDPETS
BINDING_NAME_PERLINFINITY_RAIDICONS = L.BINDING_RAIDICONS
BINDING_NAME_PERLINFINITY_TANKS = L.BINDING_TANKS
BINDING_NAME_PERLINFINITY_HEALERS = L.BINDING_HEALERS

local Bindings = {}
ns.Bindings = Bindings

function Bindings.Toggle(path)
	ns.Config:Set(path, not ns.Config:Get(path))
end

function Bindings.CycleRaidIcons()
	local order = { none = "buffs", buffs = "debuffs", debuffs = "none" }
	local nextMode = order[ns.db.raid.icons] or "none"
	ns.Config:Set("raid.icons", nextMode)
	ns.Print(L.Choices["raid.icons"][nextMode][1] or nextMode)
end

function Entry:Init()
	SLASH_PERLINFINITY1 = "/perlinfinity"
	if not hash_SlashCmdList or not hash_SlashCmdList["/PINF"] then
		SLASH_PERLINFINITY2 = "/pinf"
	end
	SlashCmdList.PERLINFINITY = OnSlash
end

function Entry:Login()
	local global = ns.Config:DB().global
	if not global.welcomed then
		global.welcomed = true
		ns.Print(L.MSG_WELCOME)
	end
	-- Other Perl ports draw their own frames on top of ours.
	for _, other in ipairs({ "ZPerl", "TPerl", "XPerlForever" }) do
		if C_AddOns.IsAddOnLoaded(other) then
			ns.Print(L.MSG_CONFLICT:format(other))
		end
	end
end

Entry.addonName = addonName
