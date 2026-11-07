-- Group buff checks, from your own client:
--   * /perlinfinity buffs (or the button) lists who is missing a class buff such as
--     Power Word: Fortitude or Mark of the Wild, in your chat window only
--   * the tooltip of a buff on a group member lists who doesn't have it
--     (hold Alt to see who does)
--
-- Buff details are secret in combat on Forever, so both only work out of
-- combat; in combat they quietly do nothing.
local _, ns = ...

local BuffCheck = ns:NewModule("BuffCheck")
local Spells = ns.Spells
local L = ns.L

local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			units[#units + 1] = "raid" .. i
		end
	else
		units[1] = "player"
		for i = 1, GetNumSubgroupMembers() do
			units[#units + 1] = "party" .. i
		end
	end
	return units
end

local function CanRead()
	return not InCombatLockdown() and not C_Secrets.ShouldAurasBeSecret()
end

-- Names (all ranks) for a buff family, looked up when needed.
local function FamilyNames(family)
	local names = {}
	for _, id in ipairs(family.spells) do
		local name = C_Spell.GetSpellName(id)
		if name then
			names[name] = true
		end
	end
	return names
end

local function HasAny(unit, names)
	for i = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
		if not aura then
			return false
		end
		if not issecretvalue(aura.name) and names[aura.name] then
			return true
		end
	end
	return false
end

local function ClassPresent(class, units)
	for _, unit in ipairs(units) do
		local _, unitClass = UnitClass(unit)
		if not issecretvalue(unitClass) and unitClass == class then
			return true
		end
	end
	return false
end

function BuffCheck:Run()
	if not CanRead() then
		ns.Print(L.MSG_BUFFS_COMBAT)
		return
	end
	local units = GroupUnits()
	local any = false
	for _, family in ipairs(Spells.buffFamilies) do
		if ClassPresent(family.class, units) then
			local names = FamilyNames(family)
			local missing = {}
			for _, unit in ipairs(units) do
				if UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) and not HasAny(unit, names) then
					missing[#missing + 1] = ns.Secret.UnitFullName(unit)
				end
			end
			if #missing > 0 then
				any = true
				ns.Print(L.MSG_BUFF_MISSING:format(C_Spell.GetSpellName(family.spells[1]) or "?", table.concat(missing, ", ")))
			end
		end
	end
	if not any then
		ns.Print(L.MSG_BUFFS_ALL_GOOD)
	end
end

---------------------------------------------------------------------------
-- "Who's missing this buff" on buff tooltips
---------------------------------------------------------------------------

local function FamilyForSpell(spellID)
	for _, family in ipairs(Spells.buffFamilies) do
		for _, id in ipairs(family.spells) do
			if id == spellID then
				return family
			end
		end
	end
	local name = C_Spell.GetSpellName(spellID)
	for _, family in ipairs(Spells.buffFamilies) do
		if name and FamilyNames(family)[name] then
			return family
		end
	end
	return nil
end

local function OnAuraTooltip(tooltip, data)
	if not ns.db.tools.buffHelper or not CanRead() or not IsInGroup() then
		return
	end
	local spellID = data and data.id
	if not spellID or issecretvalue(spellID) then
		return
	end
	local family = FamilyForSpell(spellID)
	if not family then
		return
	end
	local names = FamilyNames(family)
	local wantHave = IsAltKeyDown()
	local list = {}
	for _, unit in ipairs(GroupUnits()) do
		if UnitExists(unit) and UnitIsConnected(unit) then
			if HasAny(unit, names) == wantHave then
				list[#list + 1] = ns.Secret.UnitFullName(unit)
			end
		end
	end
	table.sort(list)
	if #list > 0 then
		tooltip:AddLine(wantHave and L.TIP_HAVE_BUFF or L.TIP_MISSING_BUFF, 1, 0.82, 0)
		tooltip:AddLine(table.concat(list, ", "), 1, 1, 1, true)
	end
end

function BuffCheck:Login()
	if TooltipDataProcessor and Enum.TooltipDataType and Enum.TooltipDataType.UnitAura then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, function(tooltip, data)
			ns.Call(OnAuraTooltip, tooltip, data)
		end)
	end
end

ns.BuffCheck = BuffCheck
