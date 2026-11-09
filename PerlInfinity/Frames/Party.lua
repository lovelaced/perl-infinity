-- Party frames, plus a column of each member's target and a column of their pets.
--
-- The game's secure group header decides who appears where. In a raid, a
-- party header shows your own raid group, which is how X-Perl's "keep party
-- frames in a raid" works.
local _, ns = ...

local Frames, Header, Combat = ns.Frames, ns.Header, ns.Combat
local L = ns.L

local header

local PARTY_ELEMENTS = {
	"Health", "HealPrediction", "Power", "Name", "Level", "Portrait", "Castbar", "Auras",
	"DispelHighlight", "Highlights", "Range", "Status", "Leader", "RaidIcon", "PvP", "ReadyCheck",
	"Resurrect", "Role", "CombatFeedback",
}

local function PartyLayoutOptions(_, conf)
	return {
		width = 140 + conf.width,
		portrait = conf.portrait,
		percent = conf.percent,
		power = conf.power,
		thick = ns.db.look.thickHealth,
		extras = 0,
	}
end

-- Which way the members run, and the corner everything is measured from.
local GROWTH = {
	down = { point = "TOP", corner = "TOPLEFT", x = 0, y = -1 },
	up = { point = "BOTTOM", corner = "BOTTOMLEFT", x = 0, y = 1 },
	right = { point = "LEFT", corner = "TOPLEFT", x = 1, y = 0 },
	left = { point = "RIGHT", corner = "TOPRIGHT", x = -1, y = 0 },
}

local function Growth(conf)
	return GROWTH[conf.direction] or GROWTH.down
end

local function MemberRects(conf)
	return ns.Layout[conf.mirror and "PortraitRight" or "PortraitLeft"](PartyLayoutOptions(nil, conf))
end

-- Icons hang off each member, and a frame can't resize to fit its auras. So
-- when members are stacked, the gap leaves room for every icon they could show.
local function MemberGap(conf, rects, growth)
	local auras = conf.auras
	if growth.x ~= 0 or not conf.fitIcons or not (auras.buffs or auras.debuffs) then
		return conf.spacing
	end
	local groups = ns.AuraHost.Groups(auras, ns.db.auras, false)
	return math.max(conf.spacing, ns.AuraHost.RoomNeeded(groups, rects, auras.rows))
end

-- From one member to the next.
local function MemberPitch(conf, rects, growth)
	return (growth.x == 0 and rects.height or rects.width) + MemberGap(conf, rects, growth)
end

---------------------------------------------------------------------------
-- Party targets and pets
---------------------------------------------------------------------------

local function TargetOf(unit)
	return unit .. "target"
end

local function PetOf(unit)
	if unit == "player" then
		return "pet"
	end
	return (unit:gsub("^(%a+)(%d+)$", "%1pet%2"))
end

-- Targets and pets each form a column with a slot per member, and each column
-- is its own Edit Mode box. A column stays beside the party until you drag it.
--
-- The buttons themselves stay children of their party member, which gives them
-- their unit and hides them along with the member. The column only decides
-- where they're drawn.
--
-- The game multiplies an anchor's offsets by the anchored frame's own scale, so
-- they're divided by it here to land at the same spot at any scale.
local TARGET_SCALE = 0.9

local COLUMNS = {
	{
		key = "partytarget", field = "PartyTarget", setting = "targets",
		relativeScale = function()
			return TARGET_SCALE
		end,
		-- Sits just above the member's stats, reaching up past their name.
		top = function(rects, height)
			return rects.name.y - 22 + height
		end,
	},
	{
		key = "partypet", field = "PartyPet", setting = "pets",
		relativeScale = function(conf)
			return math.max(conf.petScale, 0.1) / math.max(conf.scale, 0.1) -- lint: allow L10 (guarded)
		end,
		top = function(rects)
			return rects.statsBox.y
		end,
	},
}

-- Real frames on screen need no samples drawn over them in Edit Mode.
local function AnyShown(field)
	for _, child in ipairs(header and header.children or {}) do
		local sub = child[field]
		if sub and sub:IsVisible() then
			return true
		end
	end
	return false
end

local function PlaceColumnSample(column)
	return function(preview, index, mover)
		local conf = ns.db.party
		local growth = Growth(conf)
		local step = (index - 1) * MemberPitch(conf, MemberRects(conf), growth) / column.relativeScale(conf) -- lint: allow L10 (guarded)
		preview:SetPoint(growth.corner, mover, growth.corner, growth.x * step, growth.y * step)
	end
end

