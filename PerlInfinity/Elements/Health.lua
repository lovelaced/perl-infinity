-- Health bar, its color, the text on it, and the percent column.
--
-- Health numbers are always secret on Forever, even your own. They go
-- straight into the bar and into Blizzard's number formatting; the percent
-- comes from UnitHealthPercent with a curve, and the color from a color curve
-- the game evaluates. Dead, ghost and offline aren't secret, so those are
-- plain checks.
local _, ns = ...

local Bars, Colors, Secret = ns.Bars, ns.Colors, ns.Secret
local L = ns.L

local UnitHealth, UnitHealthMax, UnitHealthMissing, UnitHealthPercent =
	UnitHealth, UnitHealthMax, UnitHealthMissing, UnitHealthPercent
local UnitIsDeadOrGhost, UnitIsGhost, UnitIsConnected, UnitIsFeignDeath =
	UnitIsDeadOrGhost, UnitIsGhost, UnitIsConnected, UnitIsFeignDeath
local UnitIsPlayer, UnitClass = UnitIsPlayer, UnitClass
local AbbreviateNumbers = AbbreviateNumbers
local ScaleTo100 = CurveConstants.ScaleTo100

local Health = ns.Element("Health", {
	unitEvents = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_FACTION" },
	poll = true,
})

local GREY = 0.5

-- Text formats: none, current, currentMax, missing, missingMax, percent.
local function SetHealthText(text, unit, mode)
	if mode == "none" then
		text:SetText("")
		return
	end
	text:SetAlpha(1)
	if mode == "current" then
		text:SetText(AbbreviateNumbers(UnitHealth(unit)))
	elseif mode == "currentMax" then
		text:SetFormattedText("%s / %s", AbbreviateNumbers(UnitHealth(unit)), AbbreviateNumbers(UnitHealthMax(unit)))
	elseif mode == "missing" then
		text:SetText("-" .. AbbreviateNumbers(UnitHealthMissing(unit, true)))
		-- Nothing to show at full health; the game picks the alpha.
		text:SetAlpha(UnitHealthPercent(unit, true, Secret.HideAtFull()))
	elseif mode == "missingMax" then
		text:SetFormattedText("-%s / %s", AbbreviateNumbers(UnitHealthMissing(unit, true)), AbbreviateNumbers(UnitHealthMax(unit)))
	elseif mode == "percent" then
		text:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, ScaleTo100))
	end
end
Health.SetHealthText = SetHealthText

-- Returns a status word when the unit isn't alive and online, else nil.
local function StatusWord(unit)
	if not UnitIsConnected(unit) then
		return L.STATUS_OFFLINE
	elseif UnitIsGhost(unit) then
		return L.STATUS_GHOST
	elseif UnitIsDeadOrGhost(unit) then
		if ns.db.general.feignDeath and UnitIsFeignDeath(unit) then
			return L.STATUS_FEIGN
		end
		return L.STATUS_DEAD
	end
	return nil
end
Health.StatusWord = StatusWord

local function ColorBar(frame, unit)
	local bar = frame.Health
	if ns.db.look.healthColor == "class" and UnitIsPlayer(unit) then
		local _, classToken = UnitClass(unit)
		local r, g, b = Colors.Class(classToken)
		if r then
			Bars.SetColor(bar, r, g, b)
			return
		end
	end
	-- Red to green (or custom) by percent; the game evaluates the curve.
	local color = UnitHealthPercent(unit, true, Colors.HealthCurve())
	Bars.SetColor(bar, color:GetRGB())
end

function Health.Create(frame)
end

function Health.Configure(frame, conf)
	frame.healthText = conf.barText or conf.healthText or "none"
	frame.showPercent = conf.percent and frame.spec.layout ~= "Raid"
	frame.HealthPercent:SetShown(frame.showPercent or frame.spec.layout == "Raid")
	frame.Health.Text:SetFontObject(ns.db.look.thickHealth and frame.spec.layout ~= "Raid" and "GameFontHighlight" or "GameFontHighlightSmall")
end

function Health.Update(frame, unit)
	local bar = frame.Health
	local status = StatusWord(unit)
	if status then
		Bars.Set(bar, 0, 1)
		Bars.SetColor(bar, GREY, GREY, GREY)
		bar.Text:SetAlpha(1)
		bar.Text:SetText(status)
		frame.HealthPercent:SetText("")
		frame.dead = true
		return
	end
	frame.dead = false

	local maxHealth = UnitHealthMax(unit)
	if ns.db.look.invertBars then
		Bars.Set(bar, UnitHealthMissing(unit, true), maxHealth)
	else
		Bars.Set(bar, UnitHealth(unit), maxHealth)
	end
	if frame.snap then
		Bars.Snap(bar)
	end
	ColorBar(frame, unit)

	if frame.spec.layout == "Raid" then
		bar.Text:SetText("")
		SetHealthText(frame.HealthPercent, unit, frame.healthText)
	else
		SetHealthText(bar.Text, unit, frame.healthText)
		if frame.showPercent then
			frame.HealthPercent:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, ScaleTo100))
		end
	end
end

function Health.Preview(frame, sample)
	local bar = frame.Health
	if sample.dead then
		Bars.Set(bar, 0, 1)
		Bars.SetColor(bar, GREY, GREY, GREY)
		bar.Text:SetText(sample.dead)
		frame.HealthPercent:SetText("")
		return
	end
	Bars.Set(bar, sample.health, sample.maxHealth)
	local fraction = ns.Util.Fraction(sample.health, sample.maxHealth)
	local look = ns.db.look
	if look.healthColor == "class" and sample.class then
		local r, g, b = Colors.Class(sample.class)
		Bars.SetColor(bar, r, g, b)
	else
		Bars.SetColor(bar, Colors.HealthCurve():Evaluate(fraction):GetRGB())
	end
	if look.invertBars then
		bar:SetValue(sample.maxHealth - sample.health)
	end
	local mode = frame.healthText
	local text = frame.spec.layout == "Raid" and frame.HealthPercent or bar.Text
	if frame.spec.layout == "Raid" then
		bar.Text:SetText("")
	end
	local current, maximum = AbbreviateNumbers(sample.health), AbbreviateNumbers(sample.maxHealth)
	local missing = AbbreviateNumbers(sample.maxHealth - sample.health)
	text:SetAlpha(1)
	if mode == "none" then
		text:SetText("")
	elseif mode == "current" then
		text:SetText(current)
	elseif mode == "currentMax" then
		text:SetFormattedText("%s / %s", current, maximum)
	elseif mode == "missing" then
		text:SetText(sample.health < sample.maxHealth and ("-" .. missing) or "")
	elseif mode == "missingMax" then
		text:SetFormattedText("-%s / %s", missing, maximum)
	elseif mode == "percent" then
		text:SetFormattedText("%.0f%%", fraction * 100)
	end
	if frame.showPercent then
		frame.HealthPercent:SetFormattedText("%.0f%%", fraction * 100)
	end
end
