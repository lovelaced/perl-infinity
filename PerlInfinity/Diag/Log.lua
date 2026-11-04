-- Diagnostics that are always on and cheap: our own Lua errors and any
-- blocked or forbidden actions blamed on Perl Infinity are recorded into PerlInfinityLog,
-- which the game writes to disk on /reload or logout.
--
-- SavedVariables may not hold secret values, so everything passes through
-- Scrub before it's stored. We never replace the game's error handler; our
-- handlers run inside ns.Call, which records the error and then hands it on
-- to whatever handler is installed (BugSack, or the game's own).
local _, ns = ...

local Log = ns:NewModule("Log")

local issecretvalue, canaccesstable = issecretvalue, canaccesstable
local debugstack, date = debugstack, date
local geterrorhandler, xpcall, type, tostring, pairs = geterrorhandler, xpcall, type, tostring, pairs

local MAX_ERRORS = 100
local MAX_SESSIONS = 10
local MAX_STRING = 500

local pending = {} -- errors raised before SavedVariables load
local db -- PerlInfinityLog once loaded

-- Which element or frame is updating right now, so errors can say where.
Log.current = nil

---------------------------------------------------------------------------
-- Scrubbing
---------------------------------------------------------------------------

local function Scrub(value, depth)
	if issecretvalue(value) then
		return "<secret>"
	end
	local kind = type(value)
	if kind == "string" then
		if #value > MAX_STRING then
			return value:sub(1, MAX_STRING) .. "..."
		end
		return value
	elseif kind == "number" or kind == "boolean" or kind == "nil" then
		return value
	elseif kind == "table" then
		if depth <= 0 or (canaccesstable and not canaccesstable(value)) then
			return "<table>"
		end
		local copy, count = {}, 0
		for key, entry in pairs(value) do
			if not issecretvalue(key) then
				count = count + 1
				if count > 50 then
					break
				end
				local keyKind = type(key)
				if keyKind ~= "string" and keyKind ~= "number" then
					key = tostring(key)
				end
				copy[key] = Scrub(entry, depth - 1)
			end
		end
		return copy
	end
	return "<" .. kind .. ">"
end
Log.Scrub = Scrub

---------------------------------------------------------------------------
-- Context
---------------------------------------------------------------------------

local RESTRICTION_NAMES = {}

local function Context()
	local context = {
		combat = InCombatLockdown(),
		where = Log.current,
		time = date("%Y-%m-%d %H:%M:%S"),
	}
	local _, instanceType = IsInInstance()
	context.instance = instanceType
	if C_RestrictedActions and Enum.AddOnRestrictionType then
		local active
		for name, value in pairs(Enum.AddOnRestrictionType) do
			if C_RestrictedActions.IsAddOnRestrictionActive(value) then
				active = (active and active .. "," or "") .. (RESTRICTION_NAMES[value] or name)
			end
		end
		context.restricted = active
	end
	return context
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local function Record(bucket, key, entry)
	local list = db[bucket]
	local existing = list[key]
	if existing then
		existing.count = existing.count + 1
		existing.last = entry.context.time
		return
	end
	local unique = db.counts[bucket] or 0
	if unique >= MAX_ERRORS then
		db.dropped = db.dropped + 1
		return
	end
	db.counts[bucket] = unique + 1
	entry.count = 1
	entry.first = entry.context.time
	entry.last = entry.context.time
	list[key] = entry
end

local function TrimStack(stack)
	if type(stack) ~= "string" then
		return ""
	end
	stack = stack:gsub("Interface/AddOns/", ""):gsub("Interface\\AddOns\\", "")
	local lines, count = {}, 0
	for line in stack:gmatch("[^\n]+") do
		count = count + 1
		if count > 8 then
			break
		end
		lines[count] = line
	end
	return table.concat(lines, "\n")
end

function Log:Error(message, stack)
	if issecretvalue(message) then
		message = "<secret error message>"
	end
	message = tostring(message)
	local entry = { message = Scrub(message, 0), stack = TrimStack(stack), context = Context() }
	if not db then
		pending[#pending + 1] = entry
		return
	end
	local key = message:match("^[^\n]*") .. "|" .. (entry.stack:match("^[^\n]*") or "")
	Record("errors", key, entry)
end

-- Things that aren't errors but that I want to see when reading a session,
-- such as an event the client doesn't know about.
function Log:Note(kind, detail)
	if not db then
		return
	end
	local notes = db.notes
	local key = kind .. ":" .. tostring(Scrub(detail, 0))
	if notes[key] then
		notes[key] = notes[key] + 1
	elseif (db.counts.notes or 0) < MAX_ERRORS then
		db.counts.notes = (db.counts.notes or 0) + 1
		notes[key] = 1
	end
end

---------------------------------------------------------------------------
-- Protected calls
---------------------------------------------------------------------------

local function OnError(message)
	Log:Error(message, debugstack(2))
	local handler = geterrorhandler()
	if handler then
		handler(message)
	end
	return message
end

-- Runs fn(...) and records any error without stopping the caller.
function ns.Call(fn, ...)
	return xpcall(fn, OnError, ...)
end

---------------------------------------------------------------------------
-- Session bookkeeping
---------------------------------------------------------------------------

local function NewSession()
	local build, buildNumber, _, toc = GetBuildInfo()
	local _, class = UnitClass("player")
	return {
		started = date("%Y-%m-%d %H:%M:%S"),
		addon = ns.version,
		build = build .. "." .. buildNumber,
		toc = toc,
		class = Scrub(class, 0),
		level = Scrub(UnitLevel("player"), 0),
		counters = {},
	}
end

function Log:Init()
	PerlInfinityLog = type(PerlInfinityLog) == "table" and PerlInfinityLog or {}
	db = PerlInfinityLog
	db.errors = db.errors or {}
	db.blocked = db.blocked or {}
	db.notes = db.notes or {}
	db.counts = db.counts or {}
	db.dropped = db.dropped or 0
	db.sessions = db.sessions or {}
	db.census = db.census or {}
	db.loads = (db.loads or 0) + 1

	for _, entry in ipairs(pending) do
		local key = entry.message .. "|" .. (entry.stack:match("^[^\n]*") or "")
		Record("errors", key, entry)
	end
	pending = nil

	local sessions = db.sessions
	sessions[#sessions + 1] = NewSession()
	while #sessions > MAX_SESSIONS do
		table.remove(sessions, 1)
	end
	self.session = sessions[#sessions]

	for name, value in pairs(Enum.AddOnRestrictionType or {}) do
		RESTRICTION_NAMES[value] = name
	end

	local frame = CreateFrame("Frame")
	frame:RegisterEvent("ADDON_ACTION_BLOCKED")
	frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	frame:RegisterEvent("PLAYER_LOGOUT")
	frame:SetScript("OnEvent", function(_, event, culprit, functionName)
		if event == "PLAYER_LOGOUT" then
			self.session.ended = date("%Y-%m-%d %H:%M:%S")
			if self.OnLogout then
				ns.Call(self.OnLogout, self)
			end
			return
		end
		if culprit ~= ns.name then
			return
		end
		local entry = {
			kind = event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden",
			func = Scrub(functionName, 0),
			stack = TrimStack(debugstack(3)),
			context = Context(),
		}
		Record("blocked", entry.kind .. ":" .. tostring(entry.func) .. ":" .. tostring(Log.current), entry)
	end)
end

-- Counts things per session (events, flushes) for the CPU picture.
function Log:Count(name, amount)
	local counters = self.session and self.session.counters
	if counters then
		counters[name] = (counters[name] or 0) + (amount or 1)
	end
end

function Log:Clear()
	if db then
		wipe(db.errors)
		wipe(db.blocked)
		wipe(db.notes)
		wipe(db.counts)
		db.dropped = 0
	end
end

function Log:ErrorCount()
	return db and ((db.counts.errors or 0) + (db.counts.blocked or 0)) or 0
end

function Log:DB()
	return db
end
