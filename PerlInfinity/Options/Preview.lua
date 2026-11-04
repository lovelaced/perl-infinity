-- The live preview on the right side of the options window. It shows the
-- frames the current page changes, drawn by the same code as the real ones
-- but fed made-up players, so every change shows up right away.
local _, ns = ...

local Preview = {}
ns.OptionPreview = Preview

local L = ns.L
local PADDING = 14
local GAP = 18
local MIN_SCALE = 0.3

local pane, caption, holder
local current
local shown = {}
local cache = {}

local PARTY = {
	{ name = "SAMPLE_PARTY_1", class = "WARRIOR", role = "TANK", power = 40, maxPower = 100, powerToken = "RAGE", health = 5200, maxHealth = 6800, incoming = 900, leader = true, ready = "ready" },
	{ name = "SAMPLE_PARTY_2", class = "PRIEST", role = "HEALER", health = 2900, maxHealth = 3300, power = 2600, maxPower = 4200, powerToken = "MANA", ready = "ready", auras = { { spell = 1243 }, { spell = 8122, harmful = true } } },
	{ name = "SAMPLE_PARTY_3", class = "ROGUE", role = "DAMAGER", health = 2400, maxHealth = 3600, power = 80, maxPower = 100, powerToken = "ENERGY", outOfRange = true },
	{ name = "SAMPLE_PARTY_4", class = "WARLOCK", role = "DAMAGER", dead = "STATUS_DEAD", health = 0, maxHealth = 3400, power = 0, maxPower = 4000, powerToken = "MANA" },
}

local RAID = {
	{ "WARRIOR", 0.82 }, { "PRIEST", 0.95 }, { "MAGE", 0.4 }, { "ROGUE", 1 }, { "DRUID", 0.7 },
	{ "PALADIN", 0.9 }, { "HUNTER", 0.15, "outOfRange" }, { "SHAMAN", 0, "dead" }, { "WARLOCK", 0.6, "offline" }, { "WARRIOR", 1 },
}

local function PartySample(index)
	local sample = CopyTable(PARTY[index])
	sample.name = L[sample.name]
	sample.level = 60
	sample.icon = 132355
	if sample.dead then
		sample.dead = L[sample.dead]
	end
	return sample
end

local function RaidSample(index)
	local entry = RAID[index]
	local maxHealth = 4000
	local sample = {
		name = L.SAMPLE_RAID_NAMES[index] or ("Raider " .. index),
		class = entry[1],
		health = math.floor(maxHealth * entry[2]),
		maxHealth = maxHealth,
		power = 3000, maxPower = 5000,
		powerToken = ns.Classes.usesMana[entry[1]] and "MANA" or (entry[1] == "ROGUE" and "ENERGY" or "RAGE"),
		raidIcon = index == 1 and 8 or nil,
	}
	if entry[3] == "dead" then
		sample.dead = L.STATUS_DEAD
	elseif entry[3] == "offline" then
		sample.dead = L.STATUS_OFFLINE
	elseif entry[3] == "outOfRange" then
		sample.outOfRange = true
	end
	if index == 3 then
		sample.auras = { { spell = 11597, harmful = true } }
	end
	return sample
end

-- Which frames each page shows: a list of rows, each row a list of frames.
local SETS = {
	overview = { { { "player" } }, { { "target" } }, { { "party", 1 } } },
	player = { { { "player" } } },
	pet = { { { "pet" } }, { { "pettarget" } } },
	target = { { { "target" } }, { { "targettarget" } } },
	small = { { { "targettarget" } }, { { "targettargettarget" } }, { { "focustarget" } }, { { "pettarget" } } },
	focus = { { { "focus" } }, { { "focustarget" } } },
	party = { { { "party", 1 } }, { { "party", 2 } }, { { "party", 3 } }, { { "party", 4 } } },
	raid = "raid",
}

