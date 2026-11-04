-- tools/gen_api_tags.lua
-- Builds tests/harness/api_tags.lua from Blizzard's generated API documentation
-- (Blizzard_APIDocumentationGenerated/*.lua). Each doc file registers itself with
-- APIDocumentation:AddDocumentationTable(t), so we run them in a sandbox with a stub
-- and serialize what they register. The output holds only signature and secret-tag
-- facts (names, types, tags), never Blizzard source.
--
-- usage: luajit tools/gen_api_tags.lua [docDir] [outFile]
--   docDir defaults to $WOW_UI_SOURCE/Blizzard_APIDocumentationGenerated

local UI_ROOT = os.getenv("WOW_UI_SOURCE") or "wow-ui-source/Interface/AddOns"
local docDir = arg[1] or (UI_ROOT .. "/Blizzard_APIDocumentationGenerated")
local outFile = arg[2] or "tests/harness/api_tags.lua"

---------------------------------------------------------------------------
-- Symbolic Enum/Constants: doc files reference Enum.X.Y before the enum tables
-- are known, so we hand out symbols and resolve them after every file is read.
---------------------------------------------------------------------------
local symMT = {}
local function sym(enum, key) return setmetatable({ enum = enum, key = key }, symMT) end
local function binop(op) return function(a, b) return setmetatable({ op = op, a = a, b = b }, symMT) end end
symMT.__add, symMT.__sub, symMT.__mul = binop("+"), binop("-"), binop("*")
symMT.__tostring = function(s) return s.key and ("Enum." .. s.enum .. "." .. s.key) or "<expr>" end
local function isSym(v) return getmetatable(v) == symMT end

local enumValues = {}  -- [enumName][key] = number, filled from Enumeration tables

local function resolve(v)
  if not isSym(v) then return v end
  if v.op then
    local a, b = resolve(v.a), resolve(v.b)
    if type(a) ~= "number" or type(b) ~= "number" then return nil end
    if v.op == "+" then return a + b elseif v.op == "-" then return a - b else return a * b end
  end
  local e = enumValues[v.enum]
  return e and e[v.key]
end

local function symbolicTable(prefix)
  return setmetatable({}, { __index = function(t, k)
    local sub = setmetatable({}, { __index = function(e, kk)
      local s = sym(k, kk); rawset(e, kk, s); return s end })
    rawset(t, k, sub); return sub
  end })
end

---------------------------------------------------------------------------
-- Load every doc file in a sandbox
---------------------------------------------------------------------------
local docs = {}
local sandbox = {
  APIDocumentation = { AddDocumentationTable = function(_, t) docs[#docs + 1] = t end },
  Enum = symbolicTable("Enum"),
  Constants = symbolicTable("Constants"),
  pairs = pairs, ipairs = ipairs, type = type, tostring = tostring, table = table, math = math, string = string,
}

local files = {}
local p = assert(io.popen('ls "' .. docDir .. '"'))
for f in p:lines() do if f:match("%.lua$") then files[#files + 1] = f end end
p:close()
table.sort(files)
if #files == 0 then
  io.stderr:write("gen_api_tags: no doc files in " .. docDir .. "\n")
  os.exit(1)
end

local loadErrors = 0
for _, f in ipairs(files) do
  local fn, err = loadfile(docDir .. "/" .. f)
  if not fn then io.stderr:write(err .. "\n"); loadErrors = loadErrors + 1
  else
    setfenv(fn, sandbox)
    local before = #docs
    local ok, e = pcall(fn)
    if not ok then io.stderr:write(f .. ": " .. tostring(e) .. "\n"); loadErrors = loadErrors + 1 end
    for i = before + 1, #docs do docs[i].__file = f end
  end
end

-- First pass: enum values (needed to resolve defaults and constants)
for _, d in ipairs(docs) do
  for _, t in ipairs(d.Tables or {}) do
    if t.Type == "Enumeration" then
      local e = enumValues[t.Name] or {}
      for _, fld in ipairs(t.Fields or {}) do e[fld.Name] = fld.EnumValue end
      enumValues[t.Name] = e
    end
  end
end

---------------------------------------------------------------------------
-- Normalisers
---------------------------------------------------------------------------
local SKIP_FN = { Name = true, Type = true, Arguments = true, Returns = true, Payload = true,
  Documentation = true, LiteralName = true, Namespace = true, Environment = true }
local SKIP_FIELD = { Name = true, Type = true, Nilable = true, Documentation = true, Default = true,
  InnerType = true, Mixin = true, StrideIndex = true, KeyType = true, EnumValue = true }

local function tagValue(v)
  if isSym(v) then return v.key or resolve(v) end
  if type(v) == "table" then
    local r = {}
    for i, x in ipairs(v) do r[i] = isSym(x) and x.key or x end
    return r
  end
  return v
end

local function field(f)
  local r = { f.Name, f.Type }
  if f.Nilable then r.nilable = true end
  if f.Default ~= nil then
    local d = f.Default
    if isSym(d) then d = resolve(d) end
    r.default = d
  end
  if f.InnerType then r.inner = f.InnerType end
  if f.Mixin then r.mixin = f.Mixin end
  if f.StrideIndex then r.stride = f.StrideIndex end
  for k, v in pairs(f) do if not SKIP_FIELD[k] then r[k] = tagValue(v) end end
  return r
end

local function fieldList(list)
  if not list or #list == 0 then return nil end
  local r = {}
  for i, f in ipairs(list) do r[i] = field(f) end
  return r
end

local function entry(fn)
  local r = { args = fieldList(fn.Arguments), rets = fieldList(fn.Returns) }
  for k, v in pairs(fn) do if not SKIP_FN[k] then r[k] = tagValue(v) end end
  return r
end

---------------------------------------------------------------------------
-- Build output tables
---------------------------------------------------------------------------
local out = {
  functions = {}, events = {}, widgets = {}, objects = {}, enums = {}, constants = {},
  structs = {}, predicates = {}, systems = {},
}
local counts = { functions = 0, events = 0, widgetMethods = 0, enums = 0 }

for _, d in ipairs(docs) do
  if d.Type == "ScriptObject" then
    local bucket = (d.ObjectType == "Userdata") and out.objects or out.widgets
    local m = bucket[d.Name] or {}
    for _, fn in ipairs(d.Functions or {}) do m[fn.Name] = entry(fn); counts.widgetMethods = counts.widgetMethods + 1 end
    bucket[d.Name] = m
  elseif d.Type == "System" then
    local sysName = d.Name
    local list = {}
    for _, fn in ipairs(d.Functions or {}) do
      local ns = fn.Namespace
      if ns == nil then ns = d.Namespace end
      local key = (ns and ns ~= "") and (ns .. "." .. fn.Name) or fn.Name
      local e = entry(fn)
      e.system = sysName
      out.functions[key] = e
      list[#list + 1] = key
      counts.functions = counts.functions + 1
    end
    table.sort(list)
    out.systems[sysName] = { namespace = d.Namespace, file = d.__file, functions = list }
  end
  for _, ev in ipairs(d.Events or {}) do
    local e = { payload = fieldList(ev.Payload), system = d.Name }
    for k, v in pairs(ev) do if not SKIP_FN[k] and k ~= "SynchronousEvent" then e[k] = tagValue(v) end end
    out.events[ev.LiteralName or ev.Name] = e
    counts.events = counts.events + 1
  end
  for _, t in ipairs(d.Tables or {}) do
    if t.Type == "Enumeration" then
      out.enums[t.Name] = enumValues[t.Name]
      counts.enums = counts.enums + 1
    elseif t.Type == "Constants" then
      local c = {}
      for _, v in ipairs(t.Values or {}) do
        local val = v.Value
        if isSym(val) then val = resolve(val) end
        if type(val) == "number" or type(val) == "string" or type(val) == "boolean" then c[v.Name] = val end
      end
      out.constants[t.Name] = c
    elseif t.Type == "Structure" then
      out.structs[t.Name] = fieldList(t.Fields) or {}
    end
  end
  for _, pr in ipairs(d.Predicates or {}) do
    out.predicates[pr.Name] = { type = pr.Type, failureMode = pr.FailureMode }
  end
end

-- Widget type -> doc tables, most specific first. Method lookup takes the first hit.
-- (Hand-maintained: the docs don't say which ScriptObject doc belongs to which type.)
local OBJ = { "SimpleObjectAPI", "SimpleFrameScriptObjectAPI" }
local SCRIPTREGION = { "SimpleScriptRegionAPI", "SimpleScriptRegionResizingAPI" }
local function chain(...)
  local r = {}
  for _, part in ipairs({ ... }) do
    if type(part) == "table" then for _, x in ipairs(part) do r[#r + 1] = x end else r[#r + 1] = part end
  end
  return r
end
local FRAME = chain("SimpleFrameAPI", SCRIPTREGION, "SimpleAnimatableObjectAPI", OBJ)
local REGION = chain("SimpleRegionAPI", SCRIPTREGION, "SimpleAnimatableObjectAPI", OBJ)
local ANIM = chain("SimpleAnimAPI", OBJ)
out.widgetTypes = {
  Frame = FRAME,
  Button = chain("SimpleButtonAPI", FRAME),
  CheckButton = chain("SimpleCheckboxAPI", "SimpleButtonAPI", FRAME),
  StatusBar = chain("SimpleStatusBarAPI", FRAME),
  Cooldown = chain("FrameAPICooldown", FRAME),
  Slider = chain("SimpleSliderAPI", FRAME),
  EditBox = chain("SimpleEditBoxAPI", FRAME, "SimpleFontAPI"),
  ScrollFrame = chain("SimpleScrollFrameAPI", FRAME),
  MessageFrame = chain("SimpleMessageFrameAPI", FRAME, "SimpleFontAPI"),
  ColorSelect = chain("SimpleColorSelectAPI", FRAME),
  GameTooltip = chain("FrameAPITooltip", FRAME),
  Model = chain("SimpleModelAPI", FRAME),
  PlayerModel = chain("FrameAPICharacterModelBase", "SimpleModelAPI", FRAME),
  DressUpModel = chain("FrameAPIDressUpModel", "FrameAPICharacterModelBase", "SimpleModelAPI", FRAME),
  AuraContainer = FRAME,
  Texture = chain("SimpleTextureAPI", "SimpleTextureBaseAPI", REGION),
  MaskTexture = chain("SimpleMaskTextureAPI", "SimpleTextureBaseAPI", REGION),
  Line = chain("SimpleLineAPI", "SimpleTextureBaseAPI", REGION),
  FontString = chain("SimpleFontStringAPI", REGION),
  Font = chain("SimpleFontAPI", OBJ),
  AnimationGroup = chain("SimpleAnimGroupAPI", OBJ),
  Animation = ANIM,
  Alpha = chain("SimpleAnimAlphaAPI", ANIM),
  Scale = chain("SimpleAnimScaleAPI", ANIM),
  Translation = chain("SimpleAnimTranslationAPI", ANIM),
  Rotation = chain("SimpleAnimRotationAPI", ANIM),
  FlipBook = chain("SimpleAnimFlipBookAPI", ANIM),
  VertexColor = chain("SimpleAnimVertexColorAPI", ANIM),
  -- userdata objects
  LuaCurveObject = { "LuaCurveObjectAPI", "LuaCurveObjectBaseAPI" },
  LuaColorCurveObject = { "LuaColorCurveObjectAPI", "LuaCurveObjectBaseAPI" },
  LuaDurationObject = { "LuaDurationObjectAPI" },
  UnitHealPredictionCalculator = { "UnitHealPredictionCalculatorAPI" },
  DurationTextBinding = { "DurationTextBindingObjectAPI" },
  SecondsFormatter = { "SecondsFormatterAPI" },
  AbbreviatedNumberFormatter = { "AbbreviatedNumberFormatterAPI" },
}

---------------------------------------------------------------------------
-- Serializer: deterministic (sorted keys), chunked into separate functions so
-- LuaJIT's per-function constant limits are never hit.
---------------------------------------------------------------------------
local function isIdent(s) return type(s) == "string" and s:match("^[%a_][%w_]*$") and not ({
  ["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,["end"]=1,["false"]=1,["for"]=1,["function"]=1,
  ["if"]=1,["in"]=1,["local"]=1,["nil"]=1,["not"]=1,["or"]=1,["repeat"]=1,["return"]=1,["then"]=1,
  ["true"]=1,["until"]=1,["while"]=1 })[s] end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    return a < b
  end)
  return keys
end

local function ser(v)
  local tv = type(v)
  if tv == "string" then return string.format("%q", v)
  elseif tv == "number" then
    if v == math.huge then return "math.huge" elseif v == -math.huge then return "-math.huge" end
    if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
    return string.format("%.17g", v)
  elseif tv == "boolean" or tv == "nil" then return tostring(v)
  elseif tv == "table" then
    local parts, n = {}, #v
    for i = 1, n do parts[#parts + 1] = ser(v[i]) end
    for _, k in ipairs(sortedKeys(v)) do
      if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
        local key = isIdent(k) and k or ("[" .. ser(k) .. "]")
        parts[#parts + 1] = key .. "=" .. ser(v[k])
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil --[[" .. tv .. "]]"
end

local lines = {}
local function emit(s) lines[#lines + 1] = s end
emit("-- GENERATED by tools/gen_api_tags.lua. Do not edit; run `make gen`.")
emit("-- Source: Blizzard_APIDocumentationGenerated, WoW: Forever 1.60.1.70338 (Gethe/wow-ui-source `forever`).")
emit("-- Contents are API facts only: names, argument/return types and secret/restriction tags.")
emit(string.format("-- %d functions, %d events, %d widget/object methods, %d enums.",
  counts.functions, counts.events, counts.widgetMethods, counts.enums))
emit("local T = { functions = {}, events = {}, widgets = {}, objects = {}, enums = {}, constants = {}, structs = {}, predicates = {}, systems = {} }")

local CHUNK = 250
local function emitMap(name, map)
  local keys = sortedKeys(map)
  for i = 1, #keys, CHUNK do
    emit("do local t = T." .. name .. "; local function f()")
    for j = i, math.min(i + CHUNK - 1, #keys) do
      local k = keys[j]
      emit("t[" .. ser(k) .. "]=" .. ser(map[k]))
    end
    emit("end f() end")
  end
end
emitMap("functions", out.functions)
emitMap("events", out.events)
emitMap("widgets", out.widgets)
emitMap("objects", out.objects)
emitMap("enums", out.enums)
emitMap("constants", out.constants)
emitMap("structs", out.structs)
emitMap("predicates", out.predicates)
emitMap("systems", out.systems)
emit("T.widgetTypes = " .. ser(out.widgetTypes))
emit("return T")

local fh = assert(io.open(outFile, "w"))
fh:write(table.concat(lines, "\n"), "\n")
fh:close()

-- Sanity: the output must load and contain the basics.
local check = assert(loadfile(outFile))()
assert(check.functions.UnitHealth and check.functions.UnitHealth.SecretReturns, "UnitHealth missing")
assert(check.events.UNIT_HEALTH, "UNIT_HEALTH missing")
assert(check.widgets.SimpleStatusBarAPI.SetValue.SecretArguments == "AllowedWhenTainted", "StatusBar:SetValue tag")
assert(check.enums.PowerType and check.enums.PowerType.Mana == 0, "Enum.PowerType")
print(string.format("gen_api_tags: wrote %s (%d functions, %d events, %d widget methods, %d enums, %d load errors)",
  outFile, counts.functions, counts.events, counts.widgetMethods, counts.enums, loadErrors))
