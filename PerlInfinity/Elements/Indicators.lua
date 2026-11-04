-- The small icons riding on a frame's edges. Each is its own tiny element so
-- an event only refreshes the icon it affects.
--
-- Icons stay "shown" and use alpha for visibility, because several of these
-- answers (raid marker, PvP flag, role outside your group) can be secret and
-- SetShown refuses secret booleans.
local _, ns = ...

local Secret, Media = ns.Secret, ns.Media
local L = ns.L

local issecretvalue = issecretvalue

local function Icon(frame, layer, size)
	local icon = frame.Content:CreateTexture(nil, layer or "OVERLAY")
	icon:SetSize(size, size)
	icon:SetAlpha(0)
	return icon
end

local function Hide(icon)
	if icon then
		icon:SetAlpha(0)
	end
end

---------------------------------------------------------------------------
-- Leader, assistant and master looter
---------------------------------------------------------------------------

local Leader = ns.Element("Leader", {
	events = { "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE", "PARTY_LOOT_METHOD_CHANGED" },
})

function Leader.Enabled(frame)
	return frame.spec.layout ~= "Small"
end

function Leader.Create(frame)
	local leader = Icon(frame, "OVERLAY", frame.spec.layout == "Raid" and 10 or 14)
	leader:SetPoint("CENTER", frame.NameBox, "TOPLEFT", 12, 0)
	frame.LeaderIcon = leader

	local looter = Icon(frame, "OVERLAY", frame.spec.layout == "Raid" and 10 or 14)
	looter:SetTexture("Interface\\GroupFrame\\UI-Group-MasterLooter")
	looter:SetPoint("LEFT", leader, "RIGHT", 1, 0)
	frame.LooterIcon = looter
end

function Leader.Disable(frame)
	Hide(frame.LeaderIcon)
	Hide(frame.LooterIcon)
end

local function IsMasterLooter(unit)
	local method, partyIndex, raidIndex = C_PartyInfo.GetLootMethod()
	if method ~= Enum.LootMethod.Masterlooter then
		return false
	end
	if raidIndex and raidIndex > 0 then
		return UnitIsUnit(unit, "raid" .. raidIndex)
	end
	if not partyIndex then
		return false
	end
	if partyIndex == 0 then
		return UnitIsUnit(unit, "player")
	end
	return UnitIsUnit(unit, "party" .. partyIndex)
end

function Leader.Update(frame, unit)
	local icon = frame.LeaderIcon
	-- Only players lead groups; asking about a creature can return a secret.
	if not UnitIsPlayer(unit) then
		icon:SetAlpha(0)
		frame.LooterIcon:SetAlpha(0)
		return
	end
	if UnitIsGroupLeader(unit) then
		icon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
		icon:SetAlpha(1)
	elseif UnitIsGroupAssistant(unit) and IsInRaid() then
		icon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
		icon:SetAlpha(1)
	else
		icon:SetAlpha(0)
	end
	Secret.ShowIf(frame.LooterIcon, IsMasterLooter(unit))
end

function Leader.Preview(frame, sample)
	frame.LeaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
	frame.LeaderIcon:SetAlpha(sample.leader and 1 or 0)
	frame.LooterIcon:SetAlpha(0)
end

---------------------------------------------------------------------------
-- Raid target marker (skull, star...)
---------------------------------------------------------------------------

local RaidIcon = ns.Element("RaidIcon", {
	events = { "RAID_TARGET_UPDATE" },
})

function RaidIcon.Create(frame)
	local icon = frame.Content:CreateTexture(nil, "OVERLAY")
	icon:SetTexture(Media.RAID_ICONS)
	icon:SetAlpha(0)
	frame.RaidIcon = icon
end

