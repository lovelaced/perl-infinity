-- The healer mana window: your raid's healers with their mana, what they're
-- casting, and (optionally) their target. If you're a druid, right-click a
-- healer to cast Innervate on them.
--
-- Mana is secret on Forever, so the window shows each healer's bar and
-- percent but can't add them up into a raid total the way X-Perl did.
local _, ns = ...

local Frames, Header, Combat, Util, Classes, Spells = ns.Frames, ns.Header, ns.Combat, ns.Util, ns.Classes, ns.Spells
local L = ns.L

local header, title

local function RowOptions(_, conf)
	return { width = conf.width, power = true }
end

Frames:Define("healers", {
	layout = "Raid",
	group = true,
	movable = true,
	conf = function()
		return ns.db.healers
	end,
	enabled = function()
		return ns.db.healers.enabled
	end,
	scale = function()
		return 1
	end,
	layoutOptions = RowOptions,
	elements = { "Health", "Power", "Name", "Castbar", "Range", "Status" },
	refreshEvents = { "GROUP_ROSTER_UPDATE" },
	Decorate = function(frame)
		if frame.preview then
			return
		end
		Combat:Run(Combat:Key(frame, "healerTarget"), function()
			if frame.HealerTarget then
				return
			end
			frame.HealerTarget = Frames:AddSubFrame(frame, "tanktarget", "target", function(unit)
				return unit .. "target"
			end)
			frame.HealerTarget:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
		end)
	end,
})

local function ClassFilter(conf)
	local list = {}
	for index, token in ipairs(Classes.healerChoices) do
		if Util.HasBit(conf.classes, index) then
			list[#list + 1] = token
		end
	end
	return table.concat(list, ",")
end

local function Apply()
	local conf = ns.db.healers
	local mover = ns.Movers:Get("healers")
	local rects = ns.Layout.Raid(RowOptions(nil, conf))
	local height = math.max(rects.height, conf.height)
	Header.SetChildSize(header, rects.width, height)
	local _, class = UnitClass("player")
	local innervate = class == "DRUID" and C_Spell.GetSpellName(Spells.innervate)
	Header.Apply(header, {
		showRaid = true,
		groupFilter = ClassFilter(conf),
		groupBy = "CLASS",
		groupingOrder = table.concat(Classes.healerChoices, ","),
		sortMethod = "NAME",
		point = conf.growUp and "BOTTOM" or "TOP",
		yOffset = conf.growUp and 1 or -1,
		-- Copied onto every row the header makes, even in combat.
		_initialAttributeNames = innervate and "type2,spell2" or "",
		["_initialAttribute-type2"] = innervate and "spell" or nil,
		["_initialAttribute-spell2"] = innervate or nil,
	})
	Combat:Run(Combat:Key(header, "place"), function()
		header:ClearAllPoints()
		header:SetPoint(conf.growUp and "BOTTOMLEFT" or "TOPLEFT", mover, conf.growUp and "BOTTOMLEFT" or "TOPLEFT", 0, conf.growUp and 0 or -14)
		RegisterAttributeDriver(header, "state-visibility", "[group:raid] show; hide")
		for _, child in ipairs(header.children) do
			if innervate then
				child:SetAttribute("type2", "spell")
				child:SetAttribute("spell2", innervate)
			end
			if child.HealerTarget then
				if conf.targets then
					RegisterUnitWatch(child.HealerTarget)
				else
					UnregisterUnitWatch(child.HealerTarget)
					child.HealerTarget:Hide()
				end
			end
		end
	end)
	mover:SetAlpha(conf.alpha)
	ns.Movers:SetSize("healers", rects.width * (conf.targets and 2 or 1) + 4, (height + 1) * 10 + 14)
	for _, child in ipairs(header.children) do
		child:Configure()
	end
end

local function EnableNow(enabled)
	if enabled and not header then
		local mover = ns.Movers:Get("healers")
		title = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		title:SetPoint("TOPLEFT", 0, 0)
		title:SetText(L.HEALERS_TITLE)
		header = Header.Create("PerlInfinity_HealerHeader", mover, "healers", Frames.specs.healers)
		Apply()
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
	ns.Movers:SetEnabled("healers", enabled)
end

-- Headers are secure, so turning the window on or off waits for combat to end.
local function Enable(enabled)
	Combat:Run(Combat:Key(Frames, "healersEnable"), EnableNow, enabled)
end

Frames.specs.healers.Create = function()
	if ns.db.healers.enabled then
		Enable(true)
	end
end
Frames.specs.healers.Reconfigure = function()
	Enable(ns.db.healers.enabled)
end
Frames.specs.healers.SetEnabled = Enable
