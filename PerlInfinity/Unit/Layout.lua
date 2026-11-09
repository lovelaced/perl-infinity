-- Box geometry for each frame layout, from settings alone. Pure functions:
-- they return rectangles (x, y from the frame's top-left, y going down as
-- negative numbers) and never touch the game, so tests can check them.
--
-- Layouts, in X-Perl's proportions:
--   portraitLeft   [level/class] [portrait] [name over stats]   player, party, pet
--   portraitRight  [name over stats] [portrait] [level/class]   target, focus
--   small          [name][level] over [stats]                   target of target
--   raid           [name] over [stats], thin edges              raid, raid pets
local _, ns = ...

local Layout = {}
ns.Layout = Layout

local PORTRAIT = 62
local NAME_H = 24
local LEVEL_W, LEVEL_H = 27, 22
local OVERLAP = 2
local INSET = 5
local PERCENT_W = 36
local POWER_H = 10
local THIN_BAR_H = 10
local EXTRA_BAR_H = 8

-- Bars inside a stats box. `extras` is the number of extra thin bars (XP,
-- reputation, druid mana) stacked below the power bar.
function Layout.Stats(width, opts)
	local barWidth = width - INSET * 2 - (opts.percent and PERCENT_W or 0)
	local healthH = opts.thick and 18 or THIN_BAR_H
	local powerH = opts.power and POWER_H or 0
	local extras = opts.extras or 0
	local height = INSET * 2 + healthH + (opts.power and (POWER_H + 2) or 0) + extras * (EXTRA_BAR_H + 2)
	if not opts.thick then
		height = math.max(height, 40)
	end
	local stats = {
		height = height,
		health = { x = INSET, y = -INSET, w = barWidth, h = healthH },
		power = { x = INSET, y = -(INSET + healthH + 2), w = barWidth, h = powerH },
		percent = { x = INSET + barWidth, w = PERCENT_W },
		extras = {},
	}
	local y = -(INSET + healthH + (opts.power and (POWER_H + 2) or 0))
	for i = 1, extras do
		stats.extras[i] = { x = INSET, y = y - 2, w = barWidth, h = EXTRA_BAR_H }
		y = y - 2 - EXTRA_BAR_H
	end
	return stats
end

-- opts: width (name/stats width), portrait, percent, power, thick, extras,
--       portraitSize, tallPortrait
local function PortraitLayout(opts, mirrored)
	local width = opts.width
	local portrait = opts.portrait and (opts.portraitSize or PORTRAIT) or 0
	local stats = Layout.Stats(width, opts)
	local statsH = stats.height
	local rects = { stats = stats }

	local column = LEVEL_W - OVERLAP
	local leftEdge = mirrored and 0 or column
	local portraitH = portrait
	if opts.portrait and opts.tallPortrait then
		portraitH = math.max(portrait, NAME_H - OVERLAP + statsH)
	end

	if mirrored then
		rects.name = { x = 0, y = 0, w = width, h = NAME_H }
		rects.statsBox = { x = 0, y = -(NAME_H - OVERLAP), w = width, h = statsH }
		local px = width - OVERLAP
		if opts.portrait then
			rects.portrait = { x = px, y = 0, w = portrait, h = portraitH }
			px = px + portrait - OVERLAP
		end
		rects.level = { x = px, y = 0, w = LEVEL_W, h = LEVEL_H }
		rects.class = { x = px + 3, y = -(LEVEL_H + 2), w = 20, h = 20 }
		rects.right = px + LEVEL_W
	else
		rects.level = { x = 0, y = 0, w = LEVEL_W, h = LEVEL_H }
		rects.class = { x = 3, y = -(LEVEL_H + 2), w = 20, h = 20 }
		local nx = leftEdge
		if opts.portrait then
			rects.portrait = { x = leftEdge, y = 0, w = portrait, h = portraitH }
			nx = leftEdge + portrait - OVERLAP
		end
		rects.name = { x = nx, y = 0, w = width, h = NAME_H }
		rects.statsBox = { x = nx, y = -(NAME_H - OVERLAP), w = width, h = statsH }
		rects.right = nx + width
	end

	rects.height = math.max(portraitH, NAME_H - OVERLAP + statsH)
	rects.width = rects.right
	-- The clickable area: everything except the level column.
	rects.click = mirrored
		and { x = 0, y = 0, w = rects.right - LEVEL_W + OVERLAP, h = rects.height }
		or { x = leftEdge, y = 0, w = rects.right - leftEdge, h = rects.height }
	return rects
end

function Layout.PortraitLeft(opts)
	return PortraitLayout(opts, false)
end

function Layout.PortraitRight(opts)
	return PortraitLayout(opts, true)
end

-- Target of target and the other small frames: no portrait.
function Layout.Small(opts)
	local width = opts.width
	local stats = Layout.Stats(width, opts)
	local nameW = width - LEVEL_W + OVERLAP
	local rects = {
		stats = stats,
		name = { x = 0, y = 0, w = nameW, h = NAME_H },
		level = { x = nameW - OVERLAP, y = 0, w = LEVEL_W, h = NAME_H },
		statsBox = { x = 0, y = -(NAME_H - OVERLAP), w = width, h = stats.height },
	}
	rects.width = width
	rects.height = NAME_H - OVERLAP + stats.height
	rects.click = { x = 0, y = 0, w = rects.width, h = rects.height }
	return rects
end

-- Raid buttons: a slim name strip over a slim stats box. The tank and
-- healer windows pass a row height, which stretches or shrinks the health
-- bar (never below 6 pixels).
Layout.RAID_HEALTH_MIN = 6
function Layout.Raid(opts)
	local width = opts.width
	local nameH = 14
	local healthH = 12
	local manaH = opts.power and 4 or 0
	if opts.height then
		local fixed = nameH - 1 + 8 + (opts.power and (manaH + 1) or 0)
		healthH = math.max(Layout.RAID_HEALTH_MIN, opts.height - fixed)
	end
	local statsH = 4 + healthH + (opts.power and (manaH + 1) or 0) + 4
	local rects = {
		name = { x = 0, y = 0, w = width, h = nameH },
		statsBox = { x = 0, y = -(nameH - 1), w = width, h = statsH },
		stats = {
			height = statsH,
			health = { x = 4, y = -4, w = width - 8, h = healthH },
			power = { x = 4, y = -(4 + healthH + 1), w = width - 8, h = manaH },
			percent = { x = 4, w = width - 8 },
			extras = {},
		},
	}
	rects.width = width
	rects.height = nameH - 1 + statsH
	rects.click = { x = 0, y = 0, w = width, h = rects.height }
	return rects
end

Layout.SIZES = {
	PORTRAIT = PORTRAIT,
	NAME_H = NAME_H,
	LEVEL_W = LEVEL_W,
	LEVEL_H = LEVEL_H,
	OVERLAP = OVERLAP,
}
