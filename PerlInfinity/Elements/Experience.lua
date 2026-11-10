-- Experience and reputation bars under the player frame, and your pet's
-- experience under the pet frame. None of this is secret.
local _, ns = ...

local Build, Bars = ns.Build, ns.Bars
local L = ns.L

local Experience = ns.Element("Experience", {
	unitEvents = { "UNIT_PET_EXPERIENCE" },
	events = { "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING", "UPDATE_FACTION", "PLAYER_LEVEL_UP" },
})

local XP_R, XP_G, XP_B = 0.58, 0, 0.55
local RESTED_R, RESTED_G, RESTED_B = 0.2, 0.4, 1

function Experience.Enabled(frame, conf)
	if frame.kind == "player" then
		return conf.xpBar or conf.repBar
	end
	return frame.kind == "pet" and conf.xpBar
end

function Experience.Create(frame)
end

function Experience.Configure(frame, conf)
	local slots = frame.extraSlots or {}
	frame.XPBar = Build.ExtraBar(frame, "xp", slots.xp)
	frame.RepBar = Build.ExtraBar(frame, "rep", slots.rep)
	frame.xpRemaining = conf.xpRemaining
	if frame.XPBar and not frame.XPBar.Rested then
		local rested = frame.XPBar:CreateTexture(nil, "BORDER")
		rested:SetTexture(ns.Media.WHITE)
		rested:SetVertexColor(RESTED_R, RESTED_G, RESTED_B, 0.4)
		rested:SetPoint("TOPLEFT", frame.XPBar:GetStatusBarTexture(), "TOPRIGHT")
		rested:SetPoint("BOTTOMLEFT", frame.XPBar:GetStatusBarTexture(), "BOTTOMRIGHT")
		frame.XPBar.Rested = rested
	end
end

function Experience.Disable(frame)
	frame.XPBar = Build.ExtraBar(frame, "xp", nil)
	frame.RepBar = Build.ExtraBar(frame, "rep", nil)
end

local function ShowXP(bar, current, maximum, rested, remaining)
	Bars.Set(bar, current, maximum)
	Bars.SetColor(bar, XP_R, XP_G, XP_B)
	if remaining then
		bar.Text:SetFormattedText(L.XP_TO_GO, BreakUpLargeNumbers(maximum - current))
	else
		bar.Text:SetFormattedText("%s / %s", BreakUpLargeNumbers(current), BreakUpLargeNumbers(maximum))
	end
	if bar.Rested then
		local width = bar:GetWidth()
		local restedWidth = (rested and maximum > 0) and math.min(rested / maximum, 1 - current / maximum) * width or 0 -- lint: allow L10 (maximum > 0)
		bar.Rested:SetWidth(math.max(restedWidth, 0.01))
		bar.Rested:SetShown(restedWidth > 0)
	end
end

local function ShowReputation(bar)
	local data = C_Reputation.GetWatchedFactionData()
	if not data or not data.name then
		Bars.Set(bar, 0, 1)
		bar.Text:SetText(L.NO_FACTION)
		return
	end
	local low, high = data.currentReactionThreshold or 0, data.nextReactionThreshold or 1
	local value = (data.currentStanding or 0) - low
	Bars.Set(bar, value, math.max(high - low, 1))
	local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[data.reaction]
	if color then
		Bars.SetColor(bar, color.r, color.g, color.b)
	end
	bar.Text:SetFormattedText("%s %d / %d", data.name, value, high - low)
end

function Experience.Update(frame)
	if frame.kind == "pet" then
		if frame.XPBar then
			local current, maximum = GetPetExperience()
			ShowXP(frame.XPBar, current or 0, math.max(maximum or 1, 1), nil, false)
		end
		return
	end
	if frame.XPBar then
		ShowXP(frame.XPBar, UnitXP("player"), math.max(UnitXPMax("player"), 1), GetXPExhaustion(), frame.xpRemaining)
	end
	if frame.RepBar then
		ShowReputation(frame.RepBar)
	end
end

function Experience.Preview(frame)
	if frame.XPBar then
		ShowXP(frame.XPBar, 6200, 10000, 2000, frame.xpRemaining)
	end
	if frame.RepBar then
		Bars.Set(frame.RepBar, 2400, 6000)
		Bars.SetColor(frame.RepBar, 0, 0.6, 0.1)
		frame.RepBar.Text:SetText(L.SAMPLE_FACTION)
	end
end
