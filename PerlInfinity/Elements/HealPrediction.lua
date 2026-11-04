-- Incoming heals and absorb shields on the health bar, plus the optional
-- "being healed" glow on party and raid frames.
--
-- Amounts are secret, so the game's heal prediction calculator does the
-- clamping for us: it never returns more than the missing health, which lets
-- each overlay bar sit right after the health fill without any math here.
-- (LibHealComm can't work on Forever; this is the game's own data.)
local _, ns = ...

local Colors = ns.Colors

local UnitGetDetailedHealPrediction = UnitGetDetailedHealPrediction

local HealPrediction = ns.Element("HealPrediction", {
	unitEvents = {
		"UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
		"UNIT_HEALTH", "UNIT_MAXHEALTH",
	},
	poll = true,
})

local function GlowWanted(frame)
	return frame.spec.group and ns.db.highlight.healing
end

function HealPrediction.Enabled(frame)
	local look = ns.db.look
	return (look.incomingHeals or look.absorbs or GlowWanted(frame)) and true or false
end

local function OverlayBar(parent, anchorTo, layer)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(ns.Media.BarTexture())
	bar:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT")
	bar:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMRIGHT")
	bar:SetFrameLevel(parent:GetFrameLevel() + (layer or 1))
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	return bar
end

function HealPrediction.Create(frame)
	local health = frame.Health
	health:SetClipsChildren(true)

	local calculator = CreateUnitHealPredictionCalculator()
	calculator:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
	calculator:SetIncomingHealOverflowPercent(1)
	calculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
	calculator:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.MaximumHealth)
	calculator:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.Total)
	frame.healCalculator = calculator

	local mine = OverlayBar(health, health:GetStatusBarTexture())
	local others = OverlayBar(health, mine:GetStatusBarTexture())
	local absorb = OverlayBar(health, others:GetStatusBarTexture())
	frame.IncomingMine, frame.IncomingOthers, frame.Absorb = mine, others, absorb

	-- Being healed: a bar with a range of 0 to 1 is completely full as soon
	-- as any heal is incoming and empty otherwise, which turns the secret
	-- amount into an on/off glow without comparing it.
	local glow = CreateFrame("StatusBar", nil, frame.Content)
	glow:SetPoint("TOPLEFT", frame.NameBox, "TOPLEFT", 2, -2)
	glow:SetPoint("BOTTOMRIGHT", frame.StatsBox, "BOTTOMRIGHT", -2, 2)
	glow:SetStatusBarTexture(ns.Media.WHITE)
	glow:GetStatusBarTexture():SetBlendMode("ADD")
	glow:SetStatusBarColor(0.2, 1, 0.2, 0.25)
	glow:SetMinMaxValues(0, 1)
	glow:SetValue(0)
	frame.HealingGlow = glow
end

function HealPrediction.Configure(frame)
	local look = ns.db.look
	local texture = ns.Media.BarTexture()
	-- Inverted bars fill from the other side, so overlays would point the
	-- wrong way; they're hidden while bars are inverted.
	local showHeals = look.incomingHeals and not look.invertBars
	local showAbsorbs = look.absorbs and not look.invertBars
	local heal = Colors.Look("incomingHealsColor")
	local absorb = Colors.Look("absorbsColor")
	for _, bar in ipairs({ frame.IncomingMine, frame.IncomingOthers, frame.Absorb }) do
		bar:SetStatusBarTexture(texture)
		bar:SetWidth(frame.Health:GetWidth())
	end
	frame.IncomingMine:SetStatusBarColor(heal.r, heal.g, heal.b, 0.8)
	frame.IncomingOthers:SetStatusBarColor(heal.r, heal.g, heal.b, 0.5)
	frame.Absorb:SetStatusBarColor(absorb.r, absorb.g, absorb.b, 0.7)
	frame.IncomingMine:SetShown(showHeals)
	frame.IncomingOthers:SetShown(showHeals)
	frame.Absorb:SetShown(showAbsorbs)
	frame.HealingGlow:SetShown(GlowWanted(frame))
end

function HealPrediction.Disable(frame)
	frame.IncomingMine:Hide()
	frame.IncomingOthers:Hide()
	frame.Absorb:Hide()
	frame.HealingGlow:Hide()
end

function HealPrediction.Update(frame, unit)
	local calculator = frame.healCalculator
	UnitGetDetailedHealPrediction(unit, "player", calculator)
	local maxHealth = calculator:GetMaximumHealth()
	local amount, mine, others = calculator:GetIncomingHeals()

	local width = frame.Health:GetWidth()
	local bar = frame.IncomingMine
	bar:SetWidth(width)
	bar:SetMinMaxValues(0, maxHealth)
	bar:SetValue(mine)

	bar = frame.IncomingOthers
	bar:SetWidth(width)
	bar:SetMinMaxValues(0, maxHealth)
	bar:SetValue(others)

	bar = frame.Absorb
	bar:SetWidth(width)
	bar:SetMinMaxValues(0, maxHealth)
	bar:SetValue((calculator:GetDamageAbsorbs()))

	frame.HealingGlow:SetValue(amount)
end

function HealPrediction.Preview(frame, sample)
	local maxHealth = sample.maxHealth or 1
	local width = frame.Health:GetWidth()
	for _, bar in ipairs({ frame.IncomingMine, frame.IncomingOthers, frame.Absorb }) do
		bar:SetWidth(width)
		bar:SetMinMaxValues(0, maxHealth)
	end
	frame.IncomingMine:SetValue(sample.incoming or 0)
	frame.IncomingOthers:SetValue(0)
	frame.Absorb:SetValue(sample.absorb or 0)
	frame.HealingGlow:SetValue(sample.incoming or 0)
end
