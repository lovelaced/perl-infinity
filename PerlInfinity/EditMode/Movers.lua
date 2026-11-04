-- Moving frames in Edit Mode.
--
-- Every movable Perl Infinity frame sits inside a plain "mover" frame registered with
-- LibEditMode, so it shows up in the game's Edit Mode beside Blizzard's own
-- frames: drag it, nudge it with the arrow keys, open its little settings
-- popup. Positions are saved per Edit Mode layout in PerlInfinityDB.positions,
-- outside profiles, so switching profiles never moves anything.
--
-- While Edit Mode is open, frames that have nothing to show (no target, not
-- in a group) display a sample so there's something to grab.
local _, ns = ...

local Movers = ns:NewModule("Movers")
local Combat = ns.Combat
local L = ns.L

local movers = {}
local LEM = ns.LibEditMode
local FALLBACK_LAYOUT = "Modern"

-- Edit Mode names, shown on the selection box and in its popup.
local NAMES = {
	player = L.EM_PLAYER,
	pet = L.EM_PET,
	pettarget = L.EM_PET_TARGET,
	target = L.EM_TARGET,
	targettarget = L.EM_TOT,
	targettargettarget = L.EM_TOTOT,
	focus = L.EM_FOCUS,
	focustarget = L.EM_FOCUS_TARGET,
	party = L.EM_PARTY,
	raid = L.EM_RAID,
	raidpets = L.EM_RAID_PETS,
	tanks = L.EM_TANKS,
	healers = L.EM_HEALERS,
	layouts = L.EM_LAYOUTS,
	aggro = L.EM_AGGRO,
}

local function LayoutName()
	return (LEM.GetActiveLayoutName and LEM:GetActiveLayoutName()) or PerlInfinityDB.global.lastLayout or FALLBACK_LAYOUT
end

local function SavedPosition(key)
	local layout = PerlInfinityDB.positions[LayoutName()]
	return (layout and layout[key]) or ns.DefaultPositions[key]
end

local function Place(mover)
	local position = SavedPosition(mover.key)
	if not position then
		return
	end
	mover:ClearAllPoints()
	mover:SetPoint(position.point, UIParent, position.point, position.x, position.y)
end

local function ApplyScale(mover)
	local spec = ns.Frames.specs[mover.key]
	if spec and spec.scale then
		mover:SetScale(spec.scale())
	end
end

-- The mover for `key`, made on first use.
function Movers:Get(key)
	local mover = movers[key]
	if mover then
		return mover
	end
	mover = CreateFrame("Frame", "PerlInfinity_Mover_" .. key, UIParent)
	mover.key = key
	mover:SetSize(100, 40)
	mover:SetClampedToScreen(true)
	if mover.SetDontSavePosition then
		mover:SetDontSavePosition(true)
	end
	movers[key] = mover
	Place(mover)
	ApplyScale(mover)
	if self.registered then
		self:Register(mover)
	end
	return mover
end

function Movers:SetSize(key, width, height)
	local mover = self:Get(key)
	Combat:Run(Combat:Key(mover, "size"), function()
		mover:SetSize(width, height)
	end)
end

-- Sizes a single frame's mover to the frame.
function Movers:Fit(key, frame)
	local rects = frame.rects
	if rects then
		self:SetSize(key, rects.width, rects.height)
	end
	local mover = self:Get(key)
	Combat:Run(Combat:Key(mover, "scale"), ApplyScale, mover)
end

function Movers:SetEnabled(key, enabled)
	local mover = self:Get(key)
	Combat:Run(Combat:Key(mover, "shown"), function()
		mover:SetShown(enabled)
	end)
end

function Movers:ApplyAll()
	Combat:Run(Combat:Key(self, "applyAll"), function()
		for _, mover in pairs(movers) do
			Place(mover)
			ApplyScale(mover)
		end
	end)
end

-- Puts every frame back where it starts in the current Edit Mode layout.
function Movers:ResetAll()
	PerlInfinityDB.positions[LayoutName()] = nil
	self:ApplyAll()
end

---------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------

local function OnMoved(mover, layoutName, point, x, y)
	layoutName = layoutName or LayoutName()
	local positions = PerlInfinityDB.positions
	positions[layoutName] = positions[layoutName] or {}
	positions[layoutName][mover.key] = { point = point, x = x, y = y }
end

function Movers:Register(mover)
	if mover.registered then
		return
	end
	mover.registered = true
	local default = ns.DefaultPositions[mover.key] or { point = "CENTER", x = 0, y = 0 }
	LEM:AddFrame(mover, OnMoved, default, NAMES[mover.key] or mover.key)
	ns.Snap.Attach(mover, function(frame, point, x, y)
		OnMoved(frame, nil, point, x, y)
	end)
	ns.QuickSettings:Attach(mover)
end

