-- Party frames, with each member's target and pet riding alongside.
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

Frames:Define("partytarget", {
	layout = "Small",
	conf = function()
		return ns.db.party
	end,
	layoutOptions = function(_, conf)
		return { width = conf.targetWidth, percent = false, power = false, thick = false, extras = 0 }
	end,
	elements = { "Health", "Name", "Level", "RaidIcon" },
	refreshEvents = {},
	combatFeedback = false,
})

Frames:Define("partypet", {
	layout = "Small",
	conf = function()
		return ns.db.party
	end,
	layoutOptions = function()
		return { width = 100, percent = false, power = true, thick = false, extras = 0 }
	end,
	elements = { "Health", "Power", "Name", "Level", "Auras", "RaidIcon" },
	refreshEvents = { "UNIT_PET" },
	combatFeedback = false,
})

-- Secure buttons are anchored to the secure party button, using the layout's
-- numbers. Anchoring them to our own boxes would make those boxes protected,
-- and they could no longer be redrawn during combat.
--
-- The game multiplies an anchor's offsets by the anchored frame's own scale, so
-- they're divided by it here to land at the same spot at any scale.
local TARGET_SCALE = 0.9

local function PlaceSubFrames(frame)
	local conf = ns.db.party
	local target, pet = frame.PartyTarget, frame.PartyPet
	local rects = frame.rects
	if not rects then
		return
	end
	local beside = rects.width - 2
	if target then
		target:ClearAllPoints()
		target:SetScale(TARGET_SCALE)
		target:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", beside / TARGET_SCALE, (rects.name.y - 22) / TARGET_SCALE) -- lint: allow L10 (a constant)
		if conf.targets then
			RegisterUnitWatch(target)
		else
			UnregisterUnitWatch(target)
			target:Hide()
		end
	end
	if pet then
		local petScale = math.max(conf.petScale, 0.1) / math.max(conf.scale, 0.1) -- lint: allow L10 (guarded)
		pet:ClearAllPoints()
		pet:SetScale(petScale)
		pet:SetPoint("TOPLEFT", frame, "TOPLEFT", beside / petScale, rects.statsBox.y / petScale) -- lint: allow L10 (guarded above)
		if conf.pets then
			RegisterUnitWatch(pet)
		else
			UnregisterUnitWatch(pet)
			pet:Hide()
		end
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

local GROWTH = {
	down = { point = "TOP", corner = "TOPLEFT", x = 0, y = -1 },
	up = { point = "BOTTOM", corner = "BOTTOMLEFT", x = 0, y = 1 },
	right = { point = "LEFT", corner = "TOPLEFT", x = 1, y = 0 },
	left = { point = "RIGHT", corner = "TOPRIGHT", x = -1, y = 0 },
}

local function Visibility(conf)
	if conf.inRaid == "hide" then
		return "[group:raid] hide; [group:party] show; hide"
	end
	return "[group] show; hide"
end

local function Apply()
	local conf = ns.db.party
	local growth = GROWTH[conf.direction] or GROWTH.down
	local rects = ns.Layout[conf.mirror and "PortraitRight" or "PortraitLeft"](PartyLayoutOptions(nil, conf))
	local spacing = conf.spacing

	Header.SetChildSize(header, rects.width, rects.height)
	Header.Apply(header, {
		showParty = true,
		showRaid = false,
		showPlayer = conf.showPlayer,
		point = growth.point,
		xOffset = growth.x * spacing,
		yOffset = growth.y * spacing,
	})

	Combat:Run(Combat:Key(header, "place"), function()
		local mover = ns.Movers:Get("party")
		header:ClearAllPoints()
		header:SetPoint(growth.corner, mover, growth.corner)
		RegisterAttributeDriver(header, "state-visibility", Visibility(conf))
		local count = conf.showPlayer and 5 or 4
		local vertical = growth.x == 0
		local width = vertical and rects.width or (rects.width + spacing) * count
		local height = vertical and (rects.height + spacing) * count or rects.height
		ns.Movers:SetSize("party", width, height)
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
	ns.Movers:RefitHandle("party")
end

-- Each member's target and pet, so Edit Mode's handle can take them in.
local function SubFrames()
	local list = {}
	for _, child in ipairs(header.children) do
		for _, sub in ipairs(child.subFrames or {}) do
			list[#list + 1] = sub
		end
	end
	return list
end

-- "Only in one-group raids" can't be written as a macro condition, so it's
-- re-checked whenever the roster changes, out of combat.
local function UpdateSmallRaid()
	local conf = ns.db.party
	if conf.inRaid ~= "smallRaid" or not header then
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
		ns.Movers:SetRiders("party", SubFrames)
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
			Combat:Run(Combat:Key(header, "enabled"), function()
				if enabled then
					RegisterAttributeDriver(header, "state-visibility", Visibility(ns.db.party))
				else
					UnregisterAttributeDriver(header, "state-visibility")
					header:Hide()
				end
			end)
		end
		ns.Movers:SetEnabled("party", enabled)
	end,

	-- Edit Mode: real members on screen need no samples drawn over them.
	ShowingMembers = function()
		return header and header:IsShown()
	end,
	-- Edit Mode: lay samples out the way the real party grows.
	PlaceSample = function(preview, index, mover)
		local conf = ns.db.party
		local growth = GROWTH[conf.direction] or GROWTH.down
		local rects = preview.rects
		local step = index - 1
		preview:SetPoint(growth.corner, mover, growth.corner,
			growth.x * step * (rects.width + conf.spacing),
			growth.y * step * (rects.height + conf.spacing))
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
