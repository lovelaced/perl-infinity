-- Raid frames and raid pets.
--
-- Columns are secure group headers: one per raid group, one per class, or a
-- single header sorted by role. Which header shows whom, and the attributes
-- that say so, come from RaidSpec.Build, a pure function of the settings.
local _, ns = ...

local Frames, Header, Combat, Util, Classes = ns.Frames, ns.Header, ns.Combat, ns.Util, ns.Classes
local L = ns.L

local RaidSpec = {}
ns.RaidSpec = RaidSpec

local MAX_COLUMNS = 9
local ROLE_ORDER = "TANK,HEALER,DAMAGER,NONE"

local GROWTH = {
	down = { point = "TOP", x = 0, y = -1 },
	up = { point = "BOTTOM", x = 0, y = 1 },
	right = { point = "LEFT", x = 1, y = 0 },
	left = { point = "RIGHT", x = -1, y = 0 },
}

local function ClassList(conf)
	local list = {}
	for token in conf.classOrder:gmatch("[^,]+") do
		list[#list + 1] = token
	end
	return list
end

-- Comma lists of the groups and classes the settings allow.
local function Allowed(conf)
	local groups, classes = {}, {}
	for i = 1, 8 do
		if Util.HasBit(conf.groups, i) then
			groups[#groups + 1] = tostring(i)
		end
	end
	for i, token in ipairs(ClassList(conf)) do
		if Util.HasBit(conf.classes, i) then
			classes[#classes + 1] = token
		end
	end
	return groups, classes
end

-- Returns { columns = { { title, attributes } ... } } for the settings.
function RaidSpec.Build(conf)
	local growth = GROWTH[conf.direction] or GROWTH.down
	local spacing = conf.spacing
	local groups, classes = Allowed(conf)
	local allGroups = #groups == 8
	local allClasses = #classes == #Classes.order
	local common = {
		showRaid = true,
		showParty = conf.inParty,
		showPlayer = conf.inParty,
		point = growth.point,
		xOffset = growth.x * spacing,
		yOffset = growth.y * spacing,
		sortMethod = conf.alphabetical and "NAME" or "INDEX",
		groupBy = false,
		groupingOrder = false,
		roleFilter = false,
		unitsPerColumn = false,
		maxColumns = false,
	}
	local columns = {}
	local function Column(title, attributes, group)
		local merged = {}
		for key, value in pairs(common) do
			merged[key] = value
		end
		for key, value in pairs(attributes) do
			merged[key] = value
		end
		columns[#columns + 1] = { title = title, attributes = merged, group = group }
	end

	if conf.sortBy == "role" then
		Column(nil, {
			groupFilter = table.concat(groups, ","),
			strictFiltering = not allClasses,
			groupBy = "ASSIGNEDROLE",
			groupingOrder = ROLE_ORDER,
			unitsPerColumn = 5,
			maxColumns = 8,
			columnSpacing = conf.groupGap,
			columnAnchorPoint = growth.x == 0 and "LEFT" or "TOP",
		})
	elseif conf.sortBy == "class" then
		local groupPart = allGroups and "" or ("," .. table.concat(groups, ","))
		for _, token in ipairs(classes) do
			Column(Classes.Name(token), {
				groupFilter = token .. groupPart,
				strictFiltering = not allGroups,
			})
		end
	else
		local classPart = allClasses and "" or ("," .. table.concat(classes, ","))
		for _, group in ipairs(groups) do
			Column(L.GROUP_N:format(group), {
				groupFilter = group .. classPart,
				strictFiltering = not allClasses,
			}, tonumber(group))
		end
	end
	return { columns = columns, growth = growth }
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local headers = {}
local titles = {}
local titleHolder
local petHeader

local RAID_ELEMENTS = {
	"Health", "HealPrediction", "Power", "Name", "Auras", "DispelHighlight", "Highlights", "Range",
	"Status", "Leader", "RaidIcon", "ReadyCheck", "Resurrect", "Role",
}

local function RaidLayoutOptions(_, conf)
	return { width = 80 + conf.width, power = conf.mana }
end

local function ChildSize(conf)
	local rects = ns.Layout.Raid(RaidLayoutOptions(nil, conf))
	return rects.width, rects.height
end

local function Visibility(conf)
	if conf.inParty then
		return "[group] show; hide"
	end
	return "[group:raid] show; hide"
end

-- Group titles live in their own holder, shown under the same rule as the
-- headers, so "Group 1" never floats on screen outside a raid.
local function Title(index)
	local title = titles[index]
	if not title then
		if not titleHolder then
			titleHolder = CreateFrame("Frame", nil, ns.Movers:Get("raid"))
			titleHolder:SetAllPoints()
		end
		title = titleHolder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		titles[index] = title
	end
	return title
end

-- Your own group's title is highlighted.
local function ColorTitles()
	local index = UnitInRaid("player")
	local mine = index and select(3, GetRaidRosterInfo(index))
	for _, title in ipairs(titles) do
		if title.group and title.group == mine then
			title:SetTextColor(1, 1, 1)
		else
			title:SetTextColor(1, 0.82, 0)
		end
	end
end

local function Apply()
	local conf = ns.db.raid
	local spec = RaidSpec.Build(conf)
	local width, height = ChildSize(conf)
	local mover = ns.Movers:Get("raid")
	local growth = spec.growth
	local vertical = growth.x == 0
	local pitchX = vertical and (width + conf.groupGap) or 0
	local pitchY = vertical and 0 or (height + conf.groupGap)
	local columnLength = 5

	for index = 1, MAX_COLUMNS do
		local header = headers[index]
		local column = spec.columns[index]
		local title = Title(index)
		if column and not header then
			header = Header.Create("PerlInfinity_RaidHeader" .. index, mover, "raid", Frames.specs.raid)
			headers[index] = header
		end
		if header then
			if column then
				Header.SetChildSize(header, width, height)
				local attributes = column.attributes
				Header.Apply(header, attributes)
				local x, y = (index - 1) * pitchX, -(index - 1) * pitchY
				if not vertical then
					x, y = 0, -(index - 1) * pitchY
				end
				Combat:Run(Combat:Key(header, "place"), function()
					header:ClearAllPoints()
					local corner = growth.point == "BOTTOM" and "BOTTOMLEFT" or (growth.point == "RIGHT" and "TOPRIGHT" or "TOPLEFT")
					header:SetPoint(corner, mover, corner, x, y + (conf.titles and -12 or 0))
					RegisterAttributeDriver(header, "state-visibility", Visibility(conf))
				end)
				title:ClearAllPoints()
				title:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", x + 2, y - 11)
				title:SetText(column.title or "")
				title.group = column.group
				title:SetShown(conf.titles and column.title ~= nil)
				for _, child in ipairs(header.children) do
					child:Configure()
				end
			else
				Combat:Run(Combat:Key(header, "place"), function()
					UnregisterAttributeDriver(header, "state-visibility")
					header:Hide()
				end)
				title:Hide()
			end
		else
			title:Hide()
		end
	end
	ColorTitles()
	RegisterAttributeDriver(titleHolder, "state-visibility", Visibility(conf))

	local columns = math.max(#spec.columns, conf.sortBy == "role" and 8 or 1)
	local blockWidth = vertical and columns * (width + conf.groupGap) or width * columnLength
	local blockHeight = vertical and (height + conf.spacing) * columnLength + 12 or columns * (height + conf.groupGap)
	ns.Movers:SetSize("raid", blockWidth, blockHeight)
end

-- Raid buttons are made ahead of time, out of combat, so a raid forming
-- mid-fight doesn't have to create forty frames. Nobody needs them while
-- solo, so that waits until you're in a group (raids grow out of parties),
-- and it's spread out, one group's worth at a time.
local precreated = false
local function PrecreateWhenGrouped()
	if precreated or #headers == 0 or not IsInGroup() then
		return
	end
	precreated = true
	for index, header in ipairs(headers) do
		C_Timer.After(index * 0.1, function()
			Header.Precreate(header, 5)
		end)
	end
end

Frames:Define("raid", {
	layout = "Raid",
	group = true,
	movable = true,
	conf = function()
		return ns.db.raid
	end,
	enabled = function()
		return ns.db.raid.enabled
	end,
	scale = function()
		return ns.db.raid.scale
	end,
	layoutOptions = RaidLayoutOptions,
	elements = RAID_ELEMENTS,
	refreshEvents = { "GROUP_ROSTER_UPDATE" },

	Create = function()
		if not ns.db.raid.enabled then
			return
		end
		Combat:Run(Combat:Key(headers, "apply"), Apply)
		PrecreateWhenGrouped()
		ns.Events:On("GROUP_ROSTER_UPDATE", titles, function()
			ColorTitles()
			PrecreateWhenGrouped()
		end)
	end,
	-- Raid headers are secure: new columns can't be made, nor attributes
	-- changed, during combat, so the whole update waits for it to end.
	Reconfigure = function()
		if ns.db.raid.enabled then
			Combat:Run(Combat:Key(headers, "apply"), Apply)
		end
	end,
	SetEnabled = function(enabled)
		if enabled then
			Combat:Run(Combat:Key(headers, "apply"), Apply)
		else
			for _, header in ipairs(headers) do
				Combat:Run(Combat:Key(header, "place"), function()
					UnregisterAttributeDriver(header, "state-visibility")
					header:Hide()
				end)
			end
			for _, title in ipairs(titles) do
				title:Hide()
			end
		end
		ns.Movers:SetEnabled("raid", enabled)
	end,

	sample = function()
		return {
			name = L.SAMPLE_RAID_1,
			class = "PRIEST",
			health = 3600, maxHealth = 4200,
			power = 4100, maxPower = 6000, powerToken = "MANA",
			raidIcon = 1,
			auras = { { spell = 11597, harmful = true } },
		}
	end,
})

---------------------------------------------------------------------------
-- Raid pets
---------------------------------------------------------------------------

local function ApplyPets()
	local conf = ns.db.raid
	local width, height = ChildSize(conf)
	Header.SetChildSize(petHeader, width, height)
	Header.Apply(petHeader, {
		showRaid = true,
		point = "TOP",
		yOffset = -conf.spacing,
		unitsPerColumn = 7,
		maxColumns = 8,
		columnSpacing = conf.groupGap,
		columnAnchorPoint = "LEFT",
		filterOnPet = true,
	})
	Combat:Run(Combat:Key(petHeader, "place"), function()
		petHeader:ClearAllPoints()
		if conf.petsAttached then
			petHeader:SetPoint("TOPLEFT", ns.Movers:Get("raid"), "TOPRIGHT", conf.groupGap + 4, -12)
		else
			petHeader:SetPoint("TOPLEFT", ns.Movers:Get("raidpets"), "TOPLEFT")
		end
		if conf.pets then
			RegisterAttributeDriver(petHeader, "state-visibility", "[group:raid] show; hide")
		else
			UnregisterAttributeDriver(petHeader, "state-visibility")
			petHeader:Hide()
		end
	end)
	ns.Movers:SetEnabled("raidpets", conf.pets and not conf.petsAttached)
	ns.Movers:SetSize("raidpets", width, (height + conf.spacing) * 7)
	for _, child in ipairs(petHeader.children) do
		child:Configure()
	end
	ns.Movers:RefitHandle("raid")
	ns.Movers:RefitHandle("raidpets")
end

Frames:Define("raidpets", {
	layout = "Raid",
	group = true,
	movable = true,
	conf = function()
		return ns.db.raid
	end,
	enabled = function()
		return ns.db.raid.enabled and ns.db.raid.pets
	end,
	scale = function()
		return ns.db.raid.scale
	end,
	layoutOptions = RaidLayoutOptions,
	elements = { "Health", "Name", "Range", "RaidIcon" },
	refreshEvents = { "UNIT_PET" },

	Create = function()
		if not (ns.db.raid.enabled and ns.db.raid.pets) then
			return
		end
		petHeader = Header.Create("PerlInfinity_RaidPetHeader", ns.Movers:Get("raid"), "raidpets", Frames.specs.raidpets, true)
		-- Pets belong to whichever box they're placed by, for Edit Mode's handle.
		ns.Movers:SetRiders("raid", function()
			return ns.db.raid.petsAttached and petHeader.children or nil
		end)
		ns.Movers:SetRiders("raidpets", function()
			return not ns.db.raid.petsAttached and petHeader.children or nil
		end)
		ApplyPets()
	end,
	Reconfigure = function()
		Combat:Run(Combat:Key(Frames.specs.raidpets, "apply"), function()
			if petHeader then
				ApplyPets()
			elseif ns.db.raid.enabled and ns.db.raid.pets then
				Frames.specs.raidpets.Create()
			end
		end)
	end,
})
