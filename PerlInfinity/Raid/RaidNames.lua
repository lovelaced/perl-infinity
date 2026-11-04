-- A copyable list of your raid's names, for attendance or loot sheets.
local _, ns = ...

local RaidNames = {}
ns.RaidNames = RaidNames

local L = ns.L

StaticPopupDialogs.PERLINFINITY_RAID_NAMES = {
	text = L.DIALOG_RAID_NAMES,
	button1 = CLOSE,
	hasEditBox = true,
	editBoxWidth = 360,
	OnShow = function(dialog)
		local box = dialog.EditBox or dialog.editBox
		box:SetText(RaidNames:Text())
		box:HighlightText()
		box:SetFocus()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function RaidNames:Text()
	local names = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local name = GetRaidRosterInfo(i)
			if name then
				names[#names + 1] = name
			end
		end
	elseif IsInGroup() then
		names[1] = UnitName("player")
		for i = 1, GetNumSubgroupMembers() do
			names[#names + 1] = UnitName("party" .. i)
		end
	else
		names[1] = UnitName("player")
	end
	table.sort(names)
	return table.concat(names, ", ")
end

function RaidNames:Show()
	StaticPopup_Show("PERLINFINITY_RAID_NAMES")
end
