-- /perlinfinity taintwatch: a development tool that finds where taint came from.
--
-- A blocked action only shows where taint ended up, often long after it spread.
-- This records the moment Blizzard's own state turns tainted, with who did it,
-- the call stack when we can catch the write, and what was going on at the time.
-- It's off by default and costs nothing until you turn it on. The setting
-- survives a reload, and everything is saved to PerlInfinityLog.taintWatch.
local _, ns = ...

local TaintWatch = ns:NewModule("TaintWatch")
local Log = ns.Log
local L = ns.L

local issecurevariable, issecretvalue, canaccesstable = issecurevariable, issecretvalue, canaccesstable
local debugstack, date, next, pairs, pcall, rawget, tostring, type = debugstack, date, next, pairs, pcall, rawget, tostring, type

local TICK = 0.1
local GLOBALS_PER_TICK = 4000
local TICKS_PER_TREE_SCAN = 10
local TREE_DEPTH = 8
local TABLE_DEPTH = 2
local MAX_FINDINGS = 300
local MAX_RUNS = 5
local MAX_CRUMBS = 12
local MAX_CHAT = 25
local MAX_STACK = 2000

-- Globals Blizzard replaces outright, and reads without securecall in places.
-- One tainted write here taints every later reader. Blizzard's action button
-- code says these are "vulnerable to taint from talent and spellbook code".
local MARKS = { "PET_ACTION_HIGHLIGHT_MARKS", "ON_BAR_HIGHLIGHT_MARKS", "ACTION_HIGHLIGHT_MARKS" }

-- Blizzard frames and tables whose fields we check, one each tick.
local ROOTS = {
	"EditModeManagerFrame", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft",
	"MultiBarRight", "MultiBar5", "MultiBar6", "MultiBar7", "PetActionBar", "StanceBar", "PossessActionBar",
	"MicroMenuContainer", "UIParentBottomManagedFrameContainer", "UIParentRightManagedFrameContainer",
	"ActionBarButtonEventsFrame", "ActionBarActionEventsFrame", "ActionButton1", "MultiBarBottomLeftButton1",
	"MultiBarBottomLeftButton12", "PetActionButton1", "PlayerCastingBarFrame", "PartyFrame", "GameTooltip",
	"EventRegistry", "PlayerSpellsFrame",
}

-- What's open when something turns tainted.
local PANELS = {
	"PlayerSpellsFrame", "EditModeManagerFrame", "SettingsPanel", "GameMenuFrame", "PerlInfinityOptionsFrame",
	"QuestFrame", "GossipFrame", "MerchantFrame", "CharacterFrame", "LFGListFrame",
}

-- Things that happened recently, kept as a trail of breadcrumbs.
local EVENTS = {
	"PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "PLAYER_SPECIALIZATION_CHANGED", "GROUP_ROSTER_UPDATE",
	"EDIT_MODE_LAYOUTS_UPDATED", "SPELL_PUSHED_TO_ACTIONBAR", "SPELLS_CHANGED", "ACTIONBAR_SLOT_CHANGED",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_LOADED", "CINEMATIC_START", "CINEMATIC_STOP",
	"UNIT_PET",
}

-- Names we create on purpose. Being tainted is expected for these.
local OURS = {
	"^PerlInfinity", "^PERLINFINITY", "^SLASH_PERLINFINITY", "^BINDING_NAME_PERLINFINITY",
	"^BINDING_HEADER_PERLINFINITY", "^LibStub$", "^ClickCastFrames$",
}

local active = false
local hooked = false
local run -- this session's findings
local ticker
local crumbs = {}
local chatted = 0
local blockedSeen = {}
local rootIndex = 0
local globalKey
local ticks = 0

local function Store()
	local db = Log:DB()
	if not db then
		return nil
	end
	db.taintWatch = db.taintWatch or { runs = {} }
	return db.taintWatch
end

local function Say(message, ...)
	if chatted < MAX_CHAT then
		chatted = chatted + 1
		ns.Print(message, ...)
	end
end

local function MouseFocus()
	local ok, name = pcall(function()
		local focus = GetMouseFoci and GetMouseFoci()[1]
		return focus and focus:GetDebugName()
	end)
	return ok and name or nil
end

