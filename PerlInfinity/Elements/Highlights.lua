-- Status glows on party and raid frames, the X-Perl way:
--   blue    one of your heals over time is on them (flashes near the end)
--   purple  your Power Word: Shield is on them
--   red     an enemy is attacking them (aggro)
--   gold    they're your target
-- plus thin bars counting down your heals over time, and on raid frames the
-- most important boss debuff as a big icon in the middle.
--
-- Z-Perl drove these from the combat log, which addons can't read on
-- Forever. Here the glows hang off aura "slots" in the frame's aura
-- container, so the game decides when they show without us reading auras.
local _, ns = ...

local AuraHost, Box, Media, Spells = ns.AuraHost, ns.Box, ns.Media, ns.Spells

local UnitThreatSituation, UnitIsUnit = UnitThreatSituation, UnitIsUnit

local Highlights = ns.Element("Highlights", {
	unitEvents = { "UNIT_THREAT_SITUATION_UPDATE" },
	events = { "PLAYER_TARGET_CHANGED" },
})

local HOT_R, HOT_G, HOT_B = 0.25, 0.55, 1
local SHIELD_R, SHIELD_G, SHIELD_B = 0.75, 0.35, 1

function Highlights.Enabled(frame)
	if not frame.spec.group or frame.preview then
		return false
	end
	local h = ns.db.highlight
	local boss = frame.spec.layout == "Raid" and frame:Conf().bossDebuff
	return h.hots or h.hotBars or h.shields or h.aggro or h.target or boss
end

-- A soft colored wash across the frame, shown by the game while the slot's
-- aura is present. Its pandemic animation (the last stretch of the aura)
-- makes it pulse, like X-Perl's flash in the final seconds.
local function GlowInitializer(frame, r, g, b)
	return function(button)
		button:EnableMouse(false)
		button:SetMouseMotionEnabled(false)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", frame.NameBox, "TOPLEFT", 3, -3)
		button:SetPoint("BOTTOMRIGHT", frame.StatsBox, "BOTTOMRIGHT", -3, 3)
		local glow = button:CreateTexture(nil, "ARTWORK")
		glow:SetTexture(Media.WHITE)
		glow:SetBlendMode("ADD")
		glow:SetVertexColor(r, g, b, 0.22)
		glow:SetAllPoints()
		local pulse = glow:CreateAnimationGroup()
		pulse:SetLooping("BOUNCE")
		local fade = pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.3)
		fade:SetDuration(0.4)
		button:AddPandemicActiveAnimation(pulse)
	end
end

-- Thin bars along the top of the health bar, one per heal over time.
local function HotBarInitializer(frame)
	return function(button)
		button:SetSize(frame.Health:GetWidth(), 2)
		button:EnableMouse(false)
		button:SetMouseMotionEnabled(false)
		local bar = CreateFrame("StatusBar", nil, button)
		bar:SetAllPoints()
		bar:SetStatusBarTexture(Media.WHITE)
		bar:SetStatusBarColor(1, 0.82, 0, 0.9)
		button:SetDurationBar(bar)
	end
end

local function BossInitializer(frame)
	return function(button)
		button:EnableMouse(false)
		button:SetMouseMotionEnabled(false)
		button:ClearAllPoints()
		button:SetPoint("CENTER", frame.StatsBox, "CENTER", 0, 0)
		button:SetSize(18, 18)
		local icon = button:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		button:SetIcon(icon)
	end
end

function Highlights.Create(frame)
	frame.hotGlowInit = GlowInitializer(frame, HOT_R, HOT_G, HOT_B)
	frame.shieldGlowInit = GlowInitializer(frame, SHIELD_R, SHIELD_G, SHIELD_B)
	frame.hotBarInit = HotBarInitializer(frame)
	frame.bossInit = BossInitializer(frame)

	frame.AggroOutline = Box.Outline(frame.Content, nil, 2, 6)
	frame.AggroOutline:SetColor(1, 0.1, 0.1)
	frame.AggroOutline:SetAlpha(0)

	frame.TargetOutline = Box.Outline(frame.Content, nil, 1, 7)
	frame.TargetOutline:SetColor(1, 0.82, 0.2)
	frame.TargetOutline:SetAlpha(0)
