-- AGGRO in the middle of the screen when an enemy turns on you or your pet
-- while you're in a group. Move it in Edit Mode.
local _, ns = ...

local Aggro = ns:NewModule("AggroWarning")
local L = ns.L

local frame, text

local function Update()
	if not ns.db.alerts.aggroWarning or not IsInGroup() then
		frame:Hide()
		return
	end
	local mine = UnitThreatSituation("player")
	local pet = UnitExists("pet") and UnitThreatSituation("pet")
	if mine and not issecretvalue(mine) and mine >= 2 then
		text:SetText(L.AGGRO)
		frame:Show()
	elseif pet and not issecretvalue(pet) and pet >= 2 then
		text:SetText(L.PET_AGGRO)
		frame:Show()
	else
		frame:Hide()
	end
end

function Aggro:Login()
	local mover = ns.Movers:Get("aggro")
	ns.Movers:SetSize("aggro", 200, 30)
	frame = CreateFrame("Frame", nil, mover)
	frame:SetAllPoints()
	text = frame:CreateFontString(nil, "OVERLAY", "GameFontRedLarge")
	text:SetPoint("CENTER")
	frame:Hide()
	ns.Events:On("UNIT_THREAT_SITUATION_UPDATE", self, Update)
	ns.Events:On("PLAYER_REGEN_ENABLED", self, Update)
	ns.Events:On("GROUP_ROSTER_UPDATE", self, Update)
end
