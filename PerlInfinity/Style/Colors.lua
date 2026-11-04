-- Colors from settings, cached as ColorMixins so updates never allocate.
-- Health colors by percent are color curves the game evaluates for us, since
-- health is a secret number we can't compare.
local _, ns = ...

local Colors = ns:NewModule("Colors")
local Secret = ns.Secret

local cache = {}

-- ColorMixin for a hex setting such as "ff00ff00".
function Colors.Hex(hex)
	local color = cache[hex]
	if not color then
		color = CreateColorFromHexString(hex)
		cache[hex] = color
	end
	return color
end

function Colors.Look(key)
	return Colors.Hex(ns.db.look[key])
end

---------------------------------------------------------------------------
-- Health
---------------------------------------------------------------------------

local healthCurve

-- The original Perl gradient: green at full, through yellow, to red.
local function BuildHealthCurve()
	local look = ns.db.look
	if look.healthColor == "custom" then
		healthCurve = Secret.ColorCurve({
			{ 0, Colors.Hex(look.healthLow) },
			{ 1, Colors.Hex(look.healthFull) },
		})
	else
		healthCurve = Secret.ColorCurve({
			{ 0, CreateColor(1, 0, 0) },
			{ 0.5, CreateColor(1, 1, 0) },
			{ 1, CreateColor(0, 1, 0) },
		})
	end
end

function Colors.HealthCurve()
	if not healthCurve then
		BuildHealthCurve()
	end
	return healthCurve
end

---------------------------------------------------------------------------
-- Class and reaction
---------------------------------------------------------------------------

-- r, g, b for a class token (which may be secret), with the brightness
-- setting applied when the color is readable.
function Colors.Class(token)
	local r, g, b = Secret.ClassRGB(token)
	if r and not Secret.Is(r) then
		local brightness = ns.db.look.classBrightness
		if brightness ~= 1 then
			r, g, b = math.min(r * brightness, 1), math.min(g * brightness, 1), math.min(b * brightness, 1)
		end
	end
	return r, g, b
end

-- UnitReaction returns 1-8 and is never secret.
local REACTION_KEYS = {
	"hostile", "hostile", "unfriendly", "neutral", "friendly", "friendly", "friendly", "friendly",
}

function Colors.Reaction(unit)
	if UnitIsTapDenied(unit) then
		return Colors.Look("tapped")
	end
	local reaction = UnitReaction(unit, "player")
	local key = reaction and REACTION_KEYS[reaction] or "noReaction"
	return Colors.Look(key)
end

---------------------------------------------------------------------------
-- Power
---------------------------------------------------------------------------

local POWER_KEYS = {
	MANA = "mana",
	RAGE = "rage",
	ENERGY = "energy",
	FOCUS = "focus",
	HAPPINESS = "happiness",
}

-- Color for a power token from UnitPowerType (never secret).
function Colors.Power(token)
	local key = POWER_KEYS[token]
	if key then
		return Colors.Look(key)
	end
	local color = PowerBarColor and PowerBarColor[token]
	if color then
		return color
	end
	return Colors.Look("mana")
end

function Colors:Init()
	ns.Config:Subscribe("look", self, function()
		healthCurve = nil
	end)
end
