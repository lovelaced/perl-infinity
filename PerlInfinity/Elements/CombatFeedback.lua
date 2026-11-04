-- Damage and healing numbers over the portrait, and the X-Perl border flash
-- (red when hit, green when healed). Driven by UNIT_COMBAT, whose amounts
-- were readable in testing; if the game ever hides one, the number still
-- shows (formatted by the game) and only the flash color falls back.
-- Animations are AnimationGroups, so nothing ticks in Lua between hits.
local _, ns = ...

local Box = ns.Box

local issecretvalue = issecretvalue
local AbbreviateNumbers = AbbreviateNumbers

local CombatFeedback = ns.Element("CombatFeedback", {
	unitEvents = { "UNIT_COMBAT" },
})

local COLORS = {
	WOUND = { 1, 0.1, 0.1 },
	HEAL = { 0.1, 1, 0.1 },
	ENERGIZE = { 0.4, 0.6, 1 },
}

function CombatFeedback.Enabled(frame)
	local general = ns.db.general
	return not frame.preview and (general.hitIndicators or general.combatFlash) and frame.spec.combatFeedback ~= false
end

local function FadeGroup(region, hold, out)
	local group = region:CreateAnimationGroup()
	local fadeIn = group:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.1)
	fadeIn:SetOrder(1)
	local fadeOut = group:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetStartDelay(hold)
	fadeOut:SetDuration(out)
	fadeOut:SetOrder(2)
	group:SetToFinalAlpha(true)
	return group
end

function CombatFeedback.Create(frame)
	local anchor = frame.PortraitBox or frame.StatsBox
	local holder = CreateFrame("Frame", nil, frame.Content)
	holder:SetAllPoints(anchor)
	holder:SetFrameLevel(frame.Content:GetFrameLevel() + 10)
	frame.hitFont = frame.PortraitBox and "NumberFontNormalLarge" or "NumberFontNormal"
	local text = holder:CreateFontString(nil, "OVERLAY", frame.hitFont)
	text:SetPoint("CENTER")
	text:SetAlpha(0)
	frame.HitText = text
	frame.HitFade = FadeGroup(text, 0.6, 0.6)

	local flash = Box.Outline(frame.Content, nil, 2, 9)
	flash:SetAlpha(0)
	frame.CombatFlash = flash
	frame.CombatFlashFade = FadeGroup(flash, 0.2, 1)
end

function CombatFeedback.Configure(frame)
	local general = ns.db.general
	frame.showHits = general.hitIndicators and frame.spec.hitIndicators ~= false
	frame.showFlash = general.combatFlash
end

function CombatFeedback.Disable(frame)
	frame.HitText:SetAlpha(0)
	frame.CombatFlash:SetAlpha(0)
end

-- UNIT_COMBAT: unit, action ("WOUND", "HEAL", "DODGE"...), flags ("CRITICAL"...), amount, school
function CombatFeedback.OnUnitEvent(frame, event, _, action, flags, amount)
	if event ~= "UNIT_COMBAT" or issecretvalue(action) then
		return
	end
	local color = COLORS[action]
	if frame.showFlash and (action == "WOUND" or action == "HEAL") then
		frame.CombatFlash:SetColor(color[1], color[2], color[3])
		frame.CombatFlashFade:Stop()
		frame.CombatFlashFade:Play()
	end
	if not frame.showHits then
		return
	end
	local text = frame.HitText
	if color and amount then
		text:SetText(AbbreviateNumbers(amount))
		text:SetTextColor(color[1], color[2], color[3])
		local critical = not issecretvalue(flags) and flags == "CRITICAL"
		text:SetFontObject(critical and "NumberFontNormalHuge" or frame.hitFont)
	else
		-- Misses, dodges and the like use the game's own words.
		text:SetText(_G[action] or action)
		text:SetTextColor(1, 1, 1)
		text:SetFontObject(frame.hitFont)
	end
	frame.HitFade:Stop()
	frame.HitFade:Play()
end

function CombatFeedback.Update()
end
