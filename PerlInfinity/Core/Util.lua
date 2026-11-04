-- Small pure helpers shared across the addon. Nothing here touches the game.
local _, ns = ...

local Util = {}
ns.Util = Util

local type, pairs, next = type, pairs, next

function Util.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = Util.DeepCopy(entry)
	end
	return copy
end

-- Copies every key from `source` into `target`, recursing into tables.
function Util.DeepMerge(target, source)
	for key, value in pairs(source) do
		if type(value) == "table" and type(target[key]) == "table" then
			Util.DeepMerge(target[key], value)
		else
			target[key] = Util.DeepCopy(value)
		end
	end
	return target
end

function Util.DeepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in pairs(a) do
		if not Util.DeepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

-- Removes empty tables left behind after pruning a sparse profile.
function Util.Prune(tbl)
	for key, value in pairs(tbl) do
		if type(value) == "table" then
			Util.Prune(value)
			if next(value) == nil then
				tbl[key] = nil
			end
		end
	end
end

-- "party.buffs.size" -> { "party", "buffs", "size" }, cached.
local pathCache = {}
function Util.SplitPath(path)
	local parts = pathCache[path]
	if not parts then
		parts = {}
		for part in path:gmatch("[^%.]+") do
			parts[#parts + 1] = tonumber(part) or part
		end
		pathCache[path] = parts
	end
	return parts
end

function Util.GetPath(tbl, path)
	local parts = Util.SplitPath(path)
	for i = 1, #parts do
		if type(tbl) ~= "table" then
			return nil
		end
		tbl = tbl[parts[i]]
	end
	return tbl
end

-- Sets a value at `path`, creating tables on the way.
function Util.SetPath(tbl, path, value)
	local parts = Util.SplitPath(path)
	for i = 1, #parts - 1 do
		local key = parts[i]
		if type(tbl[key]) ~= "table" then
			tbl[key] = {}
		end
		tbl = tbl[key]
	end
	tbl[parts[#parts]] = value
end

function Util.Clamp(value, low, high)
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

-- value / maximum for plain numbers, 0 when there's no maximum. The game
-- raises an error on division by zero, so every ratio of two settings or
-- sample numbers goes through here.
function Util.Fraction(value, maximum)
	if not maximum or maximum <= 0 then
		return 0
	end
	return (value or 0) / maximum -- lint: allow L10
end

-- Bit helpers for multi-select settings (bit 1 = first choice).
function Util.HasBit(mask, index)
	return bit.band(mask, bit.lshift(1, index - 1)) ~= 0
end

function Util.SetBit(mask, index, on)
	local flag = bit.lshift(1, index - 1)
	if on then
		return bit.bor(mask, flag)
	end
	return bit.band(mask, bit.bnot(flag))
end

function Util.HexToColor(hex)
	return CreateColorFromHexString(hex)
end