local function OpenPanels()
	local open = {}
	for _, name in ipairs(PANELS) do
		local frame = _G[name]
		if frame and frame.IsShown and frame:IsShown() then
			open[#open + 1] = name
		end
	end
	return #open > 0 and table.concat(open, ", ") or nil
end

local function Crumb(event)
	local last = crumbs[#crumbs]
	if last and last.event == event then
		last.time = date("%H:%M:%S")
		return
	end
	crumbs[#crumbs + 1] = { event = event, time = date("%H:%M:%S") }
	if #crumbs > MAX_CRUMBS then
		table.remove(crumbs, 1)
	end
end

local function CrumbTrail()
	local trail = {}
	for i, crumb in ipairs(crumbs) do
		trail[i] = crumb.time .. " " .. crumb.event
	end
	return table.concat(trail, ", ")
end

-- Records the first time something is seen tainted this session. Scans find
-- the same thing over and over, so only a new name or a first stack is news.
local function Report(what, by, stack, alert)
	if not run then
		return
	end
	local entry = run.findings[what]
	if entry then
		if stack and not entry.stack then
			entry.stack = stack:sub(1, MAX_STACK)
		end
		return
	end
	if run.total >= MAX_FINDINGS then
		run.dropped = run.dropped + 1
		return
	end
	run.total = run.total + 1
	entry = {
		by = Log.Scrub(by, 0),
		time = date("%H:%M:%S"),
		level = Log.Scrub(UnitLevel("player"), 0),
		group = IsInRaid() and "raid" or IsInGroup() and "party" or "solo",
		combat = InCombatLockdown() or nil,
		mouse = MouseFocus(),
		open = OpenPanels(),
		crumbs = CrumbTrail(),
		stack = stack and stack:sub(1, MAX_STACK) or nil,
	}
	run.findings[what] = entry
	if alert or stack then
		Say(L.MSG_TAINTWATCH_FOUND, what, tostring(entry.by), entry.mouse or L.MSG_TAINTWATCH_NOTHING)
	end
end

local function IsOurs(name)
	for _, pattern in ipairs(OURS) do
		if name:find(pattern) then
			return true
		end
	end
	return false
end

local function WalkTable(name, tbl, depth)
	for key, value in pairs(tbl) do
		if not issecretvalue(key) then
			local kind = type(key)
			if kind == "string" or kind == "number" then
				if kind == "number" or not key:find("^perlInfinity") then
					local secure, by = issecurevariable(tbl, key)
					if not secure then
						Report(name .. "." .. key, by)
					end
				end
				-- Widgets hold a userdata at [0]. They get their own scan.
				if depth > 0 and not issecretvalue(value) and type(value) == "table" and rawget(value, 0) == nil
					and (not canaccesstable or canaccesstable(value)) then
					WalkTable(name .. "." .. key, value, depth - 1)
				end
			end
		end
	end
end

local function ScanRoot(name)
	local root = _G[name]
	if type(root) == "table" then
		pcall(WalkTable, name, root, TABLE_DEPTH)
	end
end

-- Every Edit Mode system is a Blizzard frame the blocked actions ran through.
local function ScanSystems()
	local manager = EditModeManagerFrame
	local systems = manager and manager.registeredSystemFrames
	if type(systems) == "table" then
		for _, frame in pairs(systems) do
			if type(frame) == "table" and frame.GetDebugName then
				pcall(WalkTable, frame:GetDebugName(), frame, 0)
			end
		end
	end
end

local function WalkTree(frame, depth)
	if frame.IsForbidden and frame:IsForbidden() then
		return
	end
	if frame.GetDebugName then
		WalkTable(frame:GetDebugName(), frame, 0)
	end
	if depth > 0 and frame.GetChildren then
		for _, child in ipairs({ frame:GetChildren() }) do
			WalkTree(child, depth - 1)
		end
	end
end

-- The spellbook's spell buttons come from pools, so walk them while it's open.
local function ScanSpellbook()
	local frame = PlayerSpellsFrame
	if frame and frame:IsShown() then
		pcall(WalkTree, frame, TREE_DEPTH)
	end
end

-- Walks all of _G a slice at a time so a scan never causes a hitch.
local function ScanGlobals()
	local key = globalKey
	for _ = 1, GLOBALS_PER_TICK do
		key = next(_G, key)
		if key == nil then
			break
		end
		if type(key) == "string" and not IsOurs(key) then
			local secure, by = issecurevariable(key)
			if not secure then
				Report(key, by)
			end
		end
	end
	globalKey = key
end

local function Tick()
	if not active then
		return
	end
	for _, name in ipairs(MARKS) do
		local secure, by = issecurevariable(name)
		if not secure then
			Report(name, by, nil, true)
		end
	end
	rootIndex = rootIndex + 1
	if ROOTS[rootIndex] then
		ScanRoot(ROOTS[rootIndex])
	else
		rootIndex = 0
		ScanSystems()
	end
	if not pcall(ScanGlobals) then
		globalKey = nil
	end
	ticks = ticks + 1
	if ticks >= TICKS_PER_TREE_SCAN then
		ticks = 0
		ScanSpellbook()
	end
end

-- Runs right after Blizzard writes one of these, so a tainted write comes with
-- the stack that made it. That stack is the whole point of this file.
local function WatchWrite(ownerName, method, read)
	local owner = ownerName and _G[ownerName]
	if ownerName and not owner then
		return
	end
	if type((owner or _G)[method]) ~= "function" then
		return
	end
	local function After(...)
		if active then
			local what, secure, by = read(...)
			if not secure then
				Report(what, by, debugstack(2))
			end
		end
	end
	if owner then
		hooksecurefunc(owner, method, After)
	else
		hooksecurefunc(method, After)
	end
end

local function ReadGlobal(name)
	return function()
		local secure, by = issecurevariable(name)
		return name, secure, by
	end
end

local function ReadField(rootName, key)
	return function()
		local secure, by = issecurevariable(_G[rootName], key)
		return rootName .. "." .. key, secure, by
	end
end

local function HookWrites()
	if hooked then
		return
	end
	hooked = true
	WatchWrite("PetActionBar", "ClearPetActionHighlightMarks", ReadGlobal("PET_ACTION_HIGHLIGHT_MARKS"))
	WatchWrite("PetActionBar", "UpdatePetActionHighlightMarks", ReadGlobal("PET_ACTION_HIGHLIGHT_MARKS"))
	WatchWrite(nil, "ClearOnBarHighlightMarks", ReadGlobal("ON_BAR_HIGHLIGHT_MARKS"))
	WatchWrite(nil, "UpdateOnBarHighlightMarksBySpell", ReadGlobal("ON_BAR_HIGHLIGHT_MARKS"))
	WatchWrite(nil, "UpdateOnBarHighlightMarksByFlyout", ReadGlobal("ON_BAR_HIGHLIGHT_MARKS"))
	WatchWrite(nil, "MarkNewActionHighlight", function(action)
		local secure, by = issecurevariable(ACTION_HIGHLIGHT_MARKS, action)
		return "ACTION_HIGHLIGHT_MARKS[" .. tostring(action) .. "]", secure, by
	end)
	WatchWrite("EditModeManagerFrame", "UpdateLayoutInfo", ReadField("EditModeManagerFrame", "layoutInfo"))
	WatchWrite("EditModeManagerFrame", "OnEditModeSystemAnchorChanged", ReadField("EditModeManagerFrame", "editModeSystemAnchorDirty"))
end

local eventFrame

local function OnEvent(_, event, culprit, functionName)
	if not active then
		return
	end
	if event ~= "ADDON_ACTION_BLOCKED" then
		Crumb(event)
	elseif culprit == ns.name and not blockedSeen[functionName] then
		blockedSeen[functionName] = true
		Say(L.MSG_TAINTWATCH_BLOCKED, tostring(Log.Scrub(functionName, 0)))
	end
end

local function Start()
	local store = Store()
	if not store then
		return
	end
	active = true
	if not run then
		run = { started = date("%Y-%m-%d %H:%M:%S"), findings = {}, total = 0, dropped = 0 }
		local runs = store.runs
		runs[#runs + 1] = run
		while #runs > MAX_RUNS do
			table.remove(runs, 1)
		end
	end
	HookWrites()
	if not eventFrame then
		eventFrame = CreateFrame("Frame")
		for _, event in ipairs(EVENTS) do
			eventFrame:RegisterEvent(event)
		end
		eventFrame:RegisterEvent("ADDON_ACTION_BLOCKED")
		eventFrame:SetScript("OnEvent", OnEvent)
	end
	if not ticker then
		ticker = C_Timer.NewTicker(TICK, Tick)
	end
end

local function Stop()
	active = false
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if eventFrame then
		eventFrame:UnregisterAllEvents()
		eventFrame:SetScript("OnEvent", nil)
		eventFrame = nil
	end
end

function TaintWatch:Toggle()
	local store = Store()
	if not store then
		return
	end
	store.on = not store.on or nil
	if store.on then
		Start()
		ns.Print(L.MSG_TAINTWATCH_ON)
	else
		Stop()
		ns.Print(L.MSG_TAINTWATCH_OFF)
	end
end

function TaintWatch:Login()
	local db = Log:DB()
	local store = db and db.taintWatch
	if store and store.on then
		Start()
		ns.Print(L.MSG_TAINTWATCH_RUNNING)
	end
end
