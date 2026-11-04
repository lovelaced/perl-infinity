-- Snapping in Edit Mode, the way Blizzard's own frames snap. When Edit Mode's
-- "Snap" option is on, a dragged Perl Infinity frame snaps, within 8 pixels:
--   to the screen's edges and center
--   to grid lines, while the grid shows
--   edge to edge with frames beside it, lining up their corners if close
-- Red lines show the snap while you drag, and it happens when you let go.
--
-- Blizzard's snapping code keeps shared state that Edit Mode's protected
-- frames rely on, and writing to it from an addon would taint them. So
-- Perl Infinity only reads from it (the Snap option, the grid lines, which frames
-- are on screen) and does its own math and drawing.
local _, ns = ...

local Snap = {}
ns.Snap = Snap

local RANGE = 8 -- screen pixels, the same as Blizzard's
local LINE_PIXELS = 1.5

---------------------------------------------------------------------------
-- The math (pure; see tests). Rects are { l, r, b, t } in UIParent units.
---------------------------------------------------------------------------

local function Consider(best, distance, delta, at, frame)
	if distance <= best.range and (not best.distance or distance < best.distance) then
		best.distance, best.delta, best.at, best.frame = distance, delta, at, frame
	end
end

-- One axis: low/high are the rect's edges on that axis (left/right or
-- bottom/top), size is the screen's size along it, lines are grid lines.
local function Axis(low, high, size, lines, frames, rect, range, horizontal)
	local best = { range = range }
	local center = (low + high) / 2
	local middle = size / 2
	-- Screen edges and center.
	Consider(best, math.abs(low), -low, 0)
	Consider(best, math.abs(size - high), size - high, size)
	Consider(best, math.abs(middle - center), middle - center, middle)
	Consider(best, math.abs(middle - low), middle - low, middle)
	Consider(best, math.abs(middle - high), middle - high, middle)
	-- Grid lines.
	for _, at in ipairs(lines) do
		Consider(best, math.abs(at - low), at - low, at)
		Consider(best, math.abs(at - high), at - high, at)
		Consider(best, math.abs(at - center), at - center, at)
	end
	-- Neighbors: only frames level with this one, and only edge to edge.
	for _, f in ipairs(frames) do
		local fLow, fHigh, oLow, oHigh
		if horizontal then
			fLow, fHigh, oLow, oHigh = f.l, f.r, f.b, f.t
		else
			fLow, fHigh, oLow, oHigh = f.b, f.t, f.l, f.r
		end
		local otherLow, otherHigh
		if horizontal then
			otherLow, otherHigh = rect.b, rect.t
		else
			otherLow, otherHigh = rect.l, rect.r
		end
		if otherLow < oHigh and otherHigh > oLow then
			if fHigh <= low then
				Consider(best, low - fHigh, fHigh - low, fHigh, f)
			elseif fLow >= high then
				Consider(best, fLow - high, fLow - high, fLow, f)
			end
		end
	end
	return best.distance and best or nil
end

-- Lines up the other axis with the neighbor we snapped to, when its matching
-- edge is close: Blizzard's corner snap.
local function Corner(rect, frame, range, horizontal)
	local a, b, fa, fb
	if horizontal then
		a, b, fa, fb = rect.b, rect.t, frame.b, frame.t
	else
		a, b, fa, fb = rect.l, rect.r, frame.l, frame.r
	end
	local best = { range = range }
	Consider(best, math.abs(fa - a), fa - a, fa)
	Consider(best, math.abs(fb - b), fb - b, fb)
	return best.distance and best or nil
end