-- Shows samples in empty frames while Edit Mode is open.
local function ShowPlaceholders(show)
	for key, mover in pairs(movers) do
		ns.Call(ns.Placeholders.Set, ns.Placeholders, key, mover, show)
	end
end

---------------------------------------------------------------------------
-- Frames that ride along outside a mover
---------------------------------------------------------------------------

-- LibEditMode's handle covers the mover and nothing else. A party member's pet
-- and target, and attached raid pets, sit past that edge, so a click on one
-- reached the real button instead of Edit Mode. The handle grows to take them
-- in. Only the handle grows: the mover, and so the saved position, stays put.
--
-- It never shrinks while Edit Mode is open. Party targets come and go all the
-- time, and a box that followed them would jitter under your mouse.

-- `riders()` returns the frames hanging off this mover, or nil.
function Movers:SetRiders(key, riders)
	self:Get(key).riders = riders
end

local function EdgesIn(mover, region)
	local left, bottom, width, height = region:GetRect()
	if not left or issecretvalue(left) then
		return nil
	end
	local s = region:GetEffectiveScale() / mover:GetEffectiveScale() -- lint: allow L10 (scales are never 0)
	return left * s, (left + width) * s, bottom * s, (bottom + height) * s
end

local function FitHandle(mover)
	local handle = LEM.frameSelections and LEM.frameSelections[mover]
	local riders = mover.riders and mover.riders()
	if not handle or not riders then
		return
	end
	local left, right, bottom, top = EdgesIn(mover, mover)
	if not left then
		return
	end
	local grown = mover.handleGrowth
	local changed = not grown
	grown = grown or { left = 0, right = 0, bottom = 0, top = 0 }
	for _, rider in ipairs(riders) do
		if rider:IsVisible() then
			local l, r, b, t = EdgesIn(mover, rider)
			if l then
				local newLeft, newRight = math.min(grown.left, l - left), math.max(grown.right, r - right)
				local newBottom, newTop = math.min(grown.bottom, b - bottom), math.max(grown.top, t - top)
				if newLeft ~= grown.left or newRight ~= grown.right or newBottom ~= grown.bottom or newTop ~= grown.top then
					changed = true
					grown.left, grown.right, grown.bottom, grown.top = newLeft, newRight, newBottom, newTop
				end
			end
		end
	end
	mover.handleGrowth = grown
	if changed then
		handle:ClearAllPoints()
		handle:SetPoint("TOPLEFT", mover, "TOPLEFT", grown.left, grown.top)
		handle:SetPoint("BOTTOMRIGHT", mover, "BOTTOMRIGHT", grown.right, grown.bottom)
	end
end

local fitter = { queued = false }
function fitter:Flush()
	for _, mover in pairs(movers) do
		ns.Call(FitHandle, mover)
	end
end

-- A unit frame just appeared. Costs one check when Edit Mode is closed.
function Movers:FrameShown()
	if self.editing then
		ns.Scheduler:Queue(fitter)
	end
end

-- A setting moved or resized what hangs off this mover, so measure afresh.
function Movers:RefitHandle(key)
	local mover = movers[key]
	if mover and self.editing then
		mover.handleGrowth = nil
		ns.Scheduler:Queue(fitter)
	end
end

function Movers:Login()
	PerlInfinityDB.positions = PerlInfinityDB.positions or {}
	self.registered = true
	for _, mover in pairs(movers) do
		self:Register(mover)
	end

	LEM:RegisterCallback("layout", function(layoutName)
		PerlInfinityDB.global.lastLayout = layoutName
		Movers:ApplyAll()
	end)
	LEM:RegisterCallback("enter", function()
		Movers.editing = true
		ShowPlaceholders(true)
		for _, mover in pairs(movers) do
			mover.handleGrowth = nil
		end
		fitter:Flush()
	end)
	LEM:RegisterCallback("exit", function()
		Movers.editing = false
		ShowPlaceholders(false)
	end)
	LEM:RegisterCallback("create", function(layoutName, _, sourceName)
		local positions = PerlInfinityDB.positions
		if sourceName and positions[sourceName] then
			positions[layoutName] = ns.Util.DeepCopy(positions[sourceName])
		end
	end)
	LEM:RegisterCallback("rename", function(oldName, newName)
		local positions = PerlInfinityDB.positions
		positions[newName], positions[oldName] = positions[oldName], nil
	end)
	LEM:RegisterCallback("delete", function(layoutName)
		PerlInfinityDB.positions[layoutName] = nil
	end)
end

-- Opens the game's Edit Mode, if it can open right now.
function Movers:OpenEditMode()
	if InCombatLockdown() then
		ns.Print(L.MSG_EDITMODE_COMBAT)
		return
	end
	if EditModeManagerFrame and EditModeManagerFrame.CanEnterEditMode and not EditModeManagerFrame:CanEnterEditMode() then
		ns.Print(L.MSG_EDITMODE_UNAVAILABLE)
		return
	end
	ShowUIPanel(EditModeManagerFrame)
end
