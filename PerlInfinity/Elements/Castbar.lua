-- The X-Perl cast bar, drawn inside the name box: the name gives way to the
-- spell while someone casts.
--
-- Other people's casts are secret on Forever, so nothing here does math on
-- cast times. The bar runs on a duration object from the game
-- (SetTimerDuration), the countdown text on a duration text binding, and the
-- "can't interrupt" color and shield on SetAlphaFromBoolean, all native.
local _, ns = ...

local Media = ns.Media
local L = ns.L

local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local UnitCastingDuration, UnitChannelDuration = UnitCastingDuration, UnitChannelDuration
local EvaluateColorFromBoolean = C_CurveUtil.EvaluateColorFromBoolean
local Immediate = Enum.StatusBarInterpolation.Immediate
local ElapsedTime = Enum.StatusBarTimerDirection.ElapsedTime
local RemainingTime = Enum.StatusBarTimerDirection.RemainingTime

local Castbar = ns.Element("Castbar", {
	unitEvents = {
		"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
		"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_SUCCEEDED",
		"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
		"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
	},
})

local CAST = CreateColor(1, 0.7, 0)
local CHANNEL = CreateColor(0, 1, 0)
local LOCKED = CreateColor(0.6, 0.6, 0.6)
local FAILED_R, FAILED_G, FAILED_B = 1, 0, 0

function Castbar.Enabled(frame, conf)
	return conf.castBar ~= false and frame.spec.castBar ~= false
end

-- Gives the name box back to the name, unless the Name element hid it
-- (party "Show names" off, for example).
local function RestoreName(frame)
	frame.NameText:SetShown(frame.nameShown ~= false)
end

local function OnFadeFinished(animation)
	local frame = animation.frame
	frame.Castbar:Hide()
	RestoreName(frame)
end

local function CreateTimer(bar)
	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	bar.Time = text
	if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
		local formatter = C_StringUtil.CreateSecondsFormatter()
		formatter:SetMinInterval(Enum.SecondsFormatterInterval.Seconds)
		formatter:SetDefaultAbbreviation(Enum.SecondsFormatterAbbreviation.None)
		if formatter.SetMillisecondsThreshold then
			formatter:SetMillisecondsThreshold(10)
		end
		local binding = C_DurationUtil.CreateDurationTextBinding()
		binding:SetFontString(text)
		binding:SetFormatter(formatter)
		binding:SetUpdateInterval(0.1)
		bar.TimeBinding = binding
	end
end

function Castbar.Create(frame)
	local box = frame.NameBox
	local bar = CreateFrame("StatusBar", nil, box)
	bar:SetPoint("TOPLEFT", 4, -4)
	bar:SetPoint("BOTTOMRIGHT", -4, 4)
	bar:SetStatusBarTexture(Media.BarTexture())
	bar:SetMinMaxValues(0, 1)
	bar:Hide()

	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT", 3, 0)
	text:SetPoint("RIGHT", -3, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	bar.Text = text

	local spark = bar:CreateTexture(nil, "OVERLAY")
	spark:SetTexture(Media.SPARK)
	spark:SetBlendMode("ADD")
	spark:SetSize(20, 30)
	spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT")
	bar.Spark = spark

	-- Shown only when the cast can't be interrupted.
	local shield = bar:CreateTexture(nil, "OVERLAY")
	shield:SetAtlas("nameplates-InterruptShield")
	shield:SetSize(12, 14)
	shield:SetPoint("RIGHT", bar, "LEFT", 1, 0)
	shield:SetAlpha(0)
	bar.Shield = shield

	local latency = bar:CreateTexture(nil, "ARTWORK")
	latency:SetColorTexture(1, 0, 0, 0.4)
	latency:SetPoint("TOPRIGHT")
	latency:SetPoint("BOTTOMRIGHT")
	latency:Hide()
	bar.Latency = latency

	CreateTimer(bar)

	-- The spell name and time stay readable in front of the elite dragon.
	if frame.spec.eliteMarker then
		local front = ns.Box.TextLayer(bar, frame.Content)
		text:SetParent(front)
		bar.Time:SetParent(front)
	end

	local fade = bar:CreateAnimationGroup()
	local alpha = fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0)
	alpha:SetStartDelay(0.4)
	alpha:SetDuration(0.5)
	fade.frame = frame
	fade:SetScript("OnFinished", OnFadeFinished)
	bar.Fade = fade

	frame.Castbar = bar