local function Frame(kind, variant)
	local key = kind .. (variant or "")
	local frame = cache[key]
	if not frame then
		frame = ns.Frames:CreatePreview(kind, holder)
		cache[key] = frame
	end
	local spec = ns.Frames.specs[kind]
	if kind == "party" and variant then
		frame.sample = PartySample(variant)
	elseif kind == "raid" and variant then
		frame.sample = RaidSample(variant)
	elseif spec.sample then
		frame.sample = spec.sample()
	end
	frame:Configure()
	frame:Show()
	return frame
end

local function Scale(frame, room)
	local spec = ns.Frames.specs[frame.kind]
	local wanted = spec.scale and spec.scale() or 1
	local width = (frame.rects and frame.rects.width or 160) + 40
	-- The pane can measure 0 wide before the window is first laid out.
	return math.max(math.min(wanted, room / width, 1.2), MIN_SCALE) -- lint: allow L10 (width >= 40)
end

local function LayoutRows(set)
	local room = pane:GetWidth() - PADDING * 2
	local y = -PADDING - 10
	for _, row in ipairs(set) do
		local entry = row[1]
		local frame = Frame(entry[1], entry[2])
		local scale = Scale(frame, room)
		frame:SetScale(scale)
		frame:ClearAllPoints()
		-- Leave room above for icons that ride on the top edge.
		y = y - 14
		frame:SetPoint("TOPLEFT", holder, "TOPLEFT", (PADDING + 6) / scale, y / scale) -- lint: allow L10 (scale >= MIN_SCALE)
		shown[#shown + 1] = frame
		local auras = frame.PreviewAuras and #frame.PreviewAuras > 0 and 30 or 0
		y = y - ((frame.rects and frame.rects.height or 60) + auras) * scale - GAP
	end
end

local function LayoutRaid()
	local room = pane:GetWidth() - PADDING * 2
	local columns, perColumn = 2, 5
	local spacing = 4
	local first = Frame("raid", 1)
	local width = first.rects.width
	local height = first.rects.height
	local scale = math.max(math.min(ns.db.raid.scale * 1.2, room / ((width + spacing) * columns + 10)), MIN_SCALE) -- lint: allow L10
	for index = 1, columns * perColumn do
		local frame = Frame("raid", index)
		frame:SetScale(scale)
		frame:ClearAllPoints()
		local column = math.floor((index - 1) / perColumn) -- lint: allow L10 (constant)
		local slot = (index - 1) % perColumn -- lint: allow L10 (constant)
		local x = PADDING + column * (width + spacing) * scale
		local y = -PADDING - 20 - slot * (height + spacing + 2) * scale
		frame:SetPoint("TOPLEFT", holder, "TOPLEFT", x / scale, y / scale) -- lint: allow L10 (scale >= MIN_SCALE)
		shown[#shown + 1] = frame
	end
end

function Preview:Attach(frame)
	pane = frame
	holder = CreateFrame("Frame", nil, pane)
	holder:SetAllPoints()
	holder:SetClipsChildren(true)

	caption = pane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	caption:SetPoint("BOTTOMLEFT", 12, 10)
	caption:SetPoint("BOTTOMRIGHT", -12, 10)
	caption:SetJustifyH("LEFT")
	caption:SetText(L.PREVIEW_CAPTION)

	local empty = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	empty:SetPoint("CENTER")
	empty:SetWidth(260)
	pane.Empty = empty
end

function Preview:Show(key)
	current = key
	for _, frame in ipairs(shown) do
		frame:Hide()
	end
	wipe(shown)
	-- Nothing to draw while the preview is tucked away.
	if not pane or not pane:IsShown() then
		return
	end
	local set = key and SETS[key]
	pane.Empty:SetText("")
	if set == "raid" then
		LayoutRaid()
	elseif set then
		LayoutRows(set)
	elseif key == "tools" then
		pane.Empty:SetText(L.PREVIEW_TOOLS)
	elseif key ~= nil then
		pane.Empty:SetText(L.PREVIEW_NONE)
	end
	caption:SetShown(set ~= nil)
end

function Preview:Refresh()
	if current then
		self:Show(current)
	end
end
