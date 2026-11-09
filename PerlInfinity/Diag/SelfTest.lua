-- /perlinfinity selftest: one command that checks how Perl Infinity gets on with this build
-- of the game and writes everything to PerlInfinityLog, which the game saves on
-- /reload or logout. "/perlinfinity selftest dev" also forces the game's combat and
-- dungeon restrictions on for a few seconds to see how frames cope.
--
-- Also a passive census: the first fight in the open world, in a dungeon and
-- in a raid each record which values were secret, with no setup needed.
local _, ns = ...

local SelfTest = ns:NewModule("SelfTest")
local Probes, Log = ns.Probes, ns.Log
local L = ns.L

local running
local results

local function Say(message, ...)
	ns.Print(message, ...)
end

local function Step(name, fn)
	local ok, err = pcall(fn)
	results.steps[#results.steps + 1] = { name = name, ok = ok, error = not ok and Log.Scrub(err, 0) or nil }
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------

local function Environment()
	local build, number, _, toc = GetBuildInfo()
	local _, class = UnitClass("player")
	results.env = {
		build = build .. "." .. number,
		toc = toc,
		project = WOW_PROJECT_ID,
		addon = ns.version,
		class = class,
		level = UnitLevel("player"),
		inGroup = IsInGroup(),
		inRaid = IsInRaid(),
		instance = select(2, IsInInstance()),
		profiler = C_AddOnProfiler and C_AddOnProfiler.IsEnabled() or false,
		editMode = EditModeManagerFrame and EditModeManagerFrame:CanEnterEditMode() or false,
		cvars = {
			combat = GetCVar("addonCombatRestrictionsForced"),
			map = GetCVar("addonMapRestrictionsForced"),
		},
	}
end

-- Do Blizzard's display functions take secret values from addon code?
local function Semantics()
	local s = {}
	local holder = CreateFrame("Frame")
	local bar = CreateFrame("StatusBar", nil, holder)
	local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	local texture = holder:CreateTexture()
	local health = UnitHealth("player")
	s.healthSecret = issecretvalue(health)
	s.setValue = Probes.Run(function()
		bar:SetMinMaxValues(0, UnitHealthMax("player"))
		bar:SetValue(health)
	end)
	s.formattedPercent = Probes.Run(function()
		text:SetFormattedText("%.0f%%", UnitHealthPercent("player", true, CurveConstants.ScaleTo100))
	end)
	s.abbreviate = Probes.Run(function()
		text:SetText(AbbreviateNumbers(health))
	end)
	s.textWidthAfterSecret = Probes.Run(function()
		text:SetText(UnitName("player"))
		return text:GetStringWidth()
	end)
	s.alphaFromBoolean = Probes.Run(function()
		texture:SetAlphaFromBoolean(UnitIsAFK("player"), 1, 0)
	end)
	s.spriteCell = Probes.Run(function()
		texture:SetTexture(ns.Media.RAID_ICONS)
		texture:SetSpriteSheetCell(GetRaidTargetIndex("player") or 1, 4, 4)
	end)
	s.colorCurve = Probes.Run(function()
		return UnitHealthPercent("player", true, ns.Colors.HealthCurve())
	end)
	s.colorFromBoolean = Probes.Run(function()
		return C_CurveUtil.EvaluateColorFromBoolean(UnitIsAFK("player"), CreateColor(1, 0, 0), CreateColor(0, 1, 0))
	end)
	s.nilCheckOnSecret = Probes.Run(function()
		if health then
			return true
		end
		return false
	end)
	s.durationBinding = Probes.Run(function()
		local binding = C_DurationUtil.CreateDurationTextBinding()
		binding:SetFontString(text)
		return binding
	end)
	s.rolesets = {}
	for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "PartyFrame", "CompactRaidFrameManager", "BuffFrame", "DebuffFrame" }) do
		local frame = _G[name]
		if frame then
			s.rolesets[name] = (frame.IsRolesetFiltered and frame:IsRolesetFiltered() and "blocked" or "not blocked")
				.. (frame:IsVisible() and ", visible" or ", hidden")
		end
	end
	results.semantics = s
end

