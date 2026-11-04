-- tests/harness/curves.lua
-- Userdata-style API objects: curves (real Linear/Step/Cosine interpolation),
-- color curves, CurveConstants, boolean->color helpers, duration objects, the heal
-- prediction calculator and number/seconds formatters. Methods enforce the
-- SecretArguments tags of their doc tables (Curve:Evaluate(secret) errors).

local Secret = require("secret")
local Api = require("api")

local C = {}

-- Build a method table for an object type: documented methods become stubs, impl
-- overrides; every call checks secret arguments against the doc entry.
function C.objectClass(h, typeName, impl)
  local methods = {}
  local chain = h.tags.widgetTypes[typeName] or {}
  local function entryFor(m)
    for _, doc in ipairs(chain) do
      local d = h.tags.objects[doc]
      if d and d[m] then return d[m] end
    end
  end
  local function wrap(m, f)
    local entry = entryFor(m)
    local label = typeName .. ":" .. m
    return function(self, ...)
      if entry then Api.checkSecretArgs(label, entry, ...) end
      return f(self, ...)
    end
  end
  for _, doc in ipairs(chain) do
    for m in pairs(h.tags.objects[doc] or {}) do
      if not methods[m] then methods[m] = wrap(m, function() end) end
    end
  end
  for m, f in pairs(impl) do methods[m] = wrap(m, f) end
  return { __index = methods, __metatable = typeName }
end

local function lerp(a, b, t) return a + (b - a) * t end

