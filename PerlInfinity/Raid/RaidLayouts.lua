-- Save who's in which raid group, and put everyone back later. Loading moves
-- one person at a time, waiting for the game to confirm each move, and gives
-- up after ten seconds. Needs raid leader or assistant, out of combat.
local _, ns = ...

local RaidLayouts = ns:NewModule("RaidLayouts")
local RosterPlan = ns.RosterPlan
local L = ns.L

local TIMEOUT = 10
local loading, deadline, timer

local function DB()
	return ns.Config:DB().raidLayouts
end

local function Roster()
	local roster = {}
	for index = 1, GetNumGroupMembers() do
		local name, _, group, _, _, class = GetRaidRosterInfo(index)
		if name then
			roster[#roster + 1] = { index = index, name = name, class = class, group = group }
		end
	end
	return roster
end

local function CanArrange()
	if not IsInRaid() then
		ns.Print(L.MSG_LAYOUT_NOT_RAID)
		return false
	end
	if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		ns.Print(L.MSG_LAYOUT_NOT_LEADER)
		return false
	end
	if InCombatLockdown() then
		ns.Print(L.MSG_NOT_IN_COMBAT)
		return false
	end
	return true
end

function RaidLayouts:Choices()
	local choices = {}
	for name in pairs(DB()) do
		choices[#choices + 1] = { label = name, value = name }
	end
	table.sort(choices, function(a, b)
		return a.label < b.label
	end)
	return choices
end

function RaidLayouts:Save(name)
	name = strtrim(name or "")
	if name == "" then
		return self:AskSave()
	end
	if not IsInRaid() then
		ns.Print(L.MSG_LAYOUT_NOT_RAID)
		return
	end
	local layout = {}
	for _, member in ipairs(Roster()) do
		layout[member.name] = { group = member.group, class = member.class }
	end
	DB()[name] = layout
	self.selected = name
	ns.Print(L.MSG_LAYOUT_SAVED:format(name))
end

local function Step()
	if not loading then
		return
	end
	if GetTime() > deadline or InCombatLockdown() then
		RaidLayouts:Stop()
		return
	end
	local move = RosterPlan.Next(Roster(), loading)
	if not move then
		ns.Print(L.MSG_LAYOUT_DONE)
		RaidLayouts:Stop(true)
		return
	end
	if move.kind == "move" then
		SetRaidSubgroup(move.index, move.group)
	else
		SwapRaidSubgroup(move.index, move.other)
	end
end

function RaidLayouts:Load(name)
	local layout = name and DB()[name]
	if not layout then
		ns.Print(L.MSG_LAYOUT_MISSING)
		return
	end
	if not CanArrange() then
		return
	end
	loading = layout
	deadline = GetTime() + TIMEOUT
	ns.Events:On("GROUP_ROSTER_UPDATE", self, Step)
	-- In case the game doesn't report a move, try again shortly.
	timer = C_Timer.NewTicker(1, function()
		ns.Call(Step)
	end, TIMEOUT)
	Step()
end

function RaidLayouts:Stop(quiet)
	if loading and not quiet then
		ns.Print(L.MSG_LAYOUT_STOPPED)
	end
	loading = nil
	ns.Events:Off("GROUP_ROSTER_UPDATE", self)
	if timer then
		timer:Cancel()
		timer = nil
	end
end

function RaidLayouts:Delete(name)
	if name and DB()[name] then
		DB()[name] = nil
		self.selected = nil
		ns.Print(L.MSG_LAYOUT_DELETED:format(name))
	end
end

StaticPopupDialogs.PERLINFINITY_LAYOUT_SAVE = {
	text = L.DIALOG_SAVE_LAYOUT,
	button1 = L.DIALOG_SAVE,
	button2 = CANCEL,
	hasEditBox = true,
	OnAccept = function(dialog)
		RaidLayouts:Save((dialog.EditBox or dialog.editBox):GetText())
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function RaidLayouts:AskSave()
	StaticPopup_Show("PERLINFINITY_LAYOUT_SAVE")
end

ns.RaidLayouts = RaidLayouts