Frames:Define("partytarget", {
	layout = "Small",
	conf = function()
		return ns.db.party
	end,
	scale = function()
		return ns.db.party.scale * TARGET_SCALE
	end,
	layoutOptions = function(_, conf)
		return { width = conf.targetWidth, percent = false, power = false, thick = false, extras = 0 }
	end,
	elements = { "Health", "Name", "Level", "RaidIcon" },
	refreshEvents = {},
	combatFeedback = false,
	ShowingMembers = function()
		return AnyShown("PartyTarget")
	end,
	PlaceSample = PlaceColumnSample(COLUMNS[1]),
	sample = function()
		return {
			name = L.SAMPLE_PET_TARGET,
			level = 60,
			reaction = "hostile",
			health = 2800, maxHealth = 4000,
		}
	end,
})

Frames:Define("partypet", {
	layout = "Small",
	conf = function()
		return ns.db.party
	end,
	scale = function()
		return math.max(ns.db.party.petScale, 0.1)
	end,
	layoutOptions = function()
		return { width = 100, percent = false, power = true, thick = false, extras = 0 }
	end,
	elements = { "Health", "Power", "Name", "Level", "Auras", "RaidIcon" },
	refreshEvents = { "UNIT_PET" },
	combatFeedback = false,
	ShowingMembers = function()
		return AnyShown("PartyPet")
	end,
	PlaceSample = PlaceColumnSample(COLUMNS[2]),
	sample = function()
		return {
			name = L.SAMPLE_PET,
			level = 60,
			reaction = "friendly",
			health = 1250, maxHealth = 1600,
			power = 70, maxPower = 100, powerToken = "FOCUS",
		}
	end,
})

-- Secure buttons are anchored to their column, using the layout's numbers.
-- Anchoring them to our own boxes would make those boxes protected, and they
-- could no longer be redrawn during combat.
local function SlotOf(frame)
	for index, child in ipairs(header.children) do
		if child == frame then
			return index
		end
	end
	return 1
end

local function PlaceSubFrames(frame)
	local rects = frame.rects
	if not rects then
		return
	end
	local conf = ns.db.party
	local growth = Growth(conf)
	local distance = (SlotOf(frame) - 1) * MemberPitch(conf, rects, growth)
	for _, column in ipairs(COLUMNS) do
		local sub = frame[column.field]
		if sub then
			local scale = column.relativeScale(conf)
			sub:ClearAllPoints()
			sub:SetScale(scale)
			sub:SetPoint(growth.corner, ns.Movers:Get(column.key), growth.corner,
				growth.x * distance / scale, growth.y * distance / scale) -- lint: allow L10 (guarded)
			if conf[column.setting] then
				RegisterUnitWatch(sub)
			else
				UnregisterUnitWatch(sub)
				sub:Hide()
			end
		end
	end
end

-- Sizes each column to fit its slots, and sets where it stays until you drag it:
-- beside the first member, measured corner to corner with the party.
local function PlaceColumns(conf, growth, rects)
	local party = ns.Movers:Get("party")
	local slots = (conf.showPlayer and 5 or 4) - 1
	local pitch = MemberPitch(conf, rects, growth)
	local left = rects.width - 2
	for _, column in ipairs(COLUMNS) do
		local size = ns.Layout.Small(Frames.specs[column.key].layoutOptions(nil, conf))
		local scale = column.relativeScale(conf)
		local run = slots * pitch / scale -- lint: allow L10 (guarded)
		local top = column.top(rects, size.height * scale)
		local x, y = left, top
		if growth.corner == "TOPRIGHT" then
			x = left + size.width * scale - rects.width
		elseif growth.corner == "BOTTOMLEFT" then
			y = top - size.height * scale + rects.height
		end
		ns.Movers:Rescale(column.key)
		ns.Movers:SetSize(column.key,
			size.width + (growth.x == 0 and 0 or run),
			size.height + (growth.x == 0 and run or 0))
		ns.Movers:Follow(column.key, party, growth.corner, x / scale, y / scale) -- lint: allow L10 (guarded)
		ns.Movers:SetEnabled(column.key, conf.enabled and conf[column.setting])
	end
end

local function DecorateMember(frame)
	if frame.preview then
		return
	end
	-- Place the target and pet buttons whenever this frame's layout changes.
	frame.OnLayout = function(self)
		if self.PartyTarget then
			Combat:Run(Combat:Key(self, "partySubFrames"), PlaceSubFrames, self)
		end
	end
	Combat:Run(Combat:Key(frame, "partySubFrames"), function()
		if not frame.PartyTarget then
			frame.PartyTarget = Frames:AddSubFrame(frame, "partytarget", "target", TargetOf)
			frame.PartyPet = Frames:AddSubFrame(frame, "partypet", "pet", PetOf)
		end
		PlaceSubFrames(frame)
	end)
end

---------------------------------------------------------------------------
-- The header
---------------------------------------------------------------------------