function RaidIcon.Configure(frame)
	local icon = frame.RaidIcon
	icon:ClearAllPoints()
	local large = ns.db.look.raidMarker == "name" and frame.spec.layout ~= "Raid"
	if large then
		icon:SetSize(26, 26)
		icon:SetPoint("CENTER", frame.NameBox, "CENTER")
	else
		local size = frame.spec.layout == "Raid" and 12 or 16
		icon:SetSize(size, size)
		icon:SetPoint("CENTER", frame.NameBox, "TOPRIGHT", -8, -2)
	end
end

function RaidIcon.Disable(frame)
	Hide(frame.RaidIcon)
end

function RaidIcon.Update(frame, unit)
	local index = GetRaidTargetIndex(unit)
	local icon = frame.RaidIcon
	-- The index may be secret; a secret number still counts as "set" here,
	-- and SetSpriteSheetCell takes it as is.
	if index then
		icon:SetSpriteSheetCell(index, 4, 4)
		icon:SetAlpha(1)
	else
		icon:SetAlpha(0)
	end
end

function RaidIcon.Preview(frame, sample)
	if sample.raidIcon then
		frame.RaidIcon:SetSpriteSheetCell(sample.raidIcon, 4, 4)
		frame.RaidIcon:SetAlpha(1)
	else
		frame.RaidIcon:SetAlpha(0)
	end
end

---------------------------------------------------------------------------
-- PvP flag (and your own PvP timer)
---------------------------------------------------------------------------

local PvP = ns.Element("PvP", {
	unitEvents = { "UNIT_FACTION" },
	events = { "PLAYER_FLAGS_CHANGED" },
})

local FACTION_ICONS = {
	Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
	Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
}

function PvP.Enabled(frame)
	return ns.db.look.pvpIcon and frame.spec.layout ~= "Raid"
end

function PvP.Create(frame)
	local icon = Icon(frame, "OVERLAY", 40)
	icon:SetPoint("CENTER", frame.NameBox, "TOPLEFT", 4, -8)
	frame.PvPIcon = icon
	if frame.kind == "player" then
		local timer = frame.NameBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		timer:SetPoint("BOTTOMLEFT", frame.NameBox, "TOPLEFT", 6, 0)
		frame.PvPTimer = timer
	end
end

function PvP.Disable(frame)
	Hide(frame.PvPIcon)
	if frame.PvPTimer then
		frame.PvPTimer:SetText("")
	end
end

function PvP.Update(frame, unit)
	local icon = frame.PvPIcon
	if UnitIsPVPFreeForAll(unit) then
		icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA")
		icon:SetAlpha(1)
	else
		local faction = UnitFactionGroup(unit)
		local texture = faction and not issecretvalue(faction) and FACTION_ICONS[faction]
		if texture then
			icon:SetTexture(texture)
			Secret.ShowIf(icon, UnitIsPVP(unit))
		else
			icon:SetAlpha(0)
		end
	end
	if frame.PvPTimer then
		local seconds = IsPVPTimerRunning() and GetPVPTimer() / 1000 or 0
		if seconds > 0 then
			frame.PvPTimer:SetFormattedText(L.PVP_TIMER, math.floor(seconds / 60), seconds % 60)
		else
			frame.PvPTimer:SetText("")
		end
	end
end

function PvP.Preview(frame)
	Hide(frame.PvPIcon)
end

---------------------------------------------------------------------------
-- In combat or resting (your own frame)
---------------------------------------------------------------------------

local StateIcon = ns.Element("StateIcon", {
	events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING" },
})

function StateIcon.Enabled(frame)
	return frame.kind == "player"
end

function StateIcon.Create(frame)
	local icon = Icon(frame, "OVERLAY", 22)
	icon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
	icon:SetPoint("RIGHT", frame.NameBox, "RIGHT", -4, 0)
	frame.StateIcon = icon
end

function StateIcon.Disable(frame)
	Hide(frame.StateIcon)
end

