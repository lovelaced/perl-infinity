-- tools/lint.lua
-- Static checks for Perl Infinity (parity doc §2.5), run under LuaJIT.
--
--   luajit tools/lint.lua [--strict] [--manifest=PATH] [--json] <dir-or-files...>
--
-- Exit 0 with findings printed (default), 1 with --strict when any error-severity
-- finding exists, 2 when the tool itself fails. Libs/ folders are skipped.
-- Suppress one line with a trailing comment: `-- lint: allow L8` (or `-- lint: allow`).
--
-- Uses luacheck's parser (~/.luarocks) for a real AST. Without it, a line-based
-- fallback covers L4, L5, L7 and L9 only.
--
-- Rules
--   L1 error  truth test (if/while/until, not/and/or, ==) of a secret-tagged boolean API result
--   L2 error  arithmetic, comparison, #, tostring or math.* on a secret-tagged number/string result
--   L3 warn   table indexed by a secret-tagged (identity) result without an issecretvalue guard
--   L4 error  banned identifiers (removed APIs, CLEU, SecureAuraHeaderTemplate, version gates ...)
--   L5 error  RegisterEvent/RegisterUnitEvent/element event literals must be documented events
--   L6 error  globals and C_X.Y / Enum.X.Y members must exist (api_tags + FrameXML scan)
--   L7 error  OnUpdate / C_Timer.NewTicker / NewTimer only in tools/perf_allow.txt files
--   L8 warn   user-visible string literals (SetText, AddLine, print, Settings labels) bypass L
--   L9 error  SendAddonMessage / SendChatMessage result discarded
--   L10 error division or modulo by anything but a nonzero literal or math.max(..., positive literal).
--             The game raises "Division by zero" where LuaJIT returns inf, so the harness can't
--             catch it; guard the divisor, then mark the line `-- lint: allow L10`.