local function Visibility(conf)
	if conf.inRaid == "hide" then
		return "[group:raid] hide; [group:party] show; hide"
	end
	return "[group] show; hide"
end

local function Apply()
	local conf = ns.db.party
	local growth = Growth(conf)
	local rects = MemberRects(conf)
	local gap = MemberGap(conf, rects, growth)

	Header.SetChildSize(header, rects.width, rects.height)
	Header.Apply(header, {
		showParty = true,
		showRaid = false,
		showPlayer = conf.showPlayer,
		point = growth.point,
		xOffset = growth.x * gap,
		yOffset = growth.y * gap,
	})

	Combat:Run(Combat:Key(header, "place"), function()
		local mover = ns.Movers:Get("party")
		ns.Movers:Rescale("party")
		header:ClearAllPoints()
		header:SetPoint(growth.corner, mover, growth.corner)
		if conf.enabled then
			RegisterAttributeDriver(header, "state-visibility", Visibility(conf))
		else
			UnregisterAttributeDriver(header, "state-visibility")
			header:Hide()
		end
		local count = conf.showPlayer and 5 or 4
		local vertical = growth.x == 0
		local width = vertical and rects.width or (rects.width + gap) * count
		local height = vertical and (rects.height + gap) * count or rects.height
		ns.Movers:SetSize("party", width, height)
		PlaceColumns(conf, growth, rects)
	end)

	for _, child in ipairs(header.children) do
		child:Configure()
		if child.subFrames then
			Combat:Run(Combat:Key(child, "partySubFrames"), PlaceSubFrames, child)
			for _, sub in ipairs(child.subFrames) do
				sub:Configure()
			end
		end
	end
end

-- "Only in one-group raids" can't be written as a macro condition, so it's
-- re-checked whenever the roster changes, out of combat.
local function UpdateSmallRaid()
	local conf = ns.db.party
	if conf.inRaid ~= "smallRaid" or not header or not conf.enabled then
		return
	end
	Combat:Run(Combat:Key(header, "smallRaid"), function()
		local small = IsInRaid() and GetNumGroupMembers() <= 5
		RegisterAttributeDriver(header, "state-visibility", small and "[group] show; hide" or "[group:raid] hide; [group:party] show; hide")
	end)
end

Frames:Define("party", {
	layout = "PortraitLeft",
	layoutName = function(conf)
		return conf.mirror and "PortraitRight" or "PortraitLeft"
	end,
	group = true,
	rangeHand = true,
	movable = true,
	conf = function()
		return ns.db.party
	end,
	enabled = function()
		return ns.db.party.enabled
	end,
	scale = function()
		return ns.db.party.scale
	end,
	layoutOptions = PartyLayoutOptions,
	elements = PARTY_ELEMENTS,
	refreshEvents = { "GROUP_ROSTER_UPDATE" },
	Decorate = DecorateMember,

	Create = function()
		if not ns.db.party.enabled then
			return
		end
		local mover = ns.Movers:Get("party")
		header = Header.Create("PerlInfinity_PartyHeader", mover, "party", Frames.specs.party)
		Apply()
		Header.Precreate(header, 5)
		ns.Events:On("GROUP_ROSTER_UPDATE", header, UpdateSmallRaid)
		UpdateSmallRaid()
	end,
	Reconfigure = function()
		if header then
			Apply()
		end
	end,
	SetEnabled = function(enabled)
		if enabled and not header then
			Frames.specs.party.Create()
		elseif header then
			-- Apply shows or hides the header by the switch.
			Apply()
			UpdateSmallRaid()
		end
		ns.Movers:SetEnabled("party", enabled)
		for _, column in ipairs(COLUMNS) do
			ns.Movers:SetEnabled(column.key, enabled and ns.db.party[column.setting])
		end
	end,

	-- Edit Mode: real members on screen need no samples drawn over them.
	ShowingMembers = function()
		return header and header:IsShown()
	end,
	-- Edit Mode: lay samples out the way the real party grows.
	PlaceSample = function(preview, index, mover)
		local conf = ns.db.party
		local growth = Growth(conf)
		local step = (index - 1) * MemberPitch(conf, preview.rects, growth)
		preview:SetPoint(growth.corner, mover, growth.corner, growth.x * step, growth.y * step)
	end,

	sample = function()
		return {
			name = L.SAMPLE_PARTY_1,
			class = "WARRIOR",
			level = 60,
			health = 5200, maxHealth = 6800,
			power = 40, maxPower = 100, powerToken = "RAGE",
			incoming = 900,
			role = "TANK",
			leader = true,
			ready = "ready",
			icon = 132355,
			auras = {
				{ spell = 1243 },
				{ spell = 139, mine = true },
				{ spell = 8921, harmful = true },
			},
		}
	end,
})