end

local HOT_SET, SHIELD_SET

local function SetSlot(container, key, filter, init, candidates, on)
	if on then
		if AuraHost.EnsureSlot(container, key, filter, init, candidates) then
			container:SetAuraSlotEnabled(key, true)
		end
	elseif container.slots[key] then
		container:SetAuraSlotEnabled(key, false)
	end
end

function Highlights.Configure(frame, conf)
	HOT_SET = HOT_SET or { includeSpellIDs = Spells.Set(Spells.hots) }
	SHIELD_SET = SHIELD_SET or { includeSpellIDs = Spells.Set(Spells.shields) }
	local h = ns.db.highlight

	local glows = AuraHost.Get(frame)
	if glows then
		SetSlot(glows, "hots", "HELPFUL|PLAYER", frame.hotGlowInit, HOT_SET, h.hots)
		SetSlot(glows, "shields", "HELPFUL|PLAYER", frame.shieldGlowInit, SHIELD_SET, h.shields)
		local boss = frame.spec.layout == "Raid" and conf.bossDebuff
		SetSlot(glows, "boss", "HARMFUL", frame.bossInit, { isBossAura = true }, boss)
		if boss and glows.slots.boss then
			local button = glows:GetAuraSlotFrame("boss")
			if button and not InCombatLockdown() and not C_Secrets.ShouldAurasBeSecret() then
				button:SetAlpha(conf.bossDebuffAlpha)
			end
		end
	end

	if h.hotBars then
		local bars = AuraHost.Get(frame, "hotBars")
		if bars and AuraHost.EnsureGroup(bars, "hotBars", "HELPFUL|PLAYER", frame.hotBarInit) then
			bars:ClearAllPoints()
			bars:SetPoint("TOPLEFT", frame.Health, "TOPLEFT", 0, 0)
			bars:SetFlowLayoutAnchorPoint("TOPLEFT")
			bars:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
			bars:SetAuraGroupCandidateFilters("hotBars", HOT_SET)
			bars:SetAuraGroupMaxFrameCount("hotBars", 3)
			bars:SetEnabled(true)
			ns.Combat:RunAuraSafe(bars, function()
				local width = frame.Health:GetWidth()
				bars:SetAuraGroupLayout("hotBars", {
					elementWidth = width,
					elementHeight = 2,
					elementSpacing = 0,
					lineSpacing = 1,
				})
				-- The layout only sets the room each bar takes up, not its size.
				for i = 1, bars:GetAuraGroupFrameCount("hotBars") do
					bars:GetAuraGroupFrame("hotBars", i):SetSize(width, 2)
				end
			end)
		end
	elseif frame.AuraContainers and frame.AuraContainers.hotBars then
		frame.AuraContainers.hotBars:SetAuraGroupMaxFrameCount("hotBars", 0)
	end

	frame.showAggro = h.aggro
	frame.showTargetOutline = h.target
	frame.AggroOutline:SetAlpha(0)
	frame.TargetOutline:SetAlpha(0)
end

function Highlights.Disable(frame)
	local glows = frame.AuraContainers and frame.AuraContainers.icons
	if glows then
		for _, key in ipairs({ "hots", "shields", "boss" }) do
			if glows.slots[key] then
				glows:SetAuraSlotEnabled(key, false)
			end
		end
	end
	frame.AggroOutline:SetAlpha(0)
	frame.TargetOutline:SetAlpha(0)
end

function Highlights.Update(frame, unit)
	if frame.showAggro then
		-- 2 and 3 mean the unit has aggro. A secret status can't be compared,
		-- so the outline stays off rather than guessing.
		local status = UnitThreatSituation(unit)
		if status and not issecretvalue(status) and status >= 2 then
			frame.AggroOutline:SetAlpha(1)
		else
			frame.AggroOutline:SetAlpha(0)
		end
	end
	if frame.showTargetOutline then
		ns.Secret.ShowIf(frame.TargetOutline, UnitIsUnit("target", unit))
	end
end
