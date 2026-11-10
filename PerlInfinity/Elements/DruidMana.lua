-- Keeps a druid's mana in view on a thin bar while in bear or cat form. The
-- row is always reserved so nothing has to move in combat; in caster form,
-- where the main bar already shows mana, it simply fades out.
local _, ns = ...

local Build, Bars, Colors = ns.Build, ns.Bars, ns.Colors

local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local MANA = Enum.PowerType.Mana

local DruidMana = ns.Element("DruidMana", {
	unitEvents = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
	events = { "UPDATE_SHAPESHIFT_FORM" },
})

function DruidMana.Enabled(frame, conf)
	if frame.kind ~= "player" or not conf.druidMana then
		return false
	end
	local _, class = UnitClass("player")
	return class == "DRUID"
end

function DruidMana.Create(frame)
end

function DruidMana.Configure(frame)
	local slot = frame.extraSlots and frame.extraSlots.druidMana
	frame.DruidManaBar = Build.ExtraBar(frame, "druidMana", slot)
	if frame.DruidManaBar then
		local color = Colors.Look("mana")
		Bars.SetColor(frame.DruidManaBar, color.r, color.g, color.b)
	end
end

function DruidMana.Disable(frame)
	frame.DruidManaBar = Build.ExtraBar(frame, "druidMana", nil)
end

function DruidMana.Update(frame, unit)
	local bar = frame.DruidManaBar
	if not bar then
		return
	end
	Bars.Set(bar, UnitPower(unit, MANA), UnitPowerMax(unit, MANA))
	bar.Text:SetFormattedText("%s / %s", AbbreviateNumbers(UnitPower(unit, MANA)), AbbreviateNumbers(UnitPowerMax(unit, MANA)))
	bar:SetAlpha(UnitPowerType(unit) == MANA and 0.25 or 1)
end

function DruidMana.Preview(frame)
	local bar = frame.DruidManaBar
	if bar then
		Bars.Set(bar, 1800, 2400)
		bar.Text:SetText("1,800 / 2,400")
		bar:SetAlpha(1)
	end
end