-- Where `rect` should move to snap. Returns dx, dy and the lines to draw
-- ({ vertical = true, at = x } or { vertical = false, at = y }).
-- world = { width, height, gridX = {...}, gridY = {...}, frames = { rects } }
function Snap.Find(rect, world, range)
	local x = Axis(rect.l, rect.r, world.width, world.gridX or {}, world.frames or {}, rect, range, true)
	local y = Axis(rect.b, rect.t, world.height, world.gridY or {}, world.frames or {}, rect, range, false)
	local lines = {}
	local dx, dy = 0, 0
	local function UseX(snap)
		dx = snap.delta
		lines[#lines + 1] = { vertical = true, at = snap.at }
	end
	local function UseY(snap)
		dy = snap.delta
		lines[#lines + 1] = { vertical = false, at = snap.at }
	end

	-- A neighbor wins with its corner lined up, if that's close.
	local neighbor = (x and x.frame) and x or ((y and y.frame) and y or nil)
	if x and y and x.frame and y.frame then
		neighbor = x.distance <= y.distance and x or y
	end
	if neighbor then
		local horizontal = neighbor == x
		local corner = Corner(rect, neighbor.frame, range, horizontal)
		if corner then
			if horizontal then
				UseX(x)
				UseY(corner)
			else
				UseY(y)
				UseX(corner)
			end
			return dx, dy, lines
		end
	end

	if x and y and not x.frame and not y.frame then
		-- Screen and grid snaps apply on both axes at once.
		UseX(x)
		UseY(y)
	elseif x and (not y or x.distance < y.distance) then
		UseX(x)
	elseif y then
		UseY(y)
	end
	return dx, dy, lines
end

---------------------------------------------------------------------------
-- Reading the screen
---------------------------------------------------------------------------

local function RectOf(region)
	local left, bottom, width, height = region:GetRect()
	if not left then
		return nil
	end
	local s = region:GetEffectiveScale() / UIParent:GetEffectiveScale() -- lint: allow L10 (scales are never 0)
	return { l = left * s, r = (left + width) * s, b = bottom * s, t = (bottom + height) * s }
end

local function SnapEnabled()
	return EditModeManagerFrame and EditModeManagerFrame.IsSnapEnabled and EditModeManagerFrame:IsSnapEnabled()
end

local function GridLines()
	local gridX, gridY = {}, {}
	local manager = EditModeMagnetismManager
	local lines = manager and manager.magneticGridLines
	if lines then
		for _, at in pairs(lines.vertical or {}) do
			gridX[#gridX + 1] = at
		end
		for _, at in pairs(lines.horizontal or {}) do
			gridY[#gridY + 1] = at
		end
	end
	return gridX, gridY
end

-- Frames on screen in Edit Mode, other than the one being dragged: Blizzard's
-- (as it lists them for its own snapping) and every LibEditMode frame.
local function Neighbors(dragged)
	local frames = {}
	local manager = EditModeMagnetismManager
	if manager and manager.magneticFrames then
		for frame in pairs(manager.magneticFrames) do
			if frame:IsVisible() then
				frames[#frames + 1] = RectOf(frame.Selection or frame)
			end
		end
	end
	for frame, selection in pairs(ns.LibEditMode.frameSelections or {}) do
		if frame ~= dragged and selection:IsVisible() then
			frames[#frames + 1] = RectOf(selection)
		end
	end
	return frames
end

local function World(dragged)
	local width, height = UIParent:GetSize()
	local gridX, gridY = GridLines()
	return { width = width, height = height, gridX = gridX, gridY = gridY, frames = Neighbors(dragged) }
end

local function Range()
	return RANGE / UIParent:GetEffectiveScale() -- lint: allow L10 (scales are never 0)
end

---------------------------------------------------------------------------
-- Preview lines
---------------------------------------------------------------------------

local overlay
local lines = {}

local function Overlay()
	if not overlay then
		overlay = CreateFrame("Frame", nil, UIParent)
		overlay:SetAllPoints()
		overlay:SetFrameStrata("FULLSCREEN_DIALOG")
		overlay:Hide()
	end
	return overlay
end

local function HideLines()
	for _, line in ipairs(lines) do
		line:Hide()
	end
end

local function ShowLines(list)
	local parent = Overlay()
	local thickness = PixelUtil and PixelUtil.GetNearestPixelSize(LINE_PIXELS, parent:GetEffectiveScale(), 1) or 1
	HideLines()
	for i, info in ipairs(list) do
		local line = lines[i]
		if not line then
			line = parent:CreateLine(nil, "OVERLAY")
			line:SetColorTexture(1, 0, 0, 1)
			lines[i] = line
		end
		line:SetThickness(thickness)
		if info.vertical then
			line:SetStartPoint("BOTTOMLEFT", parent, info.at, 0)
			line:SetEndPoint("TOPLEFT", parent, info.at, 0)
		else
			line:SetStartPoint("BOTTOMLEFT", parent, 0, info.at)
			line:SetEndPoint("BOTTOMRIGHT", parent, 0, info.at)
		end
		line:Show()
	end
	parent:Show()
end

---------------------------------------------------------------------------
-- Dragging
---------------------------------------------------------------------------

-- Runs only while a frame is being dragged.
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self)
	local selection = self.selection
	if not selection or InCombatLockdown() or not SnapEnabled() then
		self:Hide()
		if overlay then
			overlay:Hide()
		end
		return
	end
	local rect = RectOf(selection)
	if rect then
		local _, _, list = Snap.Find(rect, World(selection.parent), Range())
		ShowLines(list)
	end
end)

local function StopPreview()
	driver.selection = nil
	driver:Hide()
	HideLines()
	if overlay then
		overlay:Hide()
	end
end

-- Hooks a mover's Edit Mode handle. `saved(mover, point, x, y)` stores the
-- snapped position the same way a plain drag does.
function Snap.Attach(mover, saved)
	local selection = ns.LibEditMode.frameSelections and ns.LibEditMode.frameSelections[mover]
	if not selection or selection.perlInfinitySnap then
		return
	end
	selection.perlInfinitySnap = true
	selection:HookScript("OnDragStart", function(self)
		if InCombatLockdown() or not SnapEnabled() then
			return
		end
		driver.selection = self
		driver:Show()
	end)
	-- Runs after LibEditMode has saved the plain drop position.
	selection:HookScript("OnDragStop", function(self)
		StopPreview()
		if InCombatLockdown() or not SnapEnabled() then
			return
		end
		local rect = RectOf(self)
		if not rect then
			return
		end
		local dx, dy = Snap.Find(rect, World(mover), Range())
		if dx == 0 and dy == 0 then
			return
		end
		local point, _, _, x, y = mover:GetPoint(1)
		if not point then
			return
		end
		-- Offsets are in the mover's own scale.
		local s = mover:GetScale()
		x, y = x + dx / s, y + dy / s -- lint: allow L10 (scales are never 0)
		mover:ClearAllPoints()
		mover:SetPoint(point, UIParent, point, x, y)
		saved(mover, point, x, y)
	end)
end
