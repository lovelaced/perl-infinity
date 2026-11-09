-- Buff and debuff icons, built on Blizzard's aura container.
--
-- Aura details are secret in combat on Forever, and reading them from addon
-- code throws. The container reads auras inside the game and draws icons,
-- stacks, timers and debuff colors for us; we only describe what to show
-- with filter strings ("HELPFUL|PLAYER" is "buffs I cast") and style each
-- button once when it's created. Containers can't be made during combat,
-- and buttons can't be restyled while auras are secret, so those steps wait.
local _, ns = ...

local Combat, Media = ns.Combat, ns.Media

local AuraHost = {}
ns.AuraHost = AuraHost

local SortDefault = AuraContainerSortMethod and AuraContainerSortMethod.Default or 0
local SortNormal = AuraContainerSortDirection and AuraContainerSortDirection.Normal or 0
local FlowRight = AnchorUtil.FlowDirection.Right
local FlowDown = AnchorUtil.FlowDirection.Down
local FlowUp = AnchorUtil.FlowDirection.Up
local RemainingDuration = Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration

---------------------------------------------------------------------------
-- Building a few frames' auras at a time
---------------------------------------------------------------------------

-- Every aura group makes ten buttons up front, so one frame's auras are a
-- few dozen widgets. When many frames appear at once (logging in to a full
-- raid, or joining one), building them all in one go would freeze the game,
-- so each rendered frame builds about AuraHost.budget milliseconds' worth
-- and the rest carry on in the next.
AuraHost.budget = 4
local GetTime, debugprofilestop = GetTime, debugprofilestop
local budgetTime, spent = nil, 0
local waiting, waitingList = {}, {}
local resumeQueued = false

local function Spend(started)
	local now = GetTime()
	if budgetTime ~= now then
		budgetTime, spent = now, 0
	end
	spent = spent + math.max(debugprofilestop() - started, 0.001)
end

-- Something is always built in each frame, so the queue drains even when
-- one container takes longer than the whole budget.
local function OverBudget()
	local now = GetTime()
	if budgetTime ~= now then
		budgetTime, spent = now, 0
	end
	return spent > 0 and spent >= AuraHost.budget
end

local Resume

local function ScheduleResume()
	if not resumeQueued then
		resumeQueued = true
		C_Timer.After(0, Resume)
	end
end