-- Evaluate a curve at x (x must be plain). Returns number or color table.
function C.evaluate(curve, x)
  local pts = curve.points
  if #pts == 0 then return curve.isColor and nil or 0 end
  local function val(p) return p.y end
  if x <= pts[1].x then return val(pts[1]) end
  if x >= pts[#pts].x then return val(pts[#pts]) end
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    if x >= a.x and x < b.x then
      if curve.type == 1 then return val(a) end -- Step: points promote on exact match
      local t = (x - a.x) / (b.x - a.x)
      if curve.type == 2 then t = (1 - math.cos(t * math.pi)) / 2 end
      if curve.isColor then
        return { r = lerp(a.y.r, b.y.r, t), g = lerp(a.y.g, b.y.g, t), b = lerp(a.y.b, b.y.b, t),
          a = lerp(a.y.a or 1, b.y.a or 1, t) }
      end
      return lerp(a.y, b.y, t)
    end
  end
  return val(pts[#pts])
end

function C.install(h)
  local env = h.env
  local raw = Secret.raw
  local CreateColor = env.CreateColor

  ---------------------------------------------------------------------------
  -- Curves
  ---------------------------------------------------------------------------
  local function asColor(v)
    if type(v) ~= "table" then return v end
    return CreateColor(v.r, v.g, v.b, v.a)
  end
  local curveImpl = {
    SetType = function(self, t) self.type = t end,
    GetType = function(self) return self.type end,
    AddPoint = function(self, x, y)
      if type(x) ~= "number" then error("Curve:AddPoint: x must be a number", 2) end
      local p = { x = x, y = y }
      local pts = self.points
      local i = #pts + 1
      for j, q in ipairs(pts) do if x < q.x then i = j; break end end
      table.insert(pts, i, p)
    end,
    ClearPoints = function(self) self.points = {} end,
    RemovePoint = function(self, i) table.remove(self.points, i) end,
    GetPointCount = function(self) return #self.points end,
    GetPoint = function(self, i) local p = self.points[i]; if p then return { x = p.x, y = p.y } end end,
    GetPoints = function(self)
      local r = {}
      for i, p in ipairs(self.points) do r[i] = { x = p.x, y = p.y } end
      return r
    end,
    SetPoints = function(self, pts)
      self.points = {}
      for _, p in ipairs(pts) do self:AddPoint(p.x or p[1], p.y or p[2]) end
    end,
    Copy = function(self)
      local c = setmetatable({ points = {}, type = self.type, isColor = self.isColor, __isCurve = true }, getmetatable(self))
      for i, p in ipairs(self.points) do c.points[i] = { x = p.x, y = p.y } end
      return c
    end,
    Evaluate = function(self, x)
      local v = C.evaluate(self, x)
      if self.isColor then return asColor(v) end
      return v
    end,
    EvaluateUnpacked = function(self, x)
      local v = C.evaluate(self, x)
      if v then return v.r, v.g, v.b, v.a or 1 end
    end,
    HasSecretValues = function() return false end,
    SetToDefaults = function(self) self.points, self.type = {}, 0 end,
    Reset = function(self) self.points = {} end,
  }
  local CurveMT = C.objectClass(h, "LuaCurveObject", curveImpl)
  local ColorCurveMT = C.objectClass(h, "LuaColorCurveObject", curveImpl)
  h.isCurve = function(v)
    local m = getmetatable(v)
    return m == "LuaCurveObject" or m == "LuaColorCurveObject"
  end
  env.C_CurveUtil = env.C_CurveUtil or {}
  Api.set(h, "C_CurveUtil.CreateCurve", function()
    return setmetatable({ points = {}, type = 0, __isCurve = true }, CurveMT)
  end)
  Api.set(h, "C_CurveUtil.CreateColorCurve", function()
    return setmetatable({ points = {}, type = 0, isColor = true, __isCurve = true }, ColorCurveMT)
  end)
  Api.set(h, "C_CurveUtil.EvaluateColorFromBoolean", function(b, ifTrue, ifFalse)
    local c = raw(b) and ifTrue or ifFalse
    if Secret.is(b) and c then
      return CreateColor(Secret.wrap(c.r), Secret.wrap(c.g), Secret.wrap(c.b), Secret.wrap(c.a or 1))
    end
    return c
  end)
  Api.set(h, "C_CurveUtil.EvaluateColorValueFromBoolean", function(b, ifTrue, ifFalse)
    local v = raw(b) and ifTrue or ifFalse
    if Secret.is(b) then return Secret.wrap(v) end
    return v
  end)

  local function constCurve(points)
    local c = env.C_CurveUtil.CreateCurve()
    c:SetType(env.Enum.LuaCurveType.Linear)
    for _, p in ipairs(points) do c:AddPoint(p[1], p[2]) end
    return c
  end
  env.CurveConstants = {
    ZeroToOne = constCurve({ { 0, 0 }, { 1, 1 } }),
    ScaleTo100 = constCurve({ { 0, 0 }, { 1, 100 } }),
    Reverse = constCurve({ { 0, 1 }, { 1, 0 } }),
    ReverseTo100 = constCurve({ { 0, 100 }, { 1, 0 } }),
  }

  -- Evaluate a plain x through a curve for an API that takes a curve argument;
  -- result is secret when `secret` is true. Colors come back as ColorMixin.
  function h.evalCurveResult(curve, x, secret)
    if curve == nil then
      if secret then return Secret.wrap(x) end
      return x
    end
    if type(curve) ~= "table" or not curve.__isCurve then error("expected a curve object", 3) end
    local v = C.evaluate(curve, x)
    if curve.isColor then
      if not v then return nil end
      if secret then return CreateColor(Secret.wrap(v.r), Secret.wrap(v.g), Secret.wrap(v.b), Secret.wrap(v.a or 1)) end
      return CreateColor(v.r, v.g, v.b, v.a)
    end
    if secret then return Secret.wrap(v) end
    return v
  end

  ---------------------------------------------------------------------------
  -- Duration objects
  ---------------------------------------------------------------------------
  local function out(self, v)
    if self.__secretValues then return Secret.wrap(v) end
    return v
  end
  local durImpl = {
    SetTimeFromStart = function(self, start, dur, modRate) self.start, self.dur, self.modRate = start, dur, modRate or 1 end,
    SetTimeFromEnd = function(self, finish, dur, modRate) self.start, self.dur, self.modRate = finish - dur, dur, modRate or 1 end,
    SetTimeSpan = function(self, start, finish) self.start, self.dur = start, finish - start end,
    Reset = function(self) self.start, self.dur, self.__secretValues = 0, 0, nil end,
    SetToDefaults = function(self) self.start, self.dur, self.__secretValues = 0, 0, nil end,
    Assign = function(self, other) self.start, self.dur, self.modRate, self.__secretValues = other.start, other.dur, other.modRate, other.__secretValues end,
    Copy = function(self)
      local c = env.C_DurationUtil.CreateDuration()
      c:Assign(self)
      return c
    end,
    IsZero = function(self) return out(self, self.dur == 0) end,
    HasSecretValues = function(self) return self.__secretValues == true end,
    GetStartTime = function(self) return out(self, self.start) end,
    GetEndTime = function(self) return out(self, self.start + self.dur) end,
    GetTotalDuration = function(self) return out(self, self.dur) end,
    GetElapsedDuration = function(self) return out(self, math.max(0, math.min(self.dur, h.clock - self.start))) end,
    GetRemainingDuration = function(self) return out(self, math.max(0, self.start + self.dur - h.clock)) end,
    GetElapsedPercent = function(self) return out(self, self.dur > 0 and math.min(1, (h.clock - self.start) / self.dur) or 0) end,
    GetRemainingPercent = function(self) return out(self, self.dur > 0 and math.max(0, 1 - (h.clock - self.start) / self.dur) or 0) end,
    HasExpired = function(self) return out(self, h.clock >= self.start + self.dur) end,
    HasStarted = function(self) return out(self, h.clock >= self.start) end,
    IsActive = function(self) return out(self, h.clock >= self.start and h.clock < self.start + self.dur) end,
    GetModRate = function(self) return out(self, self.modRate or 1) end,
    EvaluateRemainingPercent = function(self, curve)
      local p = self.dur > 0 and math.max(0, 1 - (h.clock - self.start) / self.dur) or 0
      return h.evalCurveResult(curve, p, self.__secretValues)
    end,
    EvaluateElapsedPercent = function(self, curve)
      local p = self.dur > 0 and math.min(1, (h.clock - self.start) / self.dur) or 0
      return h.evalCurveResult(curve, p, self.__secretValues)
    end,
    EvaluateRemainingDuration = function(self, curve)
      return h.evalCurveResult(curve, math.max(0, self.start + self.dur - h.clock), self.__secretValues)
    end,
    EvaluateElapsedDuration = function(self, curve)
      return h.evalCurveResult(curve, math.max(0, h.clock - self.start), self.__secretValues)
    end,
    FormatRemainingDuration = function(self, formatter)
      local s = formatter and formatter.Format and formatter:Format(math.max(0, self.start + self.dur - h.clock))
        or string.format("%d", math.max(0, self.start + self.dur - h.clock))
      return out(self, raw(s))
    end,
  }
  local DurationMT = C.objectClass(h, "LuaDurationObject", durImpl)
  env.C_DurationUtil = env.C_DurationUtil or {}
  local function newDuration(start, dur, secret)
    return setmetatable({ start = start or 0, dur = dur or 0, modRate = 1, __isDuration = true,
      __secretValues = secret or nil }, DurationMT)
  end
  h.newDuration = newDuration
  Api.set(h, "C_DurationUtil.CreateDuration", function() return newDuration(0, 0) end)

  ---------------------------------------------------------------------------
  -- Heal prediction calculator (values filled by UnitGetDetailedHealPrediction)
  ---------------------------------------------------------------------------
  local function cv(self, v) if self.__secretValues then return Secret.wrap(v) end return v end
  local calcImpl = {
    SetIncomingHealClampMode = function(self, m) self.incomingClamp = m end,
    GetIncomingHealClampMode = function(self) return self.incomingClamp or 0 end,
    SetDamageAbsorbClampMode = function(self, m) self.absorbClamp = m end,
    GetDamageAbsorbClampMode = function(self) return self.absorbClamp or 0 end,
    SetHealAbsorbClampMode = function(self, m) self.healAbsorbClamp = m end,
    GetHealAbsorbClampMode = function(self) return self.healAbsorbClamp or 0 end,
    SetHealAbsorbMode = function(self, m) self.healAbsorbMode = m end,
    GetHealAbsorbMode = function(self) return self.healAbsorbMode or 0 end,
    SetIncomingHealOverflowPercent = function(self, p) self.overflow = p end,
    GetIncomingHealOverflowPercent = function(self) return self.overflow or 1 end,
    SetMaximumHealthMode = function(self, m) self.maxHealthMode = m end,
    GetMaximumHealthMode = function(self) return self.maxHealthMode or 0 end,
    HasSecretValues = function(self) return self.__secretValues == true end,
    ResetPredictedValues = function(self) self.v = nil end,
    GetIncomingHeals = function(self)
      local v = self.v or {}
      return cv(self, v.heals or 0), cv(self, v.fromHealer or 0), cv(self, v.fromOthers or 0), cv(self, v.healsClamped or false)
    end,
    GetDamageAbsorbs = function(self) local v = self.v or {}; return cv(self, v.absorbs or 0), cv(self, v.absorbsClamped or false) end,
    GetHealAbsorbs = function(self) local v = self.v or {}; return cv(self, v.healAbsorbs or 0), cv(self, false) end,
    GetMaximumHealth = function(self) return cv(self, (self.v or {}).maxHealth or 0) end,
    GetCurrentHealth = function(self) return cv(self, (self.v or {}).health or 0) end,
    GetMissingHealth = function(self) local v = self.v or {}; return cv(self, (v.maxHealth or 0) - (v.health or 0)) end,
    GetCurrentHealthPercent = function(self) local v = self.v or {}; return cv(self, (v.maxHealth or 0) > 0 and v.health / v.maxHealth or 0) end,
    GetTotalIncomingHeals = function(self) return cv(self, (self.v or {}).rawHeals or 0) end,
    GetTotalDamageAbsorbs = function(self) return cv(self, (self.v or {}).rawAbsorbs or 0) end,
    GetTotalHealAbsorbs = function(self) return cv(self, (self.v or {}).healAbsorbs or 0) end,
    EvaluateCurrentHealthPercent = function(self, curve)
      local v = self.v or {}
      return h.evalCurveResult(curve, (v.maxHealth or 0) > 0 and v.health / v.maxHealth or 0, self.__secretValues)
    end,
  }
  local CalcMT = C.objectClass(h, "UnitHealPredictionCalculator", calcImpl)
  Api.set(h, "CreateUnitHealPredictionCalculator", function()
    return setmetatable({ __isCalculator = true }, CalcMT)
  end)
  h.fillHealCalculator = function(calc, u, healerIsPlayer)
    if type(calc) ~= "table" or not calc.__isCalculator then error("expected a heal prediction calculator", 3) end
    local missing = u.maxHealth - u.health
    local heals = u.incomingHeals or 0
    local fromHealer = healerIsPlayer and (u.incomingHealsFromPlayer or 0) or 0
    local clampedHeals = heals > missing
    local healsShown = calc.incomingClamp == 1 and math.min(heals, u.maxHealth) or math.min(heals, missing)
    local absorbs = u.absorbs or 0
    local room = (calc.absorbClamp == 2) and u.maxHealth or math.max(0, missing - healsShown)
    calc.v = {
      heals = healsShown, fromHealer = math.min(fromHealer, healsShown), fromOthers = math.max(0, healsShown - fromHealer),
      healsClamped = clampedHeals, absorbs = math.min(absorbs, room), absorbsClamped = absorbs > room,
      healAbsorbs = u.healAbsorbs or 0, maxHealth = u.maxHealth, health = u.health, rawHeals = heals, rawAbsorbs = absorbs,
    }
    calc.__secretValues = h.mode ~= "open" or nil
  end

  ---------------------------------------------------------------------------
  -- Formatters
  ---------------------------------------------------------------------------
  local function fmtSeconds(s)
    if s >= 3600 then return string.format("%dh", math.floor(s / 3600)) end
    if s >= 90 then return string.format("%dm", math.floor(s / 60)) end
    return string.format("%d", math.floor(s))
  end
  local secondsImpl = { Format = function(_, s)
    local o = fmtSeconds(raw(s))
    if Secret.is(s) then return Secret.new("string", o) end
    return o
  end }
  local SecondsMT = C.objectClass(h, "SecondsFormatter", secondsImpl)
  Api.set(h, "C_StringUtil.CreateSecondsFormatter", function() return setmetatable({}, SecondsMT) end)
  local abbrevImpl = { Format = function(_, n) return env.AbbreviateNumbers(n) end }
  local AbbrevMT = C.objectClass(h, "AbbreviatedNumberFormatter", abbrevImpl)
  Api.set(h, "C_StringUtil.CreateAbbreviatedNumberFormatter", function() return setmetatable({}, AbbrevMT) end)
  local BindingMT = C.objectClass(h, "DurationTextBinding", {})
  Api.set(h, "C_DurationUtil.CreateDurationTextBinding", function() return setmetatable({}, BindingMT) end)
end

return C
