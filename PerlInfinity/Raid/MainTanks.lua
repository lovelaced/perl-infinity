-- The tank targets window: each tank, what they're fighting, and who that
-- enemy is attacking. Rows are secure buttons, so clicking any name targets
-- that unit, in combat too.
--
-- The game's group header lists the tanks: players set as main tank in the
-- raid, or everyone who picked the tank role. When nobody is a main tank,
-- "Main tanks, then warriors" lists warriors instead; that switch happens out
-- of combat, when the roster changes.
local _, ns = ...

local Frames, Header, Combat = ns.Frames, ns.Header, ns.Combat
local L = ns.L

local header, title
local ShowThirdColumn

local ROW_ELEMENTS = { "Health", "Name", "RaidIcon", "Range", "Status" }

local function RowOptions(_, conf)
	return { width = conf.width, power = false, height = conf.height }
end

Frames:Define("tanks", {
	layout = "Raid",
	group = true,
	movable = true,
	conf = function()
		return ns.db.tanks
	end,
	enabled = function()
		return ns.db.tanks.enabled
	end,
	scale = function()
		return 1
	end,
	layoutOptions = RowOptions,
	elements = ROW_ELEMENTS,
	refreshEvents = { "GROUP_ROSTER_UPDATE" },
	Decorate = function(frame)
		if frame.preview then
			return
		end
		Combat:Run(Combat:Key(frame, "tankColumns"), function()
			if frame.TankTarget then
				return
			end
			frame.TankTarget = Frames:AddSubFrame(frame, "tanktarget", "target", function(unit)
				return unit .. "target"
			end)
			frame.TankTarget:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
			frame.TankTargetTarget = Frames:AddSubFrame(frame, "tanktarget", "targettarget", function(unit)
				return unit .. "targettarget"
			end)
			frame.TankTargetTarget:SetPoint("TOPLEFT", frame.TankTarget, "TOPRIGHT", 2, 0)
			ShowThirdColumn(frame, ns.db.tanks.showTargetTarget)
		end)
		local number = frame.Content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		number:SetPoint("RIGHT", frame, "LEFT", -2, 0)
		frame.TankNumber = number
	end,
})

Frames:Define("tanktarget", {
	layout = "Raid",
	conf = function()
		return ns.db.tanks
	end,
	layoutOptions = RowOptions,
	elements = { "Health", "Name", "RaidIcon" },
	refreshEvents = {},
	combatFeedback = false,
})

-- Who counts as a tank, as header filter attributes.
local function Filter(conf)
	if conf.source == "role" then
		return { roleFilter = "TANK", groupFilter = false }
	end
	if conf.source == "mainTanks" then
		-- Fall back to warriors when nobody is set as main tank.
		for i = 1, GetNumGroupMembers() do
			local role = select(10, GetRaidRosterInfo(i))
			if role == "MAINTANK" then
				return { roleFilter = "MAINTANK", groupFilter = false }
			end
		end
		return { roleFilter = false, groupFilter = "WARRIOR" }
	end
	return { roleFilter = "MAINTANK", groupFilter = false }
end

-- The third column (who each tank's enemy is attacking) is optional.
ShowThirdColumn = function(row, shown)
	local sub = row.TankTargetTarget
	if not sub then
		return
	end
	Combat:Run(Combat:Key(sub, "shown"), function()
		if shown then
			RegisterUnitWatch(sub)
		else
			UnregisterUnitWatch(sub)
			sub:Hide()
		end
	end)
end

local function Apply()
	local conf = ns.db.tanks
	local mover = ns.Movers:Get("tanks")
	local rects = ns.Layout.Raid(RowOptions(nil, conf))
	Header.SetChildSize(header, rects.width, rects.height)
	local attributes = Filter(conf)
	attributes.showRaid = true
	attributes.point = conf.growUp and "BOTTOM" or "TOP"
	attributes.yOffset = conf.growUp and 2 or -2
	attributes.maxColumns = 1
	attributes.unitsPerColumn = conf.max
	attributes.sortMethod = "INDEX"
	Header.Apply(header, attributes)
	Combat:Run(Combat:Key(header, "place"), function()
		header:ClearAllPoints()
		header:SetPoint(conf.growUp and "BOTTOMLEFT" or "TOPLEFT", mover, conf.growUp and "BOTTOMLEFT" or "TOPLEFT", 14, conf.growUp and 0 or -14)
		RegisterAttributeDriver(header, "state-visibility", "[group:raid] show; hide")
	end)
	mover:SetAlpha(conf.alpha)
	local columns = conf.showTargetTarget and 3 or 2
	ns.Movers:SetSize("tanks", (rects.width + 2) * columns + 14, (rects.height + 2) * conf.max + 14)
	title:SetShown(true)
	for index, child in ipairs(header.children) do
		child:Configure()
		if child.TankNumber then
			child.TankNumber:SetText(conf.numbers and index or "")
		end
		if child.subFrames then
			for _, sub in ipairs(child.subFrames) do
				sub:Configure()
				Combat:Run(Combat:Key(sub, "size"), sub.SetSize, sub, rects.width, rects.height)
			end
		end
		ShowThirdColumn(child, conf.showTargetTarget)
	end
end

local Tanks = ns:NewModule("MainTanks")

local function EnableNow(enabled)
	if enabled and not header then
		local mover = ns.Movers:Get("tanks")
		title = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		title:SetPoint("TOPLEFT", 14, 0)
		title:SetText(L.TANKS_TITLE)
		header = Header.Create("PerlInfinity_TankHeader", mover, "tanks", Frames.specs.tanks)
		Apply()
		ns.Events:On("GROUP_ROSTER_UPDATE", Tanks, function()
			if ns.db.tanks.source == "mainTanks" then
				Combat:Run(Combat:Key(Tanks, "filter"), function()
					Header.Apply(header, Filter(ns.db.tanks))
				end)
			end
		end)
	elseif header then
		if enabled then
			Apply()
		else
			Combat:Run(Combat:Key(header, "place"), function()
				UnregisterAttributeDriver(header, "state-visibility")
				header:Hide()
			end)
		end
	end
	ns.Movers:SetEnabled("tanks", enabled)
end

-- Headers are secure, so turning the window on or off waits for combat to end.
local function Enable(enabled)
	Combat:Run(Combat:Key(Frames, "tanksEnable"), EnableNow, enabled)
end

Frames.specs.tanks.Create = function()
	if ns.db.tanks.enabled then
		Enable(true)
	end
end
Frames.specs.tanks.Reconfigure = function()
	Enable(ns.db.tanks.enabled)
end
Frames.specs.tanks.SetEnabled = Enable