function StateIcon.Update(frame)
	local icon = frame.StateIcon
	local inCombat = UnitAffectingCombat("player")
	if inCombat then
		icon:SetTexCoord(0.5, 1, 0, 0.5)
		icon:SetAlpha(1)
	elseif IsResting() then
		icon:SetTexCoord(0, 0.5, 0, 0.421875)
		icon:SetAlpha(1)
	else
		icon:SetAlpha(0)
	end
	-- X-Perl turns your name red while you're in combat.
	if inCombat then
		frame.NameText:SetTextColor(1, 0.2, 0.2)
	elseif frame.wasInCombat then
		ns.Elements.Name.Update(frame, "player")
	end
	frame.wasInCombat = inCombat
end

---------------------------------------------------------------------------
-- Ready check
---------------------------------------------------------------------------

local ReadyCheck = ns.Element("ReadyCheck", {
	events = { "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED" },
})

local READY = {
	ready = READY_CHECK_READY_TEXTURE,
	notready = READY_CHECK_NOT_READY_TEXTURE,
	waiting = READY_CHECK_WAITING_TEXTURE,
}

function ReadyCheck.Enabled(frame)
	return ns.db.general.readyCheck and (frame.spec.group or frame.kind == "player")
end

function ReadyCheck.Create(frame)
	local icon = Icon(frame, "OVERLAY", frame.spec.layout == "Raid" and 14 or 24)
	icon:SetPoint("CENTER", frame.StatsBox, "CENTER")
	frame.ReadyIcon = icon
	local fade = icon:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0)
	alpha:SetStartDelay(6)
	alpha:SetDuration(1.5)
	fade:SetToFinalAlpha(true)
	frame.ReadyFade = fade
end

function ReadyCheck.Disable(frame)
	Hide(frame.ReadyIcon)
end

function ReadyCheck.OnUnitEvent(frame, event)
	frame.readyEvent = event
end

function ReadyCheck.Update(frame, unit)
	local status = GetReadyCheckStatus(unit)
	local icon = frame.ReadyIcon
	local texture = status and not issecretvalue(status) and READY[status]
	if texture then
		icon:SetTexture(texture)
		frame.ReadyFade:Stop()
		icon:SetAlpha(1)
		if frame.readyEvent == "READY_CHECK_FINISHED" then
			frame.ReadyFade:Play()
		end
	elseif frame.readyEvent ~= "READY_CHECK_FINISHED" then
		icon:SetAlpha(0)
	end
	frame.readyEvent = nil
end

function ReadyCheck.Preview(frame, sample)
	if sample.ready then
		frame.ReadyIcon:SetTexture(READY[sample.ready])
		frame.ReadyIcon:SetAlpha(1)
	else
		frame.ReadyIcon:SetAlpha(0)
	end
end

---------------------------------------------------------------------------
-- Incoming resurrection and summon
---------------------------------------------------------------------------

local Resurrect = ns.Element("Resurrect", {
	unitEvents = { "INCOMING_RESURRECT_CHANGED", "INCOMING_SUMMON_CHANGED" },
})

local SUMMON_ATLAS = {
	[Enum.SummonStatus and Enum.SummonStatus.Pending or 1] = "Raid-Icon-SummonPending",
	[Enum.SummonStatus and Enum.SummonStatus.Accepted or 2] = "Raid-Icon-SummonAccepted",
	[Enum.SummonStatus and Enum.SummonStatus.Declined or 3] = "Raid-Icon-SummonDeclined",
}

function Resurrect.Enabled(frame)
	return frame.kind ~= "player"
end

function Resurrect.Create(frame)
	local icon = Icon(frame, "OVERLAY", frame.spec.layout == "Raid" and 16 or 32)
	icon:SetPoint("CENTER", frame.PortraitBox or frame.StatsBox, "CENTER")
	frame.ResurrectIcon = icon
end

function Resurrect.Disable(frame)
	Hide(frame.ResurrectIcon)
end