local ROOT = (arg[0]:match("^(.*)/tools/lint%.lua$")) or "."
local HOME = os.getenv("HOME") or ""

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local opts = { targets = {} }
for _, a in ipairs(arg) do
  local k, v = a:match("^%-%-([%w%-]+)=?(.*)$")
  if k == "strict" then opts.strict = true
  elseif k == "json" then opts.json = true
  elseif k == "manifest" then opts.manifest = (v ~= "" and v) or (ROOT .. "/tools/out/manifest.lua")
  elseif k == "no-manifest" then opts.noManifest = true
  elseif k then io.stderr:write("lint: unknown option --" .. k .. "\n"); os.exit(2)
  else opts.targets[#opts.targets + 1] = a end
end
if #opts.targets == 0 then opts.targets = { "PerlInfinity" } end

---------------------------------------------------------------------------
-- Data: api_tags, FrameXML globals, extras, perf allowlist
---------------------------------------------------------------------------
local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local T = assert(loadfile(ROOT .. "/tests/harness/api_tags.lua"), "lint: cannot load tests/harness/api_tags.lua")()

local KNOWN = {}    -- global name -> true
local MEMBERS = {}  -- table name -> { member = true }
local function addMember(t, m) MEMBERS[t] = MEMBERS[t] or {}; MEMBERS[t][m] = true end
for key in pairs(T.functions) do
  local ns, fn = key:match("^([%w_]+)%.([%w_]+)$")
  if ns then KNOWN[ns] = true; addMember(ns, fn) else KNOWN[key] = true end
end
KNOWN.Enum, KNOWN.Constants = true, true

local notes = {}
local wg = loadfile(ROOT .. "/tools/out/wow_globals.lua")
if wg then
  local G = wg()
  for _, g in ipairs(G.globals or {}) do KNOWN[g] = true end
  for t, list in pairs(G.members or {}) do for _, m in ipairs(list) do addMember(t, m) end end
else
  notes[#notes + 1] = "tools/out/wow_globals.lua missing (run `make gen`); L6 uses api_tags + globals_extra only"
  local extra = readFile(ROOT .. "/tools/globals_extra.txt") or ""
  for line in extra:gmatch("[^\n]+") do
    local name = line:gsub("#.*$", ""):match("^%s*(%S+)")
    if name then
      local t, m = name:match("^([%a_][%w_]*)%.([%a_][%w_]*)$")
      if t then KNOWN[t] = true; addMember(t, m) else KNOWN[name] = true end
    end
  end
end

-- Lua 5.1 as WoW exposes it (no io/require/dofile/loadfile/module).
for _, n in ipairs({ "_G", "_VERSION", "assert", "collectgarbage", "error", "getfenv", "getmetatable", "ipairs",
  "load", "loadstring", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset", "select", "setfenv",
  "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "gcinfo", "string", "table", "math",
  "coroutine", "bit", "os" }) do KNOWN[n] = true end

-- Our own globals (architecture §12) and optional third-party ones we nil-check.
local OWN = { PerlInfinity = 1, PerlInfinityDB = 1, PerlInfinityCharDB = 1, PerlInfinityLog = 1, SLASH_PERLINFINITY1 = 1, SLASH_PERLINFINITY2 = 1,
  BINDING_HEADER_PERLINFINITY = 1, PerlInfinity_OnAddonCompartmentClick = 1, PerlInfinity_OnAddonCompartmentEnter = 1,
  PerlInfinity_OnAddonCompartmentLeave = 1, PerlInfinityUnitButtonMixin = 1, PerlInfinityPreviewRowMixin = 1,
  LibStub = 1, ClickCastFrames = 1, BugGrabber = 1 }
local OWN_PATTERNS = { "^BINDING_NAME_PERLINFINITY_", "^PerlInfinity_" }

local PERF_ALLOW = {}
for line in (readFile(ROOT .. "/tools/perf_allow.txt") or ""):gmatch("[^\n]+") do
  local p = line:gsub("#.*$", ""):match("^%s*(%S+)")
  if p then PERF_ALLOW[#PERF_ALLOW + 1] = p end
end
local function perfAllowed(path)
  path = path:gsub("^%./", "")
  for _, p in ipairs(PERF_ALLOW) do
    if path == p or path:sub(-#p - 1) == "/" .. p then return true end
  end
  return false
end

-- Removed or forbidden on Forever (research 5.2, parity §2.5). Also the manifest's
-- "absent" list, which the in-game self-test checks for nil.
local BANNED = {
  CombatLogGetCurrentEventInfo = "the combat log is gone for addons",
  UnitAura = "removed; use C_UnitAuras or CustomAuraContainerTemplate",
  UnitBuff = "removed; use C_UnitAuras or CustomAuraContainerTemplate",
  UnitDebuff = "removed; use C_UnitAuras or CustomAuraContainerTemplate",
  GetSpellInfo = "global removed; use C_Spell.GetSpellInfo / C_Spell.GetSpellName",
  GetItemInfo = "use C_Item.GetItemInfo",
  GetLootMethod = "global removed; use C_PartyInfo.GetLootMethod",
  GetPetHappiness = "global removed; use C_PetInfo.GetPetHappiness",
  SetPortraitToTexture = "removed; use SetTexture with a mask",
  GetMouseFocus = "removed; use GetMouseFoci",
  IsRaidOfficer = "removed; use UnitIsGroupAssistant",
  IsRaidLeader = "removed; use UnitIsGroupLeader",
  UnitIsPartyLeader = "removed; use UnitIsGroupLeader",
  GetNumPartyMembers = "removed; use GetNumSubgroupMembers",
  GetNumRaidMembers = "removed; use GetNumGroupMembers",
  seterrorhandler = "Perl Infinity never replaces the error handler (decisions.md)",
}
local ABSENT = { "CombatLogGetCurrentEventInfo", "UnitAura", "UnitBuff", "UnitDebuff", "GetSpellInfo",
  "GetLootMethod", "GetPetHappiness", "SetPortraitToTexture", "GetMouseFocus", "IsRaidOfficer", "IsRaidLeader",
  "UnitIsPartyLeader", "GetNumPartyMembers", "GetNumRaidMembers", "GetPartyLeaderIndex", "GetWatchedFactionInfo",
  "GetNumTalentTabs", "GetTalentTabInfo", "UnitPVPRank", "GetPVPRankInfo" }
local BANNED_MEMBERS = { ["C_AddOns.DisableAddOn"] = "never disable other addons" }
local BANNED_STRINGS = {
  COMBAT_LOG_EVENT_UNFILTERED = "registering (even unregistering) raises ADDON_ACTION_FORBIDDEN",
  COMBAT_LOG_EVENT = "registering (even unregistering) raises ADDON_ACTION_FORBIDDEN",
  SecureAuraHeaderTemplate = "not available on Forever; use CustomAuraContainerTemplate",
}

local CHAT_SENDERS = { SendAddonMessage = 1, SendAddonMessageLogged = 1, SendChatMessage = 1,
  ["C_ChatInfo.SendAddonMessage"] = 1, ["C_ChatInfo.SendAddonMessageLogged"] = 1, ["C_ChatInfo.SendChatMessage"] = 1 }

-- Text sinks whose literal arguments are user-visible (L8): arg indexes.
local TEXT_METHODS = { SetText = { 1 }, SetFormattedText = { 1 }, AddLine = { 1 }, AddDoubleLine = { 1, 2 },
  SetTitle = { 1 }, AppendText = { 1 }, SetLabel = { 1 } }
local TEXT_CALLS = {
  print = "all",
  ["Settings.RegisterVerticalLayoutCategory"] = { 1 }, ["Settings.RegisterVerticalLayoutSubcategory"] = { 2 },
  ["Settings.RegisterCanvasLayoutCategory"] = { 2 }, ["Settings.RegisterCanvasLayoutSubcategory"] = { 3 },
  ["Settings.RegisterProxySetting"] = { 4 }, ["Settings.RegisterAddOnSetting"] = { 6 },
  ["Settings.CreateCheckbox"] = { 3 }, ["Settings.CreateSlider"] = { 4 }, ["Settings.CreateDropdown"] = { 4 },
  ["Settings.CreateColorSwatch"] = { 3 },
  CreateSettingsListSectionHeaderInitializer = { 1, 2 }, CreateSettingsButtonInitializer = { 1, 2, 4 },
}

local MATH_FUNCS = { floor = 1, ceil = 1, abs = 1, min = 1, max = 1, sqrt = 1, fmod = 1, mod = 1, modf = 1,
  pow = 1, exp = 1, log = 1, log10 = 1 }
local GUARDS = { issecretvalue = 1, canaccessvalue = 1, canaccessallvalues = 1, hasanysecretvalues = 1 }

---------------------------------------------------------------------------
-- Secret classification of API returns
---------------------------------------------------------------------------
local OBJECT_PREDS = { SecretWhenAnchoringSecret = 1, SecretWhenCurveSecret = 1, SecretWhenLuaTableHasSecretKeys = 1,
  SecretWhenNumericFormatterSecret = 1 }
-- Predicates that never hold for the player's own unit ("player") or its pet.
local SELF_EXEMPT = { SecretWhenUnitIdentityRestricted = 1, SecretWhenUnitNameIdentityRestricted = 1,
  SecretWhenUnitHealthMaxRestricted = 1, SecretWhenUnitPowerMaxRestricted = 1, SecretWhenUnitSpellCastRestricted = 1,
  SecretWhenUnitStatsRestricted = 1, SecretWhenLossOfControlInfoRestricted = 1, SecretWhenUnitPossessionRestricted = 1 }

local function secretPreds(e)
  local r = {}
  if e.ReturnsNeverSecret then return r end
  for k in pairs(e) do
    if type(k) == "string" and not OBJECT_PREDS[k] and (k == "SecretReturns" or k:match("^SecretWhen") or k:match("^SecretIn")) then
      r[#r + 1] = k
    end
  end
  return r
end

local NUMERIC = { number = 1, luaIndex = 1, uiUnit = 1, SingleColorValue = 1, fileID = 1, size = 1, time_t = 1,
  LuaCurveEvaluatedResult = 1, Seconds = 1, FrameTime = 1 }
local STRINGY = { string = 1, cstring = 1, WOWGUID = 1, stringView = 1, textureAtlas = 1 }

-- Structures the docs reference but don't define (AuraData lives outside the generated
-- docs). Field kinds from the 12.x AuraData shape; all secret while auras are restricted.
local LOCAL_STRUCTS = {
  AuraData = {
    { "applications", "number" }, { "auraInstanceID", "number" }, { "canApplyAura", "bool" },
    { "charges", "number" }, { "dispelName", "string" }, { "duration", "number" },
    { "expirationTime", "number" }, { "icon", "number" }, { "isBossAura", "bool" },
    { "isFromPlayerOrPlayerPet", "bool" }, { "isHarmful", "bool" }, { "isHelpful", "bool" },
    { "isNameplateOnly", "bool" }, { "isRaid", "bool" }, { "isStealable", "bool" },
    { "maxCharges", "number" }, { "name", "string" }, { "nameplateShowAll", "bool" },
    { "nameplateShowPersonal", "bool" }, { "sourceUnit", "string" }, { "spellId", "number" },
    { "timeMod", "number" },
  },
}
local function structFields(name) return T.structs[name] or LOCAL_STRUCTS[name] end

local function kindOf(typ)
  if typ == "bool" then return "bool" end
  if NUMERIC[typ] or T.enums[typ] then return "num" end
  if STRINGY[typ] then return "str" end
  if structFields(typ) then return "struct" end
  return nil
end

---------------------------------------------------------------------------
-- Findings
---------------------------------------------------------------------------
local findings = {}
local SEVERITY = { L0 = "error", L1 = "error", L2 = "error", L3 = "warn", L4 = "error", L5 = "error", L6 = "error",
  L7 = "error", L8 = "warn", L9 = "error", L10 = "error" }

local manifest = { apis = {}, events = {}, templates = {}, textures = {}, atlases = {} }
local function note(kind, v) if type(v) == "string" and v ~= "" then manifest[kind][v] = true end end

---------------------------------------------------------------------------
-- AST linter (luacheck parser)
---------------------------------------------------------------------------
local parser, decoder
do
  package.path = HOME .. "/.luarocks/share/lua/5.1/?.lua;" .. HOME .. "/.luarocks/share/lua/5.1/?/init.lua;" .. package.path
  local ok1, p = pcall(require, "luacheck.parser")
  local ok2, d = pcall(require, "luacheck.decoder")
  if ok1 and ok2 then parser, decoder = p, d end
end

local globalWrites = {}   -- names assigned as globals anywhere in the scanned files
local pendingL6 = {}      -- global reads to resolve after every file is walked

local function lintAst(path, src)
  local ok, ast, comments, _, _, _, lineOffsets = pcall(function() return parser.parse(decoder.decode(src)) end)
  local suppress = {}
  local function report(rule, node, msg)
    local line = node and node.line or 1
    local s = suppress[line]
    if s and (s.all or s[rule]) then return end
    local col = 1
    if node and node.offset and lineOffsets and lineOffsets[line] then col = node.offset - lineOffsets[line] + 1 end
    findings[#findings + 1] = { file = path, line = line, col = col, rule = rule, severity = SEVERITY[rule], message = msg }
  end
  if not ok then
    local e = ast
    findings[#findings + 1] = { file = path, line = type(e) == "table" and e.line or 1, col = 1, rule = "L0",
      severity = "error", message = "syntax error: " .. (type(e) == "table" and tostring(e.msg) or tostring(e)) }
    return
  end
  for _, c in ipairs(comments) do
    local codes = c.contents:match("lint:%s*allow(.*)$")
    if codes then
      local s = suppress[c.line] or {}
      local any = false
      for code in codes:gmatch("L%d+") do s[code] = true; any = true end
      if not any then s.all = true end
      suppress[c.line] = s
    end
  end
  local allowPerf = perfAllowed(path)

  -- scopes: array of { [name] = var }; var = { tag = ?, alias = "Global.Name" }
  local scopes = {}
  local function push() scopes[#scopes + 1] = {} end
  local function pop() scopes[#scopes] = nil end
  local function declare(name, var) scopes[#scopes][name] = var or {} ; return scopes[#scopes][name] end
  local function lookup(name)
    for i = #scopes, 1, -1 do local v = scopes[i][name]; if v then return v end end
  end

  local walkExpr, walkBlock, playerCheck

  -- "UnitHealth" / "C_UnitAuras.GetAuraDataByIndex" for a callee (follows local aliases)
  local function calleeName(node)
    if node.tag == "Id" then
      local v = lookup(node[1])
      if v then return v.alias end
      return node[1]
    elseif node.tag == "Index" and node[2].tag == "String" then
      local base = node[1]
      local baseName
      if base.tag == "Id" then
        local v = lookup(base[1])
        if v then baseName = v.alias else baseName = base[1] end
      end
      if baseName and not baseName:find("%.") then return baseName .. "." .. node[2][1] end
    end
  end

  local function unitArgIndex(e)
    for i, a in ipairs(e.args or {}) do
      local n, t = a[1], a[2] or ""
      if t:match("^UnitToken") or n == "unit" or n == "unitToken" then return i end
    end
  end

  local function isCompoundLiteral(s) return s ~= "target" and s:match("target$") ~= nil end

  -- Is the call provably plain because of literal unit arguments?
  local function exempt(name, e, call, preds)
    local args = {}
    for i = 2, #call do args[i - 1] = call[i] end
    if name == "UnitIsUnit" then
      for i = 1, 2 do
        local a = args[i]
        if not (a and a.tag == "String" and not isCompoundLiteral(a[1])) then return false end
      end
      return true
    end
    local ui = unitArgIndex(e)
    local a = ui and args[ui]
    local selfLiteral = a and a.tag == "String" and (a[1] == "player" or a[1] == "pet")
    local guarded = a and a.tag == "Id" and lookup(a[1]) and lookup(a[1]).playerControlled
    if not (selfLiteral or guarded) then return false end
    for _, p in ipairs(preds) do if not SELF_EXEMPT[p] then return false end end
    return true
  end

  -- Tag for return #idx of an API call node, or nil when it can't be secret.
  local function returnTag(call, idx)
    local name = calleeName(call[1])
    if not name then return nil end
    if name == "GetBuildInfo" then return { kind = "buildinfo", api = name } end
    local e = T.functions[name]
    if not e then return nil end
    local preds = secretPreds(e)
    if #preds == 0 then return nil end
    local r = e.rets and e.rets[idx]
    if not r or r.NeverSecret then return nil end
    if exempt(name, e, call, preds) then return nil end
    local kind = kindOf(r[2])
    if not kind then return nil end
    local identity = e.SecretWhenUnitIdentityRestricted or e.SecretWhenUnitNameIdentityRestricted
    return { kind = kind, api = name, identity = identity and true or nil, struct = kind == "struct" and r[2] or nil }
  end

  local function exprTag(node)
    if not node then return nil end
    local tag = node.tag
    if tag == "Paren" then return exprTag(node[1])
    elseif tag == "Op" and (node[1] == "and" or node[1] == "or") then
      -- `x and secretBool` / `secretBool or y` can yield the secret
      local tb = exprTag(node[3])
      if tb and tb.kind == "bool" then return tb end
      if node[1] == "or" then return exprTag(node[2]) end
      return nil
    elseif tag == "Call" then
      local name = calleeName(node[1])
      if name == "select" and node[2] and node[2].tag == "Number" and node[3] and node[3].tag == "Call" then
        return returnTag(node[3], tonumber(node[2][1]) or 1)
      end
      if name == "tonumber" and node[2] then
        local t = exprTag(node[2])
        if t and t.kind == "buildinfo" then return t end
      end
      return returnTag(node, 1)
    elseif tag == "Id" then
      local v = lookup(node[1])
      return v and v.tag
    elseif tag == "Index" and node[2].tag == "String" then
      local bt = exprTag(node[1])
      if bt and bt.kind == "struct" then
        for _, f in ipairs(structFields(bt.struct) or {}) do
          if f[1] == node[2][1] then
            if f.NeverSecret then return nil end
            local k = kindOf(f[2])
            if k and k ~= "struct" then return { kind = k, api = bt.api .. "()." .. f[1] } end
          end
        end
      end
    end
    return nil
  end

  -- Assign tags to targets from an expression list (Lua multi-value rules).
  local function tagsFor(rhs, count)
    local r = {}
    if not rhs then return r end
    for i = 1, count do
      local n = #rhs
      if i < n then r[i] = exprTag(rhs[i])
      elseif n > 0 then
        local last = rhs[n]
        local extra = i - n + 1
        if extra == 1 then r[i] = exprTag(last)
        elseif last.tag == "Call" then r[i] = returnTag(last, extra) end
      end
    end
    return r
  end

  local function aliasOf(node)
    if not node then return nil end
    if node.tag == "Id" then
      local v = lookup(node[1])
      if v then return v.alias end
      return node[1]
    elseif node.tag == "Index" then
      return calleeName(node)
    end
  end

  local function stringsIn(node, out)
    out = out or {}
    if node.tag == "String" then out[#out + 1] = node
    elseif node.tag == "Paren" then stringsIn(node[1], out)
    elseif node.tag == "Op" and node[1] == "concat" then stringsIn(node[2], out); stringsIn(node[3], out) end
    return out
  end

  local function userVisible(s)
    local t = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    t = t:gsub("%%[%-%+ #0]*%d*%.?%d*[%a%%]", "")
    return t:find("%a") ~= nil
  end

  local function checkText(node, what)
    for _, s in ipairs(stringsIn(node)) do
      if userVisible(s[1]) then report("L8", s, string.format("user-visible literal %q in %s; take it from L", s[1], what)) end
    end
  end

  local function checkEventLiteral(node, what)
    if node and node.tag == "String" then
      local ev = node[1]
      note("events", ev)
      if not T.events[ev] and not BANNED_STRINGS[ev] then
        report("L5", node, string.format("%s: unknown event %q (not in the API docs)", what, ev))
      end
    end
  end

  local function guardArg(node)
    if node and node.tag == "Id" then
      local v = lookup(node[1])
      if v then v.tag = nil end
    end
  end

  local function opName(op)
    local names = { add = "+", sub = "-", mul = "*", div = "/", mod = "%", pow = "^", unm = "unary -", len = "#",
      lt = "<", le = "<=", gt = ">", ge = ">=", eq = "==", ne = "~=", idiv = "//" }
    return names[op] or op
  end

  local ARITH = { add = 1, sub = 1, mul = 1, div = 1, mod = 1, pow = 1, unm = 1, idiv = 1, band = 1, bor = 1,
    bxor = 1, shl = 1, shr = 1, bnot = 1 }
  local ORDER = { lt = 1, le = 1, gt = 1, ge = 1 }

  -- A divisor that can't be zero: a nonzero number, or math.max with a
  -- positive literal among its arguments.
  local function safeDivisor(x)
    if not x then return false end
    if x.tag == "Paren" then return safeDivisor(x[1]) end
    if x.tag == "Number" then return tonumber(x[1]) ~= 0 end
    if x.tag == "Call" and x[1].tag == "Index" and x[1][1].tag == "Id" and x[1][1][1] == "math"
        and x[1][2].tag == "String" and x[1][2][1] == "max" then
      for i = 2, #x do
        if x[i].tag == "Number" and (tonumber(x[i][1]) or 0) > 0 then return true end
      end
    end
    return false
  end

  local function checkOp(node)
    local op = node[1]
    local a, b = node[2], node[3]
    if (op == "div" or op == "mod" or op == "idiv") and not safeDivisor(b) then
      report("L10", node, opName(op) .. " by a value that could be zero; the game errors on x / 0 (guard it, then `-- lint: allow L10`)")
    end
    if op == "not" then
      local t = exprTag(a)
      if t and t.kind == "bool" then report("L1", node, "`not` on a possibly-secret boolean from " .. t.api .. "; use SetAlphaFromBoolean/EvaluateColorFromBoolean") end
      return
    end
    if op == "and" or op == "or" then
      -- only the left operand is truth-tested; the right one is passed through
      local t = exprTag(a)
      if t and t.kind == "bool" then report("L1", a, "`" .. op .. "` tests a possibly-secret boolean from " .. t.api) end
      return
    end
    if ARITH[op] or op == "len" then
      for _, x in ipairs({ a, b }) do
        local t = x and exprTag(x)
        if t and t.kind ~= "buildinfo" then report("L2", node, opName(op) .. " on a possibly-secret " .. t.kind .. " from " .. t.api) end
      end
      return
    end
    if ORDER[op] or op == "eq" or op == "ne" then
      for _, x in ipairs({ a, b }) do
        if x.tag == "Id" and x[1] == "WOW_PROJECT_ID" and not lookup("WOW_PROJECT_ID") then
          report("L4", node, "WOW_PROJECT_ID comparison; Forever is gated by the TOC and feature detection")
        end
      end
      local other = { [a] = b, [b] = a }
      for _, x in ipairs({ a, b }) do
        local t = exprTag(x)
        -- `secret ~= nil` is a plain nil check and allowed
        local nilCheck = (op == "eq" or op == "ne") and other[x].tag == "Nil"
        if t and not (nilCheck and t.kind ~= "buildinfo") then
          if t.kind == "buildinfo" then
            report("L4", node, "numeric GetBuildInfo gate; feature-detect instead")
          elseif t.kind == "bool" then
            report("L1", node, "comparison of a possibly-secret boolean from " .. t.api)
          else
            report("L2", node, "comparison (" .. opName(op) .. ") of a possibly-secret " .. t.kind .. " from " .. t.api)
          end
        end
      end
    end
  end

  local function checkCondition(cond, what)
    local t = exprTag(cond)
    if t and t.kind == "bool" then
      report("L1", cond, what .. " tests a possibly-secret boolean from " .. t.api .. "; drive alpha/color with *FromBoolean instead")
    end
  end

  local function checkCall(node, isStatement)
    local name = calleeName(node[1])
    if name then
      if CHAT_SENDERS[name] and isStatement then
        report("L9", node, name .. " result discarded; check it (e.g. against Enum.SendAddonMessageResult)")
      end
      if name == "C_Timer.NewTicker" or name == "C_Timer.NewTimer" then
        if not allowPerf then report("L7", node, name .. " outside tools/perf_allow.txt") end
      end
      if name == "tostring" then
        local t = exprTag(node[2])
        if t and t.kind ~= "buildinfo" then report("L2", node, "tostring of a possibly-secret " .. t.kind .. " from " .. t.api) end
      end
      local mf = name:match("^math%.(%w+)$") or (MATH_FUNCS[name] and name)
      if mf and MATH_FUNCS[mf] then
        for i = 2, #node do
          local t = exprTag(node[i])
          if t and (t.kind == "num" or t.kind == "str") then report("L2", node, name .. " on a possibly-secret " .. t.kind .. " from " .. t.api) end
        end
      end
      if GUARDS[name] then for i = 2, #node do guardArg(node[i]) end end
      local text = TEXT_CALLS[name]
      if text == "all" then for i = 2, #node do checkText(node[i], name) end
      elseif text then for _, i in ipairs(text) do if node[i + 1] then checkText(node[i + 1], name) end end end
      if name == "CreateFrame" and node[5] and node[5].tag == "String" then
        for t in node[5][1]:gmatch("[^,%s]+") do note("templates", t) end
      end
      if name == "Settings.CreatePanelInitializer" and node[2] and node[2].tag == "String" then note("templates", node[2][1]) end
      if (name == "EventRegistry.RegisterFrameEventAndCallback") and node[2] then checkEventLiteral(node[2], name) end
    end
  end

  local function checkInvoke(node, isStatement)
    local obj, method = node[1], node[2][1]
    local arg1 = node[3]
    if method == "RegisterEvent" or method == "RegisterUnitEvent" or method == "UnregisterEvent" then
      checkEventLiteral(arg1, method)
    elseif method == "On" or method == "Off" then
      local looksLikeBus = (obj.tag == "Id" and (obj[1] == "Events" or obj[1] == "Bus"))
        or (obj.tag == "Index" and obj[2].tag == "String" and obj[2][1] == "Events")
      if looksLikeBus then checkEventLiteral(arg1, "Events:" .. method) end
    elseif method == "RegisterFrameEventAndCallback" then
      checkEventLiteral(arg1, method)
    end
    if obj.tag == "Id" and obj[1] == "UIParent" and not lookup("UIParent")
        and (method == "UnregisterEvent" or method == "UnregisterAllEvents") then
      report("L4", node, "UIParent:" .. method .. " breaks Blizzard UI; never touch UIParent's events")
    end
    if (method == "SetScript" or method == "HookScript") and arg1 and arg1.tag == "String" and arg1[1] == "OnUpdate" then
      if not allowPerf then report("L7", node, method .. "(\"OnUpdate\") outside tools/perf_allow.txt") end
    end
    if method:match("Atlas$") and arg1 and arg1.tag == "String" then note("atlases", arg1[1]) end
    if method == "SetAttribute" and arg1 and arg1.tag == "String" and node[4] and node[4].tag == "String" then
      local key = arg1[1]:lower()
      if key == "template" or key == "auracontainertemplate" then
        for t in node[4][1]:gmatch("[^,%s]+") do note("templates", t) end
      end
    end
    local text = TEXT_METHODS[method]
    if text then for _, i in ipairs(text) do if node[i + 2] then checkText(node[i + 2], ":" .. method) end end end
    if CHAT_SENDERS[method] and isStatement then
      report("L9", node, method .. " result discarded; check it")
    end
  end

  local function checkGlobalRead(node)
    local name = node[1]
    if BANNED[name] then
      report("L4", node, name .. ": " .. BANNED[name])
      return
    end
    if name:match("^UIDropDownMenu_") then
      report("L4", node, name .. ": UIDropDownMenu is retired; use Settings dropdowns or MenuUtil")
      return
    end
    note("apis", name)
    if not KNOWN[name] then pendingL6[#pendingL6 + 1] = { path = path, node = node, name = name, report = report } end
  end

  local function checkIndex(node)
    local base, key = node[1], node[2]
    -- Global namespace members: C_X.Y and Enum.X.Y (also through `local C_X = C_X`)
    local baseVar = base.tag == "Id" and lookup(base[1])
    local nsName = base.tag == "Id" and (baseVar and baseVar.alias or (not baseVar and base[1]))
    if nsName and not nsName:find("%.") and key.tag == "String" then
      local ns, m = nsName, key[1]
      if BANNED_MEMBERS[ns .. "." .. m] then report("L4", node, ns .. "." .. m .. ": " .. BANNED_MEMBERS[ns .. "." .. m]) end
      if ns:match("^C_") then
        note("apis", ns .. "." .. m)
        if KNOWN[ns] and not (MEMBERS[ns] and MEMBERS[ns][m]) then
          report("L6", node, ns .. "." .. m .. " does not exist in the Forever API docs")
        end
      elseif ns == "Enum" and not T.enums[m] and not (MEMBERS.Enum and MEMBERS.Enum[m]) then
        report("L6", node, "Enum." .. m .. " is not a known enum")
      end
    elseif base.tag == "Index" and base[1].tag == "Id" and base[1][1] == "Enum" and not lookup("Enum")
        and base[2].tag == "String" and key.tag == "String" then
      local e = T.enums[base[2][1]]
      if e and e[key[1]] == nil then report("L6", node, "Enum." .. base[2][1] .. "." .. key[1] .. " does not exist") end
    end
    if key.tag ~= "String" and key.tag ~= "Number" then
      local t = exprTag(key)
      if t and t.kind ~= "buildinfo" then
        report("L3", node, "table indexed by a possibly-secret " .. t.kind .. " from " .. t.api .. " (guard with issecretvalue/canaccessvalue)")
      end
    end
  end

  -- CLEU names are only a problem when passed somewhere (a guard table of names is fine).
  local function checkCallArgs(node, first)
    for i = first, #node do
      local a = node[i]
      if a.tag == "String" and BANNED_STRINGS[a[1]] and a[1] ~= "SecureAuraHeaderTemplate" then
        report("L4", a, a[1] .. ": " .. BANNED_STRINGS[a[1]])
      end
    end
  end

  local function checkString(node)
    local s = node[1]
    if s == "SecureAuraHeaderTemplate" then report("L4", node, s .. ": " .. BANNED_STRINGS[s]) end
    if s:find("SecureAuraHeaderTemplate", 1, true) and s ~= "SecureAuraHeaderTemplate" then
      report("L4", node, "SecureAuraHeaderTemplate is not available on Forever")
    end
    if s:match("^[Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee][\\/]") then note("textures", s) end
  end

  -- UnitIsPlayer(v) / UnitPlayerControlled(v) / not ... -> var record, negated
  function playerCheck(cond)
    local negated = false
    while cond.tag == "Paren" do cond = cond[1] end
    if cond.tag == "Op" and cond[1] == "not" then negated = true; cond = cond[2] end
    while cond.tag == "Paren" do cond = cond[1] end
    if cond.tag ~= "Call" then return nil end
    local name = calleeName(cond[1])
    if (name == "UnitIsPlayer" or name == "UnitPlayerControlled") and cond[2] and cond[2].tag == "Id" then
      return lookup(cond[2][1]), negated
    end
  end

  local function walkFunction(node)
    push()
    for _, a in ipairs(node[1]) do if a.tag == "Id" then declare(a[1]) end end
    walkBlock(node[2])
    pop()
  end

  function walkExpr(node, isStatement)
    if type(node) ~= "table" then return end
    local tag = node.tag
    if tag == "Id" then
      if not lookup(node[1]) then checkGlobalRead(node) end
    elseif tag == "String" then checkString(node)
    elseif tag == "Function" then walkFunction(node)
    elseif tag == "Paren" then walkExpr(node[1])
    elseif tag == "Op" then
      walkExpr(node[2])
      if node[3] then walkExpr(node[3]) end
      checkOp(node)
    elseif tag == "Call" then
      walkExpr(node[1])
      for i = 2, #node do walkExpr(node[i]) end
      checkCallArgs(node, 2)
      checkCall(node, isStatement)
    elseif tag == "Invoke" then
      walkExpr(node[1])
      for i = 3, #node do walkExpr(node[i]) end
      checkCallArgs(node, 3)
      checkInvoke(node, isStatement)
    elseif tag == "Index" then
      walkExpr(node[1])
      walkExpr(node[2])
      checkIndex(node)
    elseif tag == "Table" then
      for _, item in ipairs(node) do
        if item.tag == "Pair" then
          walkExpr(item[1]); walkExpr(item[2])
          local k = item[1]
          if k.tag == "String" and (k[1] == "unitEvents" or k[1] == "events") and item[2].tag == "Table" then
            for _, ev in ipairs(item[2]) do
              checkEventLiteral(ev, k[1])
              if ev.tag == "String" and BANNED_STRINGS[ev[1]] then report("L4", ev, ev[1] .. ": " .. BANNED_STRINGS[ev[1]]) end
            end
          end
        else
          walkExpr(item)
        end
      end
    end
  end

  local function assignTarget(lhs, tagInfo, aliasInfo)
    if lhs.tag == "Id" then
      local v = lookup(lhs[1])
      if v then v.tag, v.alias = tagInfo, aliasInfo
      else globalWrites[lhs[1]] = true end
    else
      walkExpr(lhs)
    end
  end

  local walkStatement
  function walkBlock(block)
    push()
    for _, st in ipairs(block) do walkStatement(st) end
    pop()
  end

  function walkStatement(st)
    local tag = st.tag
    if tag == "Local" then
      local lhs, rhs = st[1], st[2]
      if rhs then for _, e in ipairs(rhs) do walkExpr(e) end end
      local tags = tagsFor(rhs, #lhs)
      for i, id in ipairs(lhs) do
        local alias = rhs and #rhs == #lhs and aliasOf(rhs[i]) or nil
        declare(id[1], { tag = tags[i], alias = alias })
        if id[1] == "_" and rhs and rhs[i] and rhs[i].tag == "Call" and CHAT_SENDERS[calleeName(rhs[i][1]) or ""] then
          report("L9", rhs[i], "chat/addon message result assigned to _ and ignored")
        end
      end
    elseif tag == "Localrec" then
      declare(st[1][1][1])
      walkFunction(st[2][1])
    elseif tag == "Set" or tag == "OpSet" then
      local lhs, rhs = st[1], st[2]
      for _, e in ipairs(rhs) do walkExpr(e) end
      local tags = tagsFor(rhs, #lhs)
      for i, target in ipairs(lhs) do
        assignTarget(target, tags[i], #rhs == #lhs and aliasOf(rhs[i]) or nil)
        -- StaticPopupDialogs["X"] = { text = "..." }
        if target.tag == "Index" and target[1].tag == "Id" and target[1][1] == "StaticPopupDialogs" and rhs[i] and rhs[i].tag == "Table" then
          for _, item in ipairs(rhs[i]) do
            if item.tag == "Pair" and item[1].tag == "String" and (item[1][1] == "text" or item[1][1]:match("^button%d$")) then
              checkText(item[2], "StaticPopupDialogs." .. item[1][1])
            end
          end
        end
      end
      if tag == "OpSet" then
        local t = exprTag(lhs[1])
        if t then report("L2", st, "compound assignment on a possibly-secret value from " .. t.api) end
      end
    elseif tag == "Call" or tag == "Invoke" then
      walkExpr(st, true)
    elseif tag == "If" then
      -- { cond1, block1, cond2, block2, ..., [elseBlock] }
      local i = 1
      while i <= #st do
        if i + 1 <= #st then
          walkExpr(st[i]); checkCondition(st[i], i == 1 and "if" or "elseif")
          -- `if UnitIsPlayer(u) then ...`: u is player-controlled inside the block
          local pv, negated = playerCheck(st[i])
          local saved = pv and pv.playerControlled
          if pv and not negated then pv.playerControlled = true end
          walkBlock(st[i + 1])
          if pv and not negated then pv.playerControlled = saved end
          -- `if not UnitIsPlayer(u) then ... return end`: u is player-controlled afterwards
          local blk = st[i + 1]
          if pv and negated and #st == 2 and blk[#blk] and blk[#blk].tag == "Return" then pv.playerControlled = true end
          i = i + 2
        else
          walkBlock(st[i]); i = i + 1
        end
      end
    elseif tag == "While" then
      walkExpr(st[1]); checkCondition(st[1], "while")
      walkBlock(st[2])
    elseif tag == "Repeat" then
      push()
      for _, s in ipairs(st[1]) do walkStatement(s) end
      walkExpr(st[2]); checkCondition(st[2], "until")
      pop()
    elseif tag == "Fornum" then
      for i = 2, #st - 1 do
        walkExpr(st[i])
        local t = exprTag(st[i])
        if t and t.kind ~= "buildinfo" then report("L2", st[i], "for-loop bound from a possibly-secret value (" .. t.api .. ")") end
      end
      push(); declare(st[1][1]); walkBlock(st[#st]); pop()
    elseif tag == "Forin" then
      for _, e in ipairs(st[2]) do walkExpr(e) end
      push()
      for _, id in ipairs(st[1]) do declare(id[1]) end
      walkBlock(st[3])
      pop()
    elseif tag == "Do" then
      walkBlock(st)
    elseif tag == "Return" then
      for _, e in ipairs(st) do walkExpr(e) end
    end
  end

  push()
  for _, st in ipairs(ast) do walkStatement(st) end
  pop()
end

---------------------------------------------------------------------------
-- Line-based fallback (no luacheck parser): L4, L5, L7, L9 only
---------------------------------------------------------------------------
local function lintLines(path, src)
  local allowPerf = perfAllowed(path)
  local n = 0
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local code = line:gsub("%-%-.*$", "")
    local function rep(rule, msg)
      if line:match("lint:%s*allow") then return end
      findings[#findings + 1] = { file = path, line = n, col = 1, rule = rule, severity = SEVERITY[rule], message = msg }
    end
    for name, why in pairs(BANNED) do
      if code:find("%f[%w_]" .. name .. "%f[^%w_]") and not code:find("[%.:]" .. name) then rep("L4", name .. ": " .. why) end
    end
    for s, why in pairs(BANNED_STRINGS) do if code:find('"' .. s .. '"', 1, true) then rep("L4", s .. ": " .. why) end end
    for ev in code:gmatch('Register%w*Event%(%s*"([%w_]+)"') do
      note("events", ev)
      if not T.events[ev] and not BANNED_STRINGS[ev] then rep("L5", "unknown event " .. ev) end
    end
    if not allowPerf and (code:find('"OnUpdate"', 1, true) or code:find("C_Timer%.New[TT]i")) then rep("L7", "OnUpdate/ticker outside tools/perf_allow.txt") end
    if code:match("^%s*C_ChatInfo%.Send%w+%(") or code:match("^%s*Send%w*Message%(") then rep("L9", "chat/addon message result discarded") end
  end
end

---------------------------------------------------------------------------
-- XML and TOC
---------------------------------------------------------------------------
local function lintXml(path, src)
  local allowPerf = perfAllowed(path)
  local n = 0
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local function rep(rule, msg)
      if line:match("lint:%s*allow") then return end
      findings[#findings + 1] = { file = path, line = n, col = 1, rule = rule, severity = SEVERITY[rule], message = msg }
    end
    for list in line:gmatch('inherits%s*=%s*"([^"]+)"') do
      for t in list:gmatch("[^,%s]+") do
        note("templates", t)
        if t == "SecureAuraHeaderTemplate" then rep("L4", BANNED_STRINGS.SecureAuraHeaderTemplate) end
      end
    end
    local name = line:match('name%s*=%s*"([%w_]+)"')
    if name and line:find('virtual%s*=%s*"true"') then globalWrites[name] = true end
    if line:find("<OnUpdate", 1, true) and not allowPerf then rep("L7", "<OnUpdate> outside tools/perf_allow.txt") end
    for f in line:gmatch('file%s*=%s*"([Ii]nterface[\\/][^"]+)"') do note("textures", f) end
    for a in line:gmatch('atlas%s*=%s*"([^"]+)"') do note("atlases", a) end
  end
end

local function readToc(src)
  for key, value in src:gmatch("##%s*([%w%-]+):%s*([^\r\n]*)") do
    if key == "SavedVariables" or key == "SavedVariablesPerCharacter" then
      for n in value:gmatch("[%w_]+") do globalWrites[n] = true end
    elseif key:match("^AddonCompartmentFunc") then
      globalWrites[value:match("^%s*(%S+)")] = true
    end
  end
end

---------------------------------------------------------------------------
-- File discovery and main
---------------------------------------------------------------------------
local function listFiles(target)
  local files = {}
  local f = io.open(target, "r")
  if not f then io.stderr:write("lint: no such path " .. target .. "\n"); os.exit(2) end
  f:close()
  local p = io.popen("find '" .. target:gsub("'", "'\\''") .. "' -type f \\( -name '*.lua' -o -name '*.xml' -o -name '*.toc' \\) 2>/dev/null")
  for line in p:lines() do
    if not line:lower():find("/libs/", 1, true) then files[#files + 1] = line end
  end
  p:close()
  table.sort(files)
  return files
end

local function jsonString(s)
  return '"' .. tostring(s):gsub('[%c"\\]', function(c)
    local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
    return map[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function sortedKeys(t)
  local r = {}
  for k in pairs(t) do r[#r + 1] = k end
  table.sort(r)
  return r
end

local function writeManifest(path)
  os.execute("mkdir -p '" .. (path:match("^(.*)/[^/]*$") or ".") .. "'")
  -- our own globals and Lua builtins aren't game APIs
  local LUA = { _G = 1, _VERSION = 1, assert = 1, collectgarbage = 1, error = 1, getfenv = 1, getmetatable = 1,
    ipairs = 1, load = 1, loadstring = 1, next = 1, pairs = 1, pcall = 1, print = 1, rawequal = 1, rawget = 1,
    rawset = 1, select = 1, setfenv = 1, setmetatable = 1, tonumber = 1, tostring = 1, type = 1, unpack = 1,
    xpcall = 1, gcinfo = 1, string = 1, table = 1, math = 1, coroutine = 1, bit = 1, os = 1 }
  for name in pairs(manifest.apis) do
    local base = name:match("^([%w_]+)")
    local own = globalWrites[base] or OWN[base] or LUA[base]
    for _, p in ipairs(OWN_PATTERNS) do if base:match(p) then own = true end end
    if own then manifest.apis[name] = nil end
  end
  local fh = assert(io.open(path, "w"))
  fh:write("-- GENERATED by tools/lint.lua. Do not edit.\n")
  fh:write("-- Everything the scanned code references, for the in-game self-test to verify:\n")
  fh:write("-- apis/templates/textures/atlases must exist, events must be valid, absent must be nil.\n")
  fh:write("return {\n")
  local abs = {}
  for _, n in ipairs(ABSENT) do abs[n] = true end
  manifest.absent = abs
  for _, kind in ipairs({ "apis", "events", "templates", "textures", "atlases", "absent" }) do
    fh:write("\t", kind, " = {\n")
    for _, v in ipairs(sortedKeys(manifest[kind])) do fh:write(string.format("\t\t%q,\n", v)) end
    fh:write("\t},\n")
  end
  fh:write("}\n")
  fh:close()
end

local function main()
  local files = {}
  for _, t in ipairs(opts.targets) do for _, f in ipairs(listFiles(t)) do files[#files + 1] = f end end
  if not parser then notes[#notes + 1] = "luacheck parser not found; running line-based fallback (L4, L5, L7, L9 only)" end
  local nLua = 0
  for _, path in ipairs(files) do
    local src = readFile(path) or ""
    if path:match("%.lua$") then
      nLua = nLua + 1
      if parser then lintAst(path, src) else lintLines(path, src) end
    elseif path:match("%.xml$") then lintXml(path, src)
    elseif path:match("%.toc$") then readToc(src) end
  end
  -- L6: unresolved global reads, now that every file's global writes are known
  for _, r in ipairs(pendingL6) do
    local ok = globalWrites[r.name] or OWN[r.name]
    for _, p in ipairs(OWN_PATTERNS) do if r.name:match(p) then ok = true end end
    if not ok then r.report("L6", r.node, "unknown global '" .. r.name .. "' (not in api_tags, FrameXML scan or globals_extra)") end
  end
  local seen, unique = {}, {}
  for _, f in ipairs(findings) do
    local key = f.file .. ":" .. f.line .. ":" .. f.rule .. ":" .. f.message
    if not seen[key] then seen[key] = true; unique[#unique + 1] = f end
  end
  findings = unique
  table.sort(findings, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    if a.line ~= b.line then return a.line < b.line end
    return a.rule < b.rule
  end)

  local errors, warns, perRule = 0, 0, {}
  for _, f in ipairs(findings) do
    if f.severity == "error" then errors = errors + 1 else warns = warns + 1 end
    perRule[f.rule] = (perRule[f.rule] or 0) + 1
  end

  local manifestPath = opts.manifest
  if not manifestPath and not opts.noManifest then
    for _, t in ipairs(opts.targets) do
      if t:gsub("^%./", ""):match("^PerlInfinity/?$") then manifestPath = ROOT .. "/tools/out/manifest.lua" end
    end
  end
  if manifestPath then writeManifest(manifestPath) end

  if opts.json then
    local parts = {}
    for _, f in ipairs(findings) do
      parts[#parts + 1] = string.format('{"file":%s,"line":%d,"col":%d,"rule":%s,"severity":%s,"message":%s}',
        jsonString(f.file), f.line, f.col, jsonString(f.rule), jsonString(f.severity), jsonString(f.message))
    end
    io.write('{"findings":[', table.concat(parts, ","), '],"summary":{"files":', #files, ',"errors":', errors,
      ',"warnings":', warns, '}}\n')
  else
    for _, n in ipairs(notes) do io.write("lint: note: ", n, "\n") end
    for _, f in ipairs(findings) do
      io.write(string.format("%s:%d:%d: %s %s: %s\n", f.file, f.line, f.col, f.rule, f.severity, f.message))
    end
    local rules = {}
    for _, r in ipairs(sortedKeys(perRule)) do rules[#rules + 1] = r .. "=" .. perRule[r] end
    io.write(string.format("lint: %d files (%d Lua), %d errors, %d warnings%s%s\n", #files, nLua, errors, warns,
      #rules > 0 and ("  [" .. table.concat(rules, " ") .. "]") or "",
      manifestPath and ("  manifest -> " .. manifestPath:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", "")) or ""))
  end
  return errors
end

local ok, res = xpcall(main, debug.traceback)
if not ok then
  io.stderr:write("lint: internal error: ", tostring(res), "\n")
  os.exit(2)
end
if opts.strict and res > 0 then os.exit(1) end
os.exit(0)
