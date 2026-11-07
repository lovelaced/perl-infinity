-- Helpers for Forever's secret values.
--
-- Many unit values (health, power, auras in combat, other people's casts,
-- some names) arrive as "secrets": we can hand them to Blizzard's display
-- functions but can't compare them, do math on them, or branch on them.
-- These helpers keep the patterns in one place:
--   * show or hide with alpha, since SetShown refuses a secret boolean
--   * thresholds through step curves evaluated by the game
--   * class colors through C_ClassColor, which accepts a secret class
local _, ns = ...

local Secret = {}
ns.Secret = Secret

local issecretvalue = issecretvalue
local CreateCurve, CreateColorCurve = C_CurveUtil.CreateCurve, C_CurveUtil.CreateColorCurve

function Secret.Is(value)
	return issecretvalue(value)
end

-- A unit's name the way the game writes it: first name and surname for players
-- who have one. The game's own GetUnitName tests the surname, which addon code
-- can't do when it's secret, but secret strings can still be joined.
function Secret.UnitFullName(unit)
	local name, surname = UnitName(unit)
	if issecretvalue(surname) or (surname and surname ~= "") then
		return name .. Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR .. surname
	end
	return name
end

-- Returns the value when it's readable, otherwise nil.
function Secret.Plain(value)
	if issecretvalue(value) then
		return nil
	end
	return value
end

-- Shows `region` when `condition` is true, using alpha so a secret boolean
-- works. The region itself stays Shown.
function Secret.ShowIf(region, condition)
	if condition == nil then
		region:SetAlpha(0)
	else
		region:SetAlphaFromBoolean(condition, 1, 0)
	end
end

-- Like ShowIf, with custom alphas (for example range fading).
function Secret.AlphaIf(region, condition, alphaIfTrue, alphaIfFalse)
	if condition == nil then
		region:SetAlpha(alphaIfFalse)
	else
		region:SetAlphaFromBoolean(condition, alphaIfTrue, alphaIfFalse)
	end
end

---------------------------------------------------------------------------
-- Curves
---------------------------------------------------------------------------

local stepCurves = {}

-- A curve that returns `below` for x < threshold and `above` from the
-- threshold up. Built once per combination and cached.
function Secret.StepCurve(threshold, below, above)
	local key = threshold .. ":" .. below .. ":" .. above
	local curve = stepCurves[key]
	if not curve then
		curve = CreateCurve()
		curve:SetType(Enum.LuaCurveType.Step)
		curve:AddPoint(0, below)
		curve:AddPoint(threshold, above)
		stepCurves[key] = curve
	end
	return curve
end

-- Alpha curve that hides something at full health (x == 1).
function Secret.HideAtFull()
	return Secret.StepCurve(0.9999, 1, 0)
end

-- Alpha curve that shows something only below a fraction, used by the
-- low health warning and similar.
function Secret.ShowBelow(fraction)
	return Secret.StepCurve(fraction, 1, 0)
end

-- Builds a color curve from a list of { x, color } points.
function Secret.ColorCurve(points)
	local curve = CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Linear)
	for i = 1, #points do
		curve:AddPoint(points[i][1], points[i][2])
	end
	return curve
end

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------

-- Returns r, g, b for a class token that may be secret. Falls back to the
-- game's class colors when the token can't be read.
function Secret.ClassRGB(classToken, customColors)
	if classToken == nil then
		return nil
	end
	if not issecretvalue(classToken) then
		local color = (customColors and customColors[classToken]) or RAID_CLASS_COLORS[classToken]
		if color then
			return color.r, color.g, color.b
		end
		return nil
	end
	local color = C_ClassColor.GetClassColor(classToken)
	if color then
		return color:GetRGB()
	end
	return nil
end