local function Wait(frame)
	if not waiting[frame] then
		waiting[frame] = true
		waitingList[#waitingList + 1] = frame
	end
	ScheduleResume()
end

function Resume()
	resumeQueued = false
	-- A resume runs on a new frame, so it starts with a fresh budget.
	budgetTime, spent = GetTime(), 0
	local list = waitingList
	waitingList = {}
	for i = 1, #list do
		local frame = list[i]
		if OverBudget() then
			waitingList[#waitingList + 1] = frame
		else
			waiting[frame] = nil
			-- A frame hidden again by now finishes when it next shows.
			if not frame:Deferred() then
				ns.Call(frame.Configure, frame)
			end
		end
	end
	if #waitingList > 0 then
		ScheduleResume()
	end
end

-- Frames still waiting for their turn (for tests and the self-test).
function AuraHost.Waiting()
	return #waitingList
end

---------------------------------------------------------------------------
-- One container per frame, shared by icons and the highlight slots.
---------------------------------------------------------------------------

-- Returns one of the frame's containers ("icons" by default), or nil if it
-- can't be made yet. In that case it's made as soon as it's allowed and the
-- frame reconfigures.
function AuraHost.Get(frame, name)
	name = name or "icons"
	local containers = frame.AuraContainers
	if not containers then
		containers = {}
		frame.AuraContainers = containers
	end
	if containers[name] then
		return containers[name]
	end
	if frame.preview then
		return nil
	end
	if InCombatLockdown() then
		if not frame.auraHostPending then
			frame.auraHostPending = true
			Combat:Run(Combat:Key(frame, "auraHost"), function()
				frame.auraHostPending = false
				frame:Configure()
			end)
		end
		return nil
	end
	if OverBudget() then
		Wait(frame)
		return nil
	end
	local started = debugprofilestop()
	local container = CreateFrame("AuraContainer", nil, frame.Content, "CustomAuraContainerTemplate")
	ns.Box.Raise(container, frame.Content, ns.Box.LEVEL.AURAS)
	container.owner = frame
	container.groups = {}
	container.slots = {}
	container.sizes = {}
	containers[name] = container
	-- In Edit Mode the game can swap in made-up auras. Our Edit Mode samples
	-- draw their own icons, so real frames keep showing real auras and tooltips.
	container:SetEditModePreviewEnabled(false)
	if frame.unit then
		container:SetUnit(frame.unit)
	end
	Spend(started)
	return container
end

-- Points every container at the frame's unit and refreshes it.
function AuraHost.Refresh(frame, unit)
	local containers = frame.AuraContainers
	if not containers then
		return
	end
	for _, container in pairs(containers) do
		container:SetUnit(unit)
		container:UpdateAllAuras()
	end
end

-- New groups and slots can't be added in combat. The frame sets itself up
-- again once combat ends, so a setting turned on mid-fight still applies.
local function RetryAfterCombat(container)
	local frame = container.owner
	if frame then
		Combat:Run(Combat:Key(frame, "auraRetry"), frame.Configure, frame)
	end
end

-- Adds a group once; afterwards it's only reconfigured.
function AuraHost.EnsureGroup(container, key, filter, initialize)
	if container.groups[key] then
		return true
	end
	if InCombatLockdown() then
		RetryAfterCombat(container)
		return false
	end
	local started = debugprofilestop()
	container:AddAuraGroup(key, filter, {
		initializeFrame = initialize,
		sortMethod = SortDefault,
		sortDirection = SortNormal,
		maxFrameCount = 0,
	})
	container.groups[key] = true
	Spend(started)
	return true
end

function AuraHost.EnsureSlot(container, key, filter, initialize, candidates)
	if container.slots[key] then
		return true
	end
	if InCombatLockdown() then
		RetryAfterCombat(container)
		return false
	end
	local started = debugprofilestop()
	container:AddAuraSlot(key, filter, {
		initializeFrame = initialize,
		candidateFilters = candidates,
		sortMethod = SortDefault,
		sortDirection = SortNormal,
	})
	container.slots[key] = true
	Spend(started)
	return true
end

---------------------------------------------------------------------------
-- Button styling (runs inside Blizzard's wrapper when a button is created)
---------------------------------------------------------------------------

-- Debuff colors keyed by dispel type, as the container expects. A type
-- missing from the map gets the game's own color instead, so every type has
-- an entry. Forever has no DebuffTypeColor table: the colors come from the
-- game's AuraUtil, with the classic ones if that's ever missing.
local CLASSIC_DISPEL_COLORS = {
	Magic = { 0.2, 0.6, 1 },
	Curse = { 0.6, 0, 1 },
	Disease = { 0.6, 0.4, 0 },
	Poison = { 0, 0.6, 0 },
}
local DISPEL_COLORS
local function DispelColors()
	if not DISPEL_COLORS then
		DISPEL_COLORS = {}
		local gameColor = AuraUtil and AuraUtil.GetAuraBorderColor
		for kind, classic in pairs(CLASSIC_DISPEL_COLORS) do
			local color = gameColor and gameColor(kind)
			if color then
				DISPEL_COLORS[kind] = CreateColor(color.r, color.g, color.b, 1)
			else
				DISPEL_COLORS[kind] = CreateColor(classic[1], classic[2], classic[3], 1)
			end
		end
		DISPEL_COLORS.None = CreateColor(0.8, 0, 0, 1)
	end
	return DISPEL_COLORS
end
AuraHost.DispelColors = DispelColors

-- Countdown numbers only appear below a number of seconds: the text color's
-- alpha comes from a step curve over the remaining time.
local countdownCurves = {}
local function CountdownCurve(seconds)
	local curve = countdownCurves[seconds]
	if not curve then
		curve = C_CurveUtil.CreateColorCurve()
		curve:SetType(Enum.LuaCurveType.Step)
		curve:AddPoint(0, CreateColor(1, 0.82, 0, 1))
		curve:AddPoint(seconds, CreateColor(1, 0.82, 0, 0))
		countdownCurves[seconds] = curve
	end
	return curve
end

local function WantsSwirl(mine)
	local mode = ns.db.auras.spirals
	return mode == "all" or (mode == "mine" and mine)
end

local function WantsCountdown(mine)
	local mode = ns.db.auras.countdown
	return mode == "all" or (mode == "mine" and mine)
end

local function ApplyButtonPrefs(button)
	local general = ns.db.general
	button.Cooldown:SetDrawSwipe(WantsSwirl(button.mine))
	button.Time:SetShown(WantsCountdown(button.mine))
	button:SetMouseMotionEnabled(general.auraTooltips ~= "never")
	button:SetHideTooltipInCombat(not general.auraTooltipsInCombat)
end

local function InitButton(button, harmful, mine, stealable)
	button.mine = mine

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button:SetIcon(icon)

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetReverse(true)
	cooldown:SetDrawEdge(false)
	cooldown:SetHideCountdownNumbers(true)
	button:SetDurationCooldown(cooldown)
	button.Cooldown = cooldown

	-- Fonts must be set before the bindings, which write text immediately.
	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", 2, -1)
	button:SetApplicationCount(count)

	local time = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	time:SetPoint("CENTER", 0, 0)
	button:SetDurationText(time, {
		textColor = { curve = CountdownCurve(ns.db.auras.countdownStart), property = RemainingDuration },
	})
	button.Time = time

	if harmful then
		local border = button:CreateTexture(nil, "OVERLAY")
		border:SetTexture(Media.DEBUFF_BORDER)
		border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
		border:SetPoint("TOPLEFT", -1, 1)
		border:SetPoint("BOTTOMRIGHT", 1, -1)
		button:AddDispelTypeTexture(border, {
			style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
			showWhenHarmful = true,
			showWithoutDispelType = true,
			customDispelColorMap = DispelColors(),
		})
	end

	if stealable then
		-- X-Perl's spinning arrows around buffs you can purge or steal.
		local ring = button:CreateTexture(nil, "OVERLAY")
		ring:SetTexture(Media.STEAL)
		ring:SetBlendMode("ADD")
		ring:SetPoint("TOPLEFT", -5, 5)
		ring:SetPoint("BOTTOMRIGHT", 5, -5)
		local spin = ring:CreateAnimationGroup()
		spin:SetLooping("REPEAT")
		local rotation = spin:CreateAnimation("Rotation")
		rotation:SetDegrees(-360)
		rotation:SetDuration(4)
		spin:Play()
	end

	button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT")
	ApplyButtonPrefs(button)
end

-- One initializer per kind of group, made once and shared by every frame.
local initializers = {}
local function Initializer(harmful, mine, stealable)
	local key = (harmful and "h" or "b") .. (mine and "m" or "") .. (stealable and "s" or "")
	local initialize = initializers[key]
	if not initialize then
		initialize = function(button)
			InitButton(button, harmful, mine, stealable)
		end
		initializers[key] = initialize
	end
	return initialize
end

-- The game places aura buttons but never sizes them: a layout's elementWidth
-- only sets how much room a button takes up. Buttons can be made at any time,
-- even mid-fight, so each one reads the group's current size as it's made.
local function SizedInitializer(container, group, cancelable)
	local style = Initializer(group.harmful, group.mine, group.stealable)
	local key = group.key
	return function(button)
		local size = container.sizes[key]
		button:SetSize(size, size)
		style(button)
		if cancelable then
			button:SetCancelAuraButtons("RightButtonUp")
		end
	end
end

---------------------------------------------------------------------------
-- Which groups a frame shows (pure; see tests)
---------------------------------------------------------------------------

local BIG = 1.4

local function Round(value)
	return math.floor(value + 0.5)
end

-- Returns an ordered list of groups for a frame's aura settings. Every group
-- costs ten aura buttons up front (the game builds them in a batch), so
-- frames that only ever show friends (you, your pet, your party) skip the
-- groups that only matter on enemies: buffs you can remove, and your own
-- debuffs shown larger.
--
-- Each aura has to land in exactly one group. "PLAYER" and "!PLAYER" split
-- them cleanly into yours and everyone else's. The isFromPlayerOrPlayerPet
-- field can't do that: it's about any player, not just you.
function AuraHost.Groups(auras, global, hostile)
	local groups = {}
	local function Add(key, filter, candidates, size, harmful, mine, stealable)
		groups[#groups + 1] = {
			key = key, filter = filter, candidates = candidates, size = Round(size),
			harmful = harmful, mine = mine, stealable = stealable,
			notMine = filter:find("!PLAYER", 1, true) ~= nil,
		}
	end

	if auras.buffs then
		local size = auras.buffSize
		local bigSize = global.bigOwn and size * BIG or size
		if auras.buffFilter == "castable" then
			Add("buffs", "HELPFUL|RAID", nil, size, false, false, false)
		elseif auras.buffFilter == "mine" then
			Add("buffsMine", "HELPFUL|PLAYER", nil, bigSize, false, true, false)
		else
			local steal = hostile and global.markStealable
			if steal then
				Add("stealable", "HELPFUL", { isStealable = true }, bigSize, false, false, true)
			end
			local notStealable = steal and { isStealable = false } or nil
			if global.bigOwn then
				Add("buffsMine", "HELPFUL|PLAYER", notStealable, bigSize, false, true, false)
				Add("buffs", "HELPFUL|!PLAYER", notStealable, size, false, false, false)
			else
				Add("buffs", "HELPFUL", notStealable, size, false, false, false)
			end
		end
	end

	if auras.debuffs then
		local first = #groups + 1
		local size = auras.debuffSize
		local bigSize = global.bigOwn and size * BIG or size
		if auras.debuffFilter == "dispellable" then
			Add("debuffs", "HARMFUL|RAID", nil, size, true, false, false)
		elseif auras.debuffFilter == "mine" then
			Add("debuffsMine", "HARMFUL|PLAYER", nil, bigSize, true, true, false)
		elseif global.bigOwn and hostile then
			Add("debuffsMine", "HARMFUL|PLAYER", nil, bigSize, true, true, false)
			Add("debuffs", "HARMFUL|!PLAYER", nil, size, true, false, false)
		else
			Add("debuffs", "HARMFUL", nil, size, true, false, false)
		end
		if groups[first] then
			groups[first].newLine = true
		end
	end
	return groups
end

local ALL_GROUPS = { "stealable", "buffsMine", "buffs", "debuffsMine", "debuffs", "raid" }

-- Space between icons, and between icons and the frame.
local ICON_GAP = 2

-- How far a row of icons can run: from the stats box, where it starts, to the
-- frame's right edge. With the portrait on the left, that's less than the
-- frame's full width.
local function LineWidth(rects)
	return rects.width - rects.statsBox.x
end

local function MaxIcons(group, lineWidth, rows)
	local perRow = math.max(1, math.floor(lineWidth / math.max(group.size + ICON_GAP, 1)))
	return group.max or perRow * rows
end

-- How much room a frame's icons need with every group full, laid out the way
-- the game's flow layout does it. Frames can't resize to fit their auras, so
-- the party leaves this much space between members.
function AuraHost.RoomNeeded(groups, rects, rows)
	local lineWidth = LineWidth(rects)
	local height, lineHeight, used = 0, 0, 0
	local function NextLine()
		if lineHeight > 0 then
			height = height + lineHeight + ICON_GAP
		end
		lineHeight, used = 0, 0
	end
	for _, group in ipairs(groups) do
		local count = MaxIcons(group, lineWidth, rows)
		if group.newLine and count > 0 then
			NextLine()
		end
		for _ = 1, count do
			if used > 0 and used + group.size > lineWidth then
				NextLine()
			end
			used = used + group.size + ICON_GAP
			lineHeight = math.max(lineHeight, group.size)
		end
	end
	local total = height + lineHeight
	return total > 0 and total + ICON_GAP * 2 or 0
end

---------------------------------------------------------------------------
-- The element
---------------------------------------------------------------------------

local Auras = ns.Element("Auras", {
	-- Blizzard's container listens for aura changes itself; we only refresh
	-- when the unit changes, and on poll ticks for units without events.
	poll = true,
})

function Auras.Enabled(frame, conf)
	if frame.spec.layout == "Raid" then
		return conf.icons ~= "none"
	end
	local auras = conf.auras
	return auras ~= nil and (auras.buffs or auras.debuffs or auras.weaponEnchants)
end

function Auras.Create(frame)
	frame.auraGroups = {}
end

local function RaidGroups(conf)
	local filter
	if conf.icons == "buffs" then
		filter = conf.iconsFilter and "HELPFUL|RAID" or "HELPFUL"
	else
		filter = conf.iconsFilter and "HARMFUL|RAID" or "HARMFUL"
	end
	return { { key = "raid", filter = filter, size = 10, harmful = conf.icons == "debuffs", max = 8 } }
end

-- Shaman totems sit right below your frame, so icons going down start under them.
local function TotemRowHeight(frame)
	local row = frame.TotemRow
	return row and row:IsShown() and row.height + 2 or 0
end

-- Where the container sits. It isn't an aura button, so this works even
-- while auras are secret (a battleground match, say), when the rest of the
-- layout has to wait.
local function AnchorContainer(frame, conf, container)
	container:ClearAllPoints()
	if frame.spec.layout == "Raid" then
		local position = conf.iconPosition
		if position == "right" then
			container:SetPoint("TOPLEFT", frame.StatsBox, "TOPRIGHT", 1, -2)
		elseif position == "below" then
			container:SetPoint("TOPLEFT", frame.StatsBox, "BOTTOMLEFT", 2, -1)
		else
			container:SetPoint("BOTTOMRIGHT", frame.StatsBox, "BOTTOMRIGHT", -3, 3)
		end
	elseif conf.auras.onTop then
		container:SetPoint("BOTTOMLEFT", frame.NameBox, "TOPLEFT", 2, 2)
	else
		container:SetPoint("TOPLEFT", frame.StatsBox, "BOTTOMLEFT", 2, -2 - TotemRowHeight(frame))
	end
end

local function PlaceContainer(frame, conf, container)
	AnchorContainer(frame, conf, container)
	if frame.spec.layout == "Raid" then
		local position = conf.iconPosition
		container:SetFlowLayoutAnchorPoint(position == "inside" and "BOTTOMRIGHT" or "TOPLEFT")
		container:SetFlowLayoutGrowthDirection(position == "inside" and AnchorUtil.FlowDirection.Left or FlowRight, FlowDown)
		return
	end
	if conf.auras.onTop then
		container:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
		container:SetFlowLayoutGrowthDirection(FlowRight, FlowUp)
	else
		container:SetFlowLayoutAnchorPoint("TOPLEFT")
		container:SetFlowLayoutGrowthDirection(FlowRight, FlowDown)
	end
end

-- Temporary weapon enchants, like poisons, live on your own frame only. The game
-- keeps them apart from auras: each hand has its own button, placed in the same
-- flow, ahead of your buffs.
local ENCHANT_SLOTS = { "MainHand", "OffHand", "Ranged" }
local ENCHANT_GROUP = { key = "enchants", harmful = false, mine = true, stealable = false }

local function EnchantSize(auras)
	return Round(ns.db.auras.bigOwn and auras.buffSize * BIG or auras.buffSize)
end

local function ConfigureEnchants(conf, container)
	local wanted = conf.auras.weaponEnchants == true
	if not (wanted or container.enchantSlots) then
		return
	end
	container.enchantSlots = container.enchantSlots or {}
	container.sizes.enchants = EnchantSize(conf.auras)
	Combat:Run(Combat:Key(container, "enchants"), function()
		local initialize = SizedInitializer(container, ENCHANT_GROUP, true)
		for _, name in ipairs(ENCHANT_SLOTS) do
			local slot = AuraContainerItemEnchantmentSlot[name]
			if wanted and not container.enchantSlots[slot] then
				container:AddItemEnchantment(slot, { initializeFrame = initialize })
				container.enchantSlots[slot] = true
			end
			if container.enchantSlots[slot] then
				container:SetItemEnchantmentEnabled(slot, wanted)
			end
		end
	end)
end

function Auras.Configure(frame, conf)
	frame.auraGroups = frame.spec.layout == "Raid" and RaidGroups(conf) or AuraHost.Groups(conf.auras, ns.db.auras, frame.spec.hostile)
	if frame.preview then
		return
	end
	local container = AuraHost.Get(frame)
	if not container then
		return
	end

	-- What to show changes right away; filters are evaluated by the game.
	local lineWidth = LineWidth(frame.rects)
	local rows = conf.auras and conf.auras.rows or 1
	local used = {}
	-- Only your own buffs can be canceled, so only your own frame offers it.
	local yours = frame.kind == "player"
	for _, group in ipairs(frame.auraGroups) do
		container.sizes[group.key] = group.size
		local initialize = SizedInitializer(container, group, yours and not group.harmful)
		if AuraHost.EnsureGroup(container, group.key, group.filter, initialize) then
			used[group.key] = true
			container:SetAuraGroupFilterString(group.key, group.filter)
			container:SetAuraGroupCandidateFilters(group.key, group.candidates)
			container:SetAuraGroupMaxFrameCount(group.key, MaxIcons(group, lineWidth, rows))
		end
	end
	for _, key in ipairs(ALL_GROUPS) do
		if container.groups[key] and not used[key] then
			container:SetAuraGroupMaxFrameCount(key, 0)
		end
	end
	if yours then
		ConfigureEnchants(conf, container)
	end
	container:SetEnabled(true)

	-- Sizes and placement resize aura buttons, which the game only allows
	-- while auras aren't secret, so they wait for that if needed. The
	-- container itself is anchored now either way.
	AnchorContainer(frame, conf, container)
	Combat:RunAuraSafe(container, AuraHost.ApplyLayout, frame, conf, container)
end

function AuraHost.ApplyLayout(frame, conf, container)
	PlaceContainer(frame, conf, container)
	container:SetFlowLayoutMaximumLineSize(LineWidth(frame.rects))
	for index, group in ipairs(frame.auraGroups) do
		if container.groups[group.key] then
			container:SetAuraGroupLayout(group.key, {
				elementWidth = group.size,
				elementHeight = group.size,
				elementSpacing = ICON_GAP,
				lineSpacing = ICON_GAP,
				forceNewLine = group.newLine or false,
				layoutIndex = index,
			})
		end
	end
	if container.enchantSlots then
		local size = container.sizes.enchants
		container:SetItemEnchantmentLayout({
			elementWidth = size,
			elementHeight = size,
			elementSpacing = ICON_GAP,
			lineSpacing = ICON_GAP,
		})
	end
	AuraHost.RestyleButtons(container)
end

local function RestyleButton(button, size)
	if button and button.Cooldown then
		button:SetSize(size, size)
		ApplyButtonPrefs(button)
		button:SetDurationText(button.Time, {
			textColor = { curve = CountdownCurve(ns.db.auras.countdownStart), property = RemainingDuration },
		})
	end
end

function AuraHost.RestyleButtons(container)
	for key in pairs(container.groups) do
		local count = container:GetAuraGroupFrameCount(key)
		local size = container.sizes[key]
		for i = 1, count do
			RestyleButton(container:GetAuraGroupFrame(key, i), size)
		end
	end
	for slot in pairs(container.enchantSlots or {}) do
		RestyleButton(container:GetItemEnchantmentFrame(slot), container.sizes.enchants)
	end
end

function Auras.Disable(frame)
	local container = frame.AuraContainers and frame.AuraContainers.icons
	if container then
		for _, key in ipairs(ALL_GROUPS) do
			if container.groups[key] then
				container:SetAuraGroupMaxFrameCount(key, 0)
			end
		end
		for slot in pairs(container.enchantSlots or {}) do
			container:SetItemEnchantmentEnabled(slot, false)
		end
	end
	if frame.PreviewAuras then
		for _, icon in ipairs(frame.PreviewAuras) do
			icon:Hide()
		end
	end
end

-- Containers update themselves; UnitFrame refreshes them when the unit
-- behind the frame changes (see UnitFrame:Flush).
function Auras.Update()
end

-- Mirrors the filter strings for sample auras in the options window.
local function SampleMatches(group, aura)
	if aura.enchant or (aura.harmful and true or false) ~= (group.harmful and true or false) then
		return false
	end
	if group.key == "stealable" then
		return aura.stealable and true or false
	end
	if (group.mine and not aura.mine) or (group.notMine and aura.mine) then
		return false
	end
	local candidates = group.candidates
	if candidates and candidates.isStealable == false and aura.stealable then
		return false
	end
	return true
end

-- Previews draw plain icons, since the container only shows real auras.
function Auras.Preview(frame, sample)
	local icons = frame.PreviewAuras
	if not icons then
		icons = {}
		frame.PreviewAuras = icons
	end
	for _, icon in ipairs(icons) do
		icon:Hide()
	end
	local conf = frame:Conf()
	local list = sample.auras or {}
	local x, y, rowHeight = ICON_GAP, -ICON_GAP - TotemRowHeight(frame), 0
	local lineWidth = LineWidth(frame.rects)
	local count = 0

	local function Draw(aura, size)
		count = count + 1
		local icon = icons[count]
		if not icon then
			icon = frame.Content:CreateTexture(nil, "ARTWORK")
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			icons[count] = icon
		end
		if x + size > lineWidth then
			x, y, rowHeight = ICON_GAP, y - rowHeight - ICON_GAP, 0
		end
		icon:SetTexture(C_Spell.GetSpellTexture(aura.spell) or 134400)
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		if frame.spec.layout ~= "Raid" and conf.auras.onTop then
			icon:SetPoint("BOTTOMLEFT", frame.NameBox, "TOPLEFT", x, -y)
		else
			icon:SetPoint("TOPLEFT", frame.StatsBox, "BOTTOMLEFT", x, y)
		end
		icon:Show()
		x = x + size + ICON_GAP
		rowHeight = math.max(rowHeight, size)
	end

	if conf.auras and conf.auras.weaponEnchants then
		for _, aura in ipairs(list) do
			if aura.enchant then
				Draw(aura, EnchantSize(conf.auras))
			end
		end
	end
	for _, group in ipairs(frame.auraGroups) do
		if group.newLine and x > ICON_GAP then
			x, y, rowHeight = ICON_GAP, y - rowHeight - ICON_GAP, 0
		end
		for _, aura in ipairs(list) do
			if SampleMatches(group, aura) then
				Draw(aura, group.size)
			end
		end
	end
end
