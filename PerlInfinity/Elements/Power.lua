-- Power bar (mana, rage, energy, focus) and its text. Like health, the
-- numbers can be secret, so they only ever go into the bar and Blizzard's
-- formatting. The power type itself is never secret.
local _, ns = ...

local Bars, Colors = ns.Bars, ns.Colors

local UnitPower, UnitPowerMax, UnitPowerType, UnitPowerPercent =
	UnitPower, UnitPowerMax, UnitPowerType, UnitPowerPercent
local UnitIsConnected, UnitIsDeadOrGhost = UnitIsConnected, UnitIsDeadOrGhost
local AbbreviateNumbers = AbbreviateNumbers
local ScaleTo100 = CurveConstants.ScaleTo100

local FREQUENT = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION" }
local NORMAL = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_CONNECTION" }

local Power = ns.Element("Power", {
	-- Smooth updates for you and your pet; everyone else updates on the
	-- slower event, which is plenty for a raid's mana bars.
	unitEvents = function(frame)
		if frame.kind == "player" or frame.kind == "pet" then
			return FREQUENT
		end
		return NORMAL
	end,
	poll = true,
})

function Power.Enabled(frame, conf)
	if frame.spec.layout == "Raid" then
		return conf.mana
	end
	return conf.power ~= false
end

function Power.Create(frame)
end

function Power.Configure(frame, conf)
	frame.Power:Show()
	frame.powerText = conf.barText or "none"
	frame.showPowerPercent = conf.percent and frame.hasPercentColumn and frame.spec.layout ~= "Raid"
	frame.raidManaPercent = frame.spec.layout == "Raid" and conf.manaPercent
	frame.PowerPercent:SetShown(frame.showPowerPercent)
end

function Power.Disable(frame)
	frame.Power:Hide()
	frame.PowerPercent:Hide()
end

function Power.Update(frame, unit)
	local bar = frame.Power
	local powerType, token = UnitPowerType(unit)
	local color = Colors.Power(token)
	Bars.SetColor(bar, color.r, color.g, color.b)

	if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then
		Bars.Set(bar, 0, 1)
		bar.Text:SetText("")
		frame.PowerPercent:SetText("")
		return
	end

	local power, maxPower = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
	Bars.Set(bar, power, maxPower)
	if frame.snap then
		Bars.Snap(bar)
	end

	local text = bar.Text
	local mode = frame.powerText
	if frame.raidManaPercent then
		text:SetFormattedText("%.0f%%", UnitPowerPercent(unit, powerType, false, ScaleTo100))
	elseif mode == "none" then
		text:SetText("")
	elseif mode == "current" then
		text:SetText(AbbreviateNumbers(power))
	else
		-- Missing-health modes still show current / max for power.
		text:SetFormattedText("%s / %s", AbbreviateNumbers(power), AbbreviateNumbers(maxPower))
	end

	if frame.showPowerPercent then
		if token == "MANA" then
			frame.PowerPercent:SetFormattedText("%.0f%%", UnitPowerPercent(unit, powerType, false, ScaleTo100))
		else
			-- X-Perl shows rage and energy as their actual amount.
			frame.PowerPercent:SetText(AbbreviateNumbers(power))
		end
	end
end

function Power.Preview(frame, sample)
	local bar = frame.Power
	local color = Colors.Power(sample.powerToken or "MANA")
	Bars.SetColor(bar, color.r, color.g, color.b)
	Bars.Set(bar, sample.power or 0, sample.maxPower or 1)
	local power, maxPower = AbbreviateNumbers(sample.power or 0), AbbreviateNumbers(sample.maxPower or 0)
	if frame.raidManaPercent then
		bar.Text:SetFormattedText("%.0f%%", ns.Util.Fraction(sample.power, sample.maxPower) * 100)
	elseif frame.powerText == "none" then
		bar.Text:SetText("")
	elseif frame.powerText == "current" then
		bar.Text:SetText(power)
	else
		bar.Text:SetFormattedText("%s / %s", power, maxPower)
	end
	if frame.showPowerPercent then
		if (sample.powerToken or "MANA") == "MANA" then
			frame.PowerPercent:SetFormattedText("%.0f%%", ns.Util.Fraction(sample.power, sample.maxPower) * 100)
		else
			frame.PowerPercent:SetText(power)
		end
	end
end
