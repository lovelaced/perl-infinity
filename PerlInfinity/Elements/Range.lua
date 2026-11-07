-- Fades frames when the unit is out of range.
--
-- Two modes:
--   Automatic  one of your own spells decides: a heal or buff for friends,
--              an attack for enemies. Spell range checks aren't secret.
--   40 yards   the game's group range check, for party and raid members.
--              Its answer is secret, so it's applied with SetAlphaFromBoolean.
--
-- Range changes without any event as people move, so frames with range
-- fading are checked on a light ticker (twice a second, visible frames only).
-- Group members also update right away on UNIT_IN_RANGE_UPDATE.
local _, ns = ...

local Spells = ns.Spells

local UnitInRange, UnitCanAssist, UnitCanAttack = UnitInRange, UnitCanAssist, UnitCanAttack
local IsSpellInRange = C_Spell.IsSpellInRange
local issecretvalue = issecretvalue

local Range = ns.Element("Range", {
	unitEvents = { "UNIT_IN_RANGE_UPDATE" },
})

local INTERVAL = 0.5
local frames = {}
local ticker
local friendSpell, enemySpell

local function IsGroupUnit(unit)
	return unit:match("^party%d$") ~= nil or unit:match("^raid%d+$") ~= nil
end

local function LearnSpells()
	local _, class = UnitClass("player")
	local spells = Spells.range[class] or {}
	friendSpell = Spells.FirstKnown(spells.friend)
	enemySpell = Spells.FirstKnown(spells.enemy)
end

-- Sets how faded the frame is. `inRange` may be a secret boolean.
local function Apply(frame, inRange)
	local region = frame.rangeRegion
	local faded = ns.db.range.alpha
	local hand = frame.RangeHand
	if inRange == nil then
		region:SetAlpha(1)
		if hand then
			hand:SetAlpha(0)
		end
		return
	end
	region:SetAlphaFromBoolean(inRange, 1, faded)
	if hand then
		hand:SetAlphaFromBoolean(inRange, 0, 1)
	end
end

local function Check(frame)
	local unit = frame.unit
	if not unit or unit == "player" then
		return Apply(frame, nil)
	end
	if ns.db.range.mode == "auto" then
		local spell
		if UnitCanAssist("player", unit) then
			spell = friendSpell
		elseif UnitCanAttack("player", unit) then
			spell = enemySpell
		end
		if spell then
			local inRange = IsSpellInRange(spell, unit)
			if inRange ~= nil or issecretvalue(inRange) then
				return Apply(frame, inRange)
			end
		end
	end
	if IsGroupUnit(unit) then
		return Apply(frame, (UnitInRange(unit)))
	end
	Apply(frame, nil)
end

local function Tick()
	for frame in pairs(frames) do
		if frame:IsVisible() then
			Check(frame)
		end
	end
end
Range.Tick = Tick

local function TickSafely()
	ns.Call(Tick)
end

local function Track(frame, on)
	if on and not frames[frame] then
		frames[frame] = true
		if not ticker then
			ticker = C_Timer.NewTicker(INTERVAL, TickSafely)
		end
	elseif not on and frames[frame] then
		frames[frame] = nil
		if not next(frames) and ticker then
			ticker:Cancel()
			ticker = nil
		end
	end
end

function Range.Enabled(frame)
	return ns.db.range.enabled and frame.kind ~= "player"
end

function Range.Create(frame)
	if frame.spec.rangeHand then
		local hand = frame.Overlay:CreateTexture(nil, "OVERLAY")
		hand:SetTexture(ns.Media.RANGE_HAND)
		hand:SetSize(32, 13)
		hand:SetPoint("BOTTOM", frame.NameBox, "TOP", 0, -4)
		hand:SetAlpha(0)
		frame.RangeHand = hand
	end
	if not friendSpell and not enemySpell then
		LearnSpells()
	end
end

function Range.Configure(frame)
	local part = ns.db.range.part
	frame.Content:SetAlpha(1)
	frame.NameBox:SetAlpha(1)
	frame.StatsBox:SetAlpha(1)
	if part == "name" then
		frame.rangeRegion = frame.NameBox
	elseif part == "bars" then
		frame.rangeRegion = frame.StatsBox
	else
		frame.rangeRegion = frame.Content
	end
	if frame.RangeHand then
		frame.RangeHand:SetShown(ns.db.range.icon)
	end
	if not frame.preview and frame:IsShown() then
		Track(frame, true)
	end
end

-- Only visible frames are checked, so the ticker stops when nothing shows.
function Range.Shown(frame, shown)
	Track(frame, shown)
end

function Range.Disable(frame)
	Track(frame, false)
	if frame.rangeRegion then
		frame.rangeRegion:SetAlpha(1)
	end
	if frame.RangeHand then
		frame.RangeHand:SetAlpha(0)
	end
end

function Range.Update(frame)
	Check(frame)
end

function Range.Preview(frame, sample)
	frame.rangeRegion:SetAlpha(sample.outOfRange and ns.db.range.alpha or 1)
	if frame.RangeHand then
		frame.RangeHand:SetAlpha(sample.outOfRange and 1 or 0)
	end
end

-- Learn which spells to use when the spellbook changes.
local Watcher = ns:NewModule("RangeSpells")
function Watcher:Login()
	LearnSpells()
	ns.Events:On("SPELLS_CHANGED", self, LearnSpells)
end

function Range.IsTicking()
	return ticker ~= nil
end