function Resurrect.Update(frame, unit)
	local icon = frame.ResurrectIcon
	if UnitHasIncomingResurrection(unit) then
		icon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
		icon:SetTexCoord(0, 1, 0, 1)
		icon:SetAlpha(1)
		return
	end
	if C_IncomingSummon.HasIncomingSummon(unit) then
		local atlas = SUMMON_ATLAS[C_IncomingSummon.IncomingSummonStatus(unit)]
		if atlas then
			icon:SetAtlas(atlas)
			icon:SetAlpha(1)
			return
		end
	end
	icon:SetAlpha(0)
end

---------------------------------------------------------------------------
-- Group role (tank, healer, damage)
---------------------------------------------------------------------------

local Role = ns.Element("Role", {
	events = { "PLAYER_ROLES_ASSIGNED", "GROUP_ROSTER_UPDATE" },
})

function Role.Enabled(frame)
	return ns.db.look.roleIcons and frame.spec.group
end

function Role.Create(frame)
	local icon = Icon(frame, "OVERLAY", frame.spec.layout == "Raid" and 10 or 14)
	icon:SetPoint("CENTER", frame.NameBox, "BOTTOMLEFT", 6, 2)
	frame.RoleIcon = icon
end

function Role.Disable(frame)
	Hide(frame.RoleIcon)
end

function Role.Update(frame, unit)
	local role = UnitGroupRolesAssigned(unit)
	local texture = role and not issecretvalue(role) and Media.ROLE[role]
	if texture then
		frame.RoleIcon:SetTexture(texture)
		frame.RoleIcon:SetAlpha(1)
	else
		frame.RoleIcon:SetAlpha(0)
	end
end

function Role.Preview(frame, sample)
	local texture = sample.role and Media.ROLE[sample.role]
	if texture then
		frame.RoleIcon:SetTexture(texture)
		frame.RoleIcon:SetAlpha(1)
	else
		frame.RoleIcon:SetAlpha(0)
	end
end

---------------------------------------------------------------------------
-- Your raid group number, above the player frame or after your name
---------------------------------------------------------------------------

local function PlayerGroupNumber()
	local index = UnitInRaid("player")
	if not index then
		return nil
	end
	local _, _, group = GetRaidRosterInfo(index)
	return group
end

local GroupNumber = ns.Element("GroupNumber", {
	events = { "GROUP_ROSTER_UPDATE" },
})

function GroupNumber.Enabled(frame, conf)
	return frame.kind == "player" and conf.groupNumber ~= "hidden"
end

function GroupNumber.Create(frame)
	local tab = ns.Box.Create(frame.Content)
	tab:SetSize(60, 18)
	tab:SetPoint("BOTTOMLEFT", frame.NameBox, "TOPLEFT", 4, -3)
	local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetPoint("CENTER", 0, 1)
	tab.Text = text
	tab:Hide()
	frame.GroupTab = tab
end

-- "Next to my name" adds the group to the name each time the name is drawn.
local function AppendGroup(frame, unit)
	local group = frame.groupNumberStyle == "name" and PlayerGroupNumber()
	if group then
		frame.NameText:SetFormattedText(L.NAME_WITH_GROUP, UnitName(unit), group)
	end
end

function GroupNumber.Configure(frame, conf)
	frame.groupNumberStyle = conf.groupNumber
	frame.OnNameUpdated = AppendGroup
end

function GroupNumber.Disable(frame)
	frame.GroupTab:Hide()
end

function GroupNumber.Update(frame)
	local group = PlayerGroupNumber()
	if group and frame.groupNumberStyle == "above" then
		frame.GroupTab.Text:SetFormattedText(L.GROUP_N, group)
		frame.GroupTab:Show()
	else
		frame.GroupTab:Hide()
	end
	AppendGroup(frame, "player")
end

function GroupNumber.Preview(frame, sample)
	if sample.group and frame.groupNumberStyle == "above" then
		frame.GroupTab.Text:SetFormattedText(L.GROUP_N, sample.group)
		frame.GroupTab:Show()
	else
		frame.GroupTab:Hide()
	end
end
