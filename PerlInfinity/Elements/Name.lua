-- The unit's name, colored by class for players and by reaction for
-- creatures. Names of creatures can be secret inside instances; they go
-- straight into SetText, and the text is never measured. A name too long for
-- its box gets cut off with dots by the font string.
local _, ns = ...

local Colors, Secret = ns.Colors, ns.Secret

local UnitIsPlayer, UnitClass = UnitIsPlayer, UnitClass

local Name = ns.Element("Name", {
	unitEvents = { "UNIT_NAME_UPDATE", "UNIT_FACTION", "UNIT_FLAGS" },
})

local YELLOW_R, YELLOW_G, YELLOW_B = 1, 0.82, 0

function Name.Create(frame)
end

function Name.Configure(frame, conf)
	frame.NameText:SetShown(conf.names ~= false and conf.name ~= false)
end

local function ColorName(frame, unit)
	local text = frame.NameText
	if UnitIsPlayer(unit) then
		if ns.db.look.classNames then
			local _, classToken = UnitClass(unit)
			local r, g, b = Colors.Class(classToken)
			if r then
				text:SetTextColor(r, g, b)
				return
			end
		end
		text:SetTextColor(YELLOW_R, YELLOW_G, YELLOW_B)
		return
	end
	local color = Colors.Reaction(unit)
	text:SetTextColor(color.r, color.g, color.b)
end

function Name.Update(frame, unit)
	frame.NameText:SetText(Secret.UnitFullName(unit))
	ColorName(frame, unit)
	if frame.OnNameUpdated then
		frame:OnNameUpdated(unit)
	end
end

function Name.Preview(frame, sample)
	frame.NameText:SetText(sample.name)
	local r, g, b
	if sample.class and ns.db.look.classNames then
		r, g, b = Colors.Class(sample.class)
	elseif sample.reaction then
		local color = Colors.Look(sample.reaction)
		r, g, b = color.r, color.g, color.b
	end
	frame.NameText:SetTextColor(r or YELLOW_R, g or YELLOW_G, b or YELLOW_B)
end
