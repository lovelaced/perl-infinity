-- Named profiles. Each character picks one; new characters start with
-- PerlInfinityDB.newCharacterProfile. Profiles only hold settings that differ from
-- the defaults, which also keeps export strings short.
--
-- Frame positions are not part of profiles. They belong to the Edit Mode
-- layout (PerlInfinityDB.positions), so switching profiles never moves frames.
local _, ns = ...

local Profiles = ns:NewModule("Profiles")
local Config = ns.Config
local Util = ns.Util

local EXPORT_PREFIX = "PERLINFINITY1:"

local function DB()
	return Config:DB()
end

function Profiles:List()
	local names = {}
	for name in pairs(DB().profiles) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

function Profiles:Exists(name)
	return DB().profiles[name] ~= nil
end

function Profiles:Active()
	return Config:ProfileName()
end

function Profiles:Use(name)
	if not self:Exists(name) then
		return false
	end
	PerlInfinityCharDB.profile = name
	Config:Rebuild()
	return true
end

-- Creates a profile, copying `source` (a profile name) or starting empty.
function Profiles:Create(name, source)
	if name == "" or self:Exists(name) then
		return false
	end
	DB().profiles[name] = source and Util.DeepCopy(DB().profiles[source] or {}) or {}
	return true
end

function Profiles:Copy(from, to)
	if not self:Exists(from) or not self:Exists(to) then
		return false
	end
	DB().profiles[to] = Util.DeepCopy(DB().profiles[from])
	if to == self:Active() then
		Config:Rebuild()
	end
	return true
end

function Profiles:Rename(old, new)
	if new == "" or not self:Exists(old) or self:Exists(new) then
		return false
	end
	local db = DB()
	db.profiles[new], db.profiles[old] = db.profiles[old], nil
	if db.newCharacterProfile == old then
		db.newCharacterProfile = new
	end
	if PerlInfinityCharDB.profile == old then
		PerlInfinityCharDB.profile = new
	end
	-- Other characters pointing at the old name fall back to the new-character
	-- profile next time they log in.
	return true
end

function Profiles:Delete(name)
	local db = DB()
	if not self:Exists(name) or #self:List() <= 1 then
		return false
	end
	db.profiles[name] = nil
	if db.newCharacterProfile == name then
		db.newCharacterProfile = self:List()[1]
	end
	if PerlInfinityCharDB.profile == name then
		PerlInfinityCharDB.profile = db.newCharacterProfile
		Config:Rebuild()
	end
	return true
end

function Profiles:Reset(name)
	if not self:Exists(name) then
		return false
	end
	wipe(DB().profiles[name])
	if name == self:Active() then
		Config:Rebuild()
	end
	return true
end

---------------------------------------------------------------------------
-- Export and import
---------------------------------------------------------------------------

function Profiles:Export(name, includePositions)
	local payload = {
		schema = Config.SCHEMA,
		settings = DB().profiles[name] or {},
	}
	if includePositions then
		payload.positions = DB().positions
	end
	local serialized = C_EncodingUtil.SerializeCBOR(payload)
	local compressed = C_EncodingUtil.CompressString(serialized, Enum.CompressionMethod.Deflate)
	return EXPORT_PREFIX .. C_EncodingUtil.EncodeBase64(compressed)
end

-- Keeps only keys that exist in the defaults, with the same type.
local function Validate(settings, defaults)
	local clean = {}
	for key, value in pairs(settings) do
		local default = defaults[key]
		if default ~= nil and type(value) == type(default) then
			if type(value) == "table" then
				clean[key] = Validate(value, default)
			else
				clean[key] = value
			end
		end
	end
	return clean
end

-- Returns the decoded payload, or nil and a reason ("format" or "newer").
function Profiles:Decode(text)
	text = strtrim(text or "")
	if text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then
		return nil, "format"
	end
	local ok, payload = pcall(function()
		local compressed = C_EncodingUtil.DecodeBase64(text:sub(#EXPORT_PREFIX + 1))
		local serialized = C_EncodingUtil.DecompressString(compressed, Enum.CompressionMethod.Deflate)
		return C_EncodingUtil.DeserializeCBOR(serialized)
	end)
	if not ok or type(payload) ~= "table" or type(payload.settings) ~= "table" then
		return nil, "format"
	end
	if (payload.schema or 0) > Config.SCHEMA then
		return nil, "newer"
	end
	payload.settings = Validate(payload.settings, ns.Defaults)
	return payload
end

function Profiles:Import(name, payload, usePositions)
	if name == "" or self:Exists(name) then
		return false
	end
	DB().profiles[name] = payload.settings
	if usePositions and type(payload.positions) == "table" then
		DB().positions = payload.positions
		ns.Movers:ApplyAll()
	end
	return true
end