end

function Castbar.Configure(frame)
	local bar = frame.Castbar
	bar:SetStatusBarTexture(Media.BarTexture())
	local where = ns.db.castBars.time
	local time = bar.Time
	time:ClearAllPoints()
	if where == "inside" then
		time:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
		bar.Text:SetPoint("RIGHT", time, "LEFT", -2, 0)
	else
		time:SetPoint("LEFT", frame.NameBox, "RIGHT", 4, 0)
		bar.Text:SetPoint("RIGHT", -3, 0)
	end
	time:SetShown(where ~= "hidden")
	frame.castLatency = frame.kind == "player" and frame:Conf().castLatency
end

function Castbar.Disable(frame)
	frame.Castbar:Hide()
	RestoreName(frame)
end

function Castbar.OnUnitEvent(frame, event)
	frame.castEvent = event
end

local function ShowLatency(bar, unit, startMs, endMs)
	-- Your own cast times are readable; anyone else's are secret.
	if unit ~= "player" or issecretvalue(startMs) or not startMs then
		bar.Latency:Hide()
		return
	end
	local _, _, home, world = GetNetStats()
	local castMs = endMs - startMs
	if castMs <= 0 then
		bar.Latency:Hide()
		return
	end
	local fraction = math.min((math.max(home, world)) / castMs, 1) -- lint: allow L10 (castMs > 0 above)
	bar.Latency:SetWidth(bar:GetWidth() * fraction)
	bar.Latency:Show()
end

local function StartCast(frame, unit, text, duration, channeling, notInterruptible, startMs, endMs)
	local bar = frame.Castbar
	bar.Fade:Stop()
	bar:SetAlpha(1)
	bar.casting = true
	frame.NameText:Hide()
	bar:Show()
	bar.Spark:Show()
	bar.Text:SetText(text)
	bar:SetTimerDuration(duration, Immediate, channeling and RemainingTime or ElapsedTime)
	-- The game can leave "can't interrupt" out; the color and shield calls
	-- need a boolean.
	if not issecretvalue(notInterruptible) and notInterruptible == nil then
		notInterruptible = false
	end
	local color = EvaluateColorFromBoolean(notInterruptible, LOCKED, channeling and CHANNEL or CAST)
	bar:SetStatusBarColor(color:GetRGB())
	bar.Shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
	if bar.TimeBinding then
		bar.TimeBinding:SetDuration(duration)
		bar.TimeBinding:SetEnabled(true)
	end
	if frame.castLatency and not channeling then
		ShowLatency(bar, unit, startMs, endMs)
	else
		bar.Latency:Hide()
	end
end

local function EndCast(frame, event)
	local bar = frame.Castbar
	if not bar.casting then
		return
	end
	bar.casting = false
	bar.Spark:Hide()
	bar.Latency:Hide()
	bar.Shield:SetAlpha(0)
	if bar.TimeBinding then
		bar.TimeBinding:SetEnabled(false)
	end
	bar.Time:SetText("")
	if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		bar:SetStatusBarColor(FAILED_R, FAILED_G, FAILED_B)
		bar.Text:SetText(event == "UNIT_SPELLCAST_INTERRUPTED" and L.CAST_INTERRUPTED or L.CAST_FAILED)
	end
	bar.Fade:Play()
end

function Castbar.Update(frame, unit)
	local event = frame.castEvent
	frame.castEvent = nil

	local name, text, _, startMs, endMs, _, _, notInterruptible = UnitCastingInfo(unit)
	if name then
		StartCast(frame, unit, text, UnitCastingDuration(unit), false, notInterruptible, startMs, endMs)
		return
	end
	local channelName, channelText, _, channelStart, channelEnd, _, channelLocked = UnitChannelInfo(unit)
	if channelName then
		StartCast(frame, unit, channelText, UnitChannelDuration(unit), true, channelLocked, channelStart, channelEnd)
		return
	end
	EndCast(frame, event)
end

function Castbar.Preview(frame, sample)
	local bar = frame.Castbar
	if not sample.cast then
		bar:Hide()
		RestoreName(frame)
		return
	end
	frame.NameText:Hide()
	bar.Fade:Stop()
	bar:SetAlpha(1)
	bar:Show()
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0.6)
	bar:SetStatusBarColor(CAST:GetRGB())
	bar.Text:SetText(sample.cast)
	bar.Time:SetText("1.2")
	bar.Shield:SetAlpha(0)
end
