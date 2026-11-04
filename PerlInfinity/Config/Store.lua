-- The settings store.
--
-- ns.db is the resolved view: the defaults with the active profile laid on
-- top. Frames read it directly (ns.db.player.scale). Changes go through
-- Config:Set so the profile stays sparse and everyone who cares is told:
--
--   Config:Get("party.auras.buffSize")
--   Config:Set("party.auras.buffSize", 24)
--   Config:Subscribe("party", owner, function(owner, path, value) end)
--
-- Subscribers matching a changed path are called right away; frames just mark
-- themselves for a reconfigure and let the Scheduler batch the work.
local _, ns = ...

local Config = ns:NewModule("Config")
local Util = ns.Util

local SCHEMA = 1

local subscribers = {} -- array of { prefix, owner, fn }
local db, charDB

Config.SCHEMA = SCHEMA

local function Resolve()
	local view = Util.DeepCopy(ns.Defaults)
	Util.DeepMerge(view, Config:Profile())
	ns.db = view
end

local function Matches(prefix, path)
	if prefix == "" then
		return true
	end
	local n = #prefix
	if path:sub(1, n) == prefix and (#path == n or path:sub(n + 1, n + 1) == ".") then
		return true
	end
	-- A whole section changed (path is a prefix of the subscriber's prefix).
	local m = #path
	return prefix:sub(1, m) == path and prefix:sub(m + 1, m + 1) == "."
end

local function Notify(path, value)
	for i = 1, #subscribers do
		local sub = subscribers[i]
		if Matches(sub.prefix, path) then
			ns.Call(sub.fn, sub.owner, path, value)
		end
	end
end

function Config:Subscribe(prefix, owner, fn)
	subscribers[#subscribers + 1] = { prefix = prefix, owner = owner, fn = fn }
end

function Config:Unsubscribe(owner)
	local kept = {}
	for i = 1, #subscribers do
		if subscribers[i].owner ~= owner then
			kept[#kept + 1] = subscribers[i]
		end
	end
	subscribers = kept
end

function Config:Get(path)
	return Util.GetPath(ns.db, path)
end

function Config:GetDefault(path)
	return Util.GetPath(ns.Defaults, path)
end

function Config:Set(path, value)
	local default = self:GetDefault(path)
	if default ~= nil and type(value) ~= type(default) then
		error(("Perl Infinity setting %s expects a %s, got %s"):format(path, type(default), type(value)), 2)
	end
	local profile = self:Profile()
	if Util.DeepEqual(value, default) then
		Util.SetPath(profile, path, nil)
		Util.Prune(profile)
	else
		Util.SetPath(profile, path, Util.DeepCopy(value))
	end
	Util.SetPath(ns.db, path, Util.DeepCopy(value))
	Notify(path, value)
end

-- Puts every setting under `prefix` back to its default ("" for all).
function Config:Reset(prefix)
	local profile = self:Profile()
	if prefix == "" then
		wipe(profile)
	else
		Util.SetPath(profile, prefix, nil)
		Util.Prune(profile)
	end
	Resolve()
	Notify(prefix, nil)
end

---------------------------------------------------------------------------
-- Profiles live in PerlInfinityDB.profiles; each character remembers which one it
-- uses in PerlInfinityCharDB.profile. See Config/Profiles.lua for management.
---------------------------------------------------------------------------

function Config:ProfileName()
	local name = charDB.profile
	if not name or not db.profiles[name] then
		name = db.newCharacterProfile
		if not db.profiles[name] then
			name = next(db.profiles)
		end
		charDB.profile = name
	end
	return name
end

function Config:Profile()
	return db.profiles[self:ProfileName()]
end

function Config:Rebuild()
	Resolve()
	Notify("", nil)
end

function Config:DB()
	return db
end

local function Migrate()
	-- Each step upgrades every profile by one schema version.
	local steps = {}
	local from = db.schema or SCHEMA
	for version = from + 1, SCHEMA do
		local step = steps[version]
		if step then
			for _, profile in pairs(db.profiles) do
				step(profile)
			end
		end
	end
	db.schema = SCHEMA
end
Config.Migrate = Migrate

function Config:Init()
	PerlInfinityDB = type(PerlInfinityDB) == "table" and PerlInfinityDB or {}
	PerlInfinityCharDB = type(PerlInfinityCharDB) == "table" and PerlInfinityCharDB or {}
	db, charDB = PerlInfinityDB, PerlInfinityCharDB

	db.profiles = db.profiles or {}
	if next(db.profiles) == nil then
		db.profiles.Default = {}
	end
	db.newCharacterProfile = db.newCharacterProfile or "Default"
	db.positions = db.positions or {}
	db.raidLayouts = db.raidLayouts or {}
	db.global = db.global or {}

	Migrate()
	Resolve()
end