local function Structure()
	local frames = {}
	for kind, frame in pairs(ns.Frames.instances) do
		frames[kind] = {
			shown = frame:IsShown(),
			elements = #frame.elements,
			containers = frame.AuraContainers and true or false,
		}
	end
	local headers = {}
	for _, name in ipairs({ "PerlInfinity_PartyHeader", "PerlInfinity_RaidHeader1", "PerlInfinity_RaidPetHeader", "PerlInfinity_TankHeader", "PerlInfinity_HealerHeader" }) do
		local header = _G[name]
		if header then
			headers[name] = { shown = header:IsShown(), children = header.children and #header.children or 0 }
		end
	end
	results.structure = { frames = frames, headers = headers }
end

-- Buttons a group owns, how many are showing, and how wide the first one is.
local function IconCounts(container, key)
	local count = container:GetAuraGroupFrameCount(key)
	local shown = 0
	for i = 1, count do
		local isShown = container:GetAuraGroupFrame(key, i):IsShown()
		if not issecretvalue(isShown) and isShown then
			shown = shown + 1
		end
	end
	local first = container:GetAuraGroupFrame(key, 1)
	return string.format("%d made, %d shown, width %s", count, shown, tostring(Log.Scrub(first and first:GetWidth())))
end

-- What the game says is on a unit, for comparing with the icons. The lists use
-- the same filters as the icons, so an aura in both shows up in both.
local function AuraList(unit, filter)
	local Scrub = Log.Scrub
	local list = {}
	for i, aura in ipairs(C_UnitAuras.GetUnitAuras(unit, filter, 12)) do
		list[i] = string.format("%s (id %s, from a player: %s)", tostring(Scrub(aura.name)),
			tostring(Scrub(aura.auraInstanceID)), tostring(Scrub(aura.isFromPlayerOrPlayerPet)))
	end
	return list
end

local function AuraLists(unit)
	local lists = {}
	for name, filter in pairs({ yourBuffs = "HELPFUL|PLAYER", otherBuffs = "HELPFUL|!PLAYER", debuffs = "HARMFUL" }) do
		local ok, list = pcall(AuraList, unit, filter)
		lists[name] = ok and list or "<hidden while auras are secret>"
	end
	return lists
end

-- What each frame's aura icons were doing when you logged out or reloaded, for
-- working out why a frame shows no buffs or debuffs. Recorded while you're in a
-- group or have icons on your own frame, with your target for comparison.
local function AuraFrameState(frame)
	local Scrub = Log.Scrub
	local unit = frame.unit
	local state = {
		kind = frame.kind,
		unit = unit,
		shown = frame:IsShown(),
		visible = frame:IsVisible(),
		stale = frame.stale,
		waitingForCombat = frame.auraHostPending,
		groupsWanted = frame.auraGroups and #frame.auraGroups,
	}
	if unit then
		state.gameHasBuff = Probes.Run(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HELPFUL")
		state.gameHasDebuff = Probes.Run(C_UnitAuras.GetAuraDataByIndex, unit, 1, "HARMFUL")
		state.auras = AuraLists(unit)
	end
	local container = frame.AuraContainers and frame.AuraContainers.icons
	if container then
		state.anchors = Scrub(container:GetNumPoints())
		state.containerUnit = Scrub(container:GetUnit())
		state.enabled = container:IsEnabled()
		state.containerVisible = container:IsVisible()
		state.icons = {}
		for key in pairs(container.groups) do
			local ok, counts = pcall(IconCounts, container, key)
			state.icons[key] = ok and counts or "<hidden while auras are secret>"
		end
	end
	return state
end

-- Your own frame always has a container for the debuff highlight, so what
-- matters is whether it shows any icons.
local function HasOwnIcons(player)
	return player ~= nil and player.AuraContainers ~= nil and ns.Elements.Auras.Enabled(player, player:Conf())
end

local function RecordAuraFrames(log)
	local player = ns.Frames.instances.player
	local playerIcons = HasOwnIcons(player)
	if not (IsInGroup() or playerIcons) or not log.session then
		return
	end
	local list = {}
	if playerIcons then
		list[#list + 1] = AuraFrameState(player)
	end
	local header = _G.PerlInfinity_PartyHeader
	for _, child in ipairs(header and header.children or {}) do
		if child.unit then
			list[#list + 1] = AuraFrameState(child)
		end
	end
	local target = ns.Frames.instances.target
	if target then
		list[#list + 1] = AuraFrameState(target)
	end
	log.session.auraFrames = {
		combat = InCombatLockdown(),
		aurasSecret = C_Secrets.ShouldAurasBeSecret(),
		layoutsWaiting = ns.Combat:HasAuraPending(),
		buildsWaiting = ns.AuraHost.Waiting(),
		frames = list,
	}
end

-- Asks every frame to redraw everything, which surfaces any secret misuse.
local function RefreshAll()
	for _, frame in pairs(ns.Frames.instances) do
		frame:UpdateAll(true)
		frame:Flush()
	end
	for _, name in ipairs({ "PerlInfinity_PartyHeader", "PerlInfinity_RaidHeader1" }) do
		local header = _G[name]
		if header and header.children then
			for _, child in ipairs(header.children) do
				if child.unit then
					child:UpdateAll(true)
					child:Flush()
				end
			end
		end
	end
end

local function Cpu()
	local cpu = {}
	local frame = ns.Frames.instances.player
	if frame then
		local started = debugprofilestop()
		for _ = 1, 200 do
			frame:UpdateAll()
			frame:Flush()
		end
		cpu.playerFullUpdateMs = (debugprofilestop() - started) / 200
	end
	local target = ns.Frames.instances.target
	if target and target.unit and UnitExists("target") then
		local started = debugprofilestop()
		for _ = 1, 200 do
			target:UpdateAll()
			target:Flush()
		end
		cpu.targetFullUpdateMs = (debugprofilestop() - started) / 200
	end
	if C_AddOnProfiler and C_AddOnProfiler.IsEnabled() and Enum.AddOnProfilerMetric then
		for name, metric in pairs(Enum.AddOnProfilerMetric) do
			cpu["addon_" .. name] = C_AddOnProfiler.GetAddOnMetric(ns.name, metric)
		end
	end
	cpu.scheduler = CopyTable(ns.Scheduler.stats)
	cpu.pollerRunning = ns.Poller:IsRunning()
	cpu.memoryKB = (UpdateAddOnMemoryUsage() or true) and GetAddOnMemoryUsage(ns.name)
	results.cpu = cpu
end

---------------------------------------------------------------------------
-- Runner
---------------------------------------------------------------------------

local function Finish()
	running = false
	Log:DB().selfTest = Log.Scrub(results, 8)
	local failed = 0
	for _, step in ipairs(results.steps) do
		if not step.ok then
			failed = failed + 1
		end
	end
	Say(L.SELFTEST_DONE:format(#results.steps - failed, failed, #results.missing, Log:ErrorCount()))
end

local function Forced(cvar, label, after)
	local previous = GetCVar(cvar)
	local ok = pcall(SetCVar, cvar, 1)
	if not ok or GetCVar(cvar) ~= "1" then
		results.forced[label] = "refused (type /console " .. cvar .. " 1 to test by hand)"
		after()
		return
	end
	C_Timer.After(1.5, function()
		Step("forced:" .. label, function()
			results.forced[label] = { matrix = Probes.Matrix() }
			RefreshAll()
			Screenshot()
		end)
		pcall(SetCVar, cvar, previous or 0)
		C_Timer.After(1, after)
	end)
end

function SelfTest:Run(dev)
	if running then
		return
	end
	if InCombatLockdown() then
		Say(L.SELFTEST_COMBAT)
		return
	end
	running = true
	results = { started = date("%Y-%m-%d %H:%M:%S"), steps = {}, forced = {}, dev = dev and true or false }
	Say(L.SELFTEST_START)

	Step("environment", Environment)
	Step("manifest", function()
		results.missing = Probes.Manifest()
	end)
	results.missing = results.missing or {}
	Step("matrix", function()
		results.matrix = Probes.Matrix()
	end)
	Step("semantics", Semantics)
	Step("structure", Structure)
	Step("refresh", RefreshAll)
	Step("cpu", Cpu)

	-- Screenshots of the frames and the options window.
	C_Timer.After(0.5, function()
		Screenshot()
		C_Timer.After(1, function()
			Step("options", function()
				ns.Options:Open("player")
			end)
			C_Timer.After(1, function()
				Screenshot()
				C_Timer.After(1, function()
					ns.Options:Open("raid")
					C_Timer.After(1, function()
						Screenshot()
						ns.Options:Toggle()
						if dev then
							Forced("addonCombatRestrictionsForced", "combat", function()
								Forced("addonMapRestrictionsForced", "map", Finish)
							end)
						else
							Finish()
						end
					end)
				end)
			end)
		end)
	end)
end

---------------------------------------------------------------------------
-- Passive census: what was secret on the first fight in each kind of place.
---------------------------------------------------------------------------

local function Context()
	local _, instance = IsInInstance()
	if instance == "party" or instance == "raid" then
		return instance
	end
	return "world"
end

function SelfTest:Login()
	ns.Events:On("PLAYER_REGEN_DISABLED", self, function()
		local census = Log:DB().census
		local context = Context()
		if census[context] then
			return
		end
		C_Timer.After(1.5, function()
			ns.Call(function()
				census[context] = Log.Scrub({ when = date("%Y-%m-%d %H:%M:%S"), matrix = Probes.Matrix() }, 5)
			end)
		end)
	end)
	Log.OnLogout = function(log)
		ns.Call(RecordAuraFrames, log)
		log.session.scheduler = CopyTable(ns.Scheduler.stats)
		log.session.loginMs = ns.loginMs
		if C_AddOnProfiler and C_AddOnProfiler.IsEnabled() and Enum.AddOnProfilerMetric then
			local metrics = {}
			for name, metric in pairs(Enum.AddOnProfilerMetric) do
				metrics[name] = C_AddOnProfiler.GetAddOnMetric(ns.name, metric)
			end
			log.session.profiler = metrics
		end
	end
end

ns.SelfTest = SelfTest
