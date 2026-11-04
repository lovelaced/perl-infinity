-- tests/harness/init.lua
-- One harness instance = one fresh client: sandbox env, world, widgets, API mocks.
--
--   local Harness = dofile("tests/harness/init.lua")
--   local h = Harness.new{ mode = "strict" }      -- "open" | "field" | "strict"
--   h:loadToc("PerlInfinity/PerlInfinity.toc")
--   h:login{ PerlInfinityDB = {...} }                    -- ADDON_LOADED, PLAYER_LOGIN, PLAYER_ENTERING_WORLD
--   h.world:damage("target", 120); h:advance(1)
--   assert(#h:problems() == 0)

local here = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "tests/harness"
if not package.path:find(here, 1, true) then
  package.path = here .. "/?.lua;" .. here .. "/stubs/?.lua;" .. package.path
end

local Secret = require("secret")
local Env = require("env")
local Api = require("api")
local World = require("world")
local Widgets = require("widgets")

local Harness = { root = here }
Harness.__index = Harness
Harness.Secret = Secret

local TAGS, TEMPLATES

function Harness.new(opts)
  opts = opts or {}
  local h = setmetatable({}, Harness)
  h.mode = opts.mode or "strict"
  assert(h.mode == "open" or h.mode == "field" or h.mode == "strict", "mode must be open, field or strict")
  h.addonName = opts.addonName or "PerlInfinity"
  h.verbose = opts.verbose
  Secret.taint = h.addonName
  h.clock = opts.clock or 1000
  h.errors, h.actions, h.warnings, h.printed, h.timers = {}, {}, {}, {}, {}
  h.stats = { scriptCalls = 0, onUpdateCalls = 0, events = 0, timerCalls = 0 }
  h.apiCalls = {}
  TAGS = TAGS or require("api_tags")
  TEMPLATES = TEMPLATES or require("blizzard_templates")
  h.tags, h.blizzardTemplates = TAGS, TEMPLATES

  h.env = Env.new(h)
  h.env.Enum, h.env.Constants = Api.buildEnum(h)
  h.world = World.new(h)
  Widgets.install(h)
  h.env.UIParent, h.env.WorldFrame = h.widgets.UIParent, h.widgets.WorldFrame
  require("blizzard").install(h)
  require("ui_templates").install(h)
  require("curves").install(h)
  require("unitapi").install(h)
  require("auracontainer").install(h)
  require("secure").install(h)
  require("settings").install(h)
  require("blizzard_frames").install(h)
  h.stubCount = Api.installStubs(h)
  return h
end

---------------------------------------------------------------------------
-- Problems: errors, forbidden/blocked actions, warnings
---------------------------------------------------------------------------
function Harness:reportError(msg, where, stack)
  if Secret.is(msg) then msg = "<secret error message> " .. tostring(Secret.raw(msg)) end
  local e = { msg = tostring(msg), where = where, stack = stack, time = self.clock }
  self.errors[#self.errors + 1] = e
  if self.verbose then io.stderr:write("[harness error] ", e.msg, where and (" @" .. where) or "", "\n") end
end

-- set by env.lua (records, then runs the addon-visible handler chain)
function Harness:dispatchError(msg, where, stack) self:reportError(msg, where, stack) end

function Harness:warn(msg)
  self.warnings[#self.warnings + 1] = msg
  if self.verbose then io.stderr:write("[harness warn] ", msg, "\n") end
end

function Harness:forbidden(fn)
  self.actions[#self.actions + 1] = { kind = "FORBIDDEN", fn = fn, stack = debug.traceback("", 2), time = self.clock }
  self:fire("ADDON_ACTION_FORBIDDEN", self.addonName, fn)
end

function Harness:blockedAction(fn)
  self.actions[#self.actions + 1] = { kind = "BLOCKED", fn = fn, stack = debug.traceback("", 2), time = self.clock }
  self:fire("ADDON_ACTION_BLOCKED", self.addonName, fn)
end

-- Every problem that should fail a test.
function Harness:problems()
  local r = {}
  for _, e in ipairs(self.errors) do r[#r + 1] = "Lua error: " .. e.msg .. (e.where and ("  [" .. e.where .. "]") or "") end
  for _, a in ipairs(self.actions) do r[#r + 1] = "ADDON_ACTION_" .. a.kind .. ": " .. a.fn end
  return r
end

function Harness:clearProblems()
  self.errors, self.actions = {}, {}
end

function Harness:protectedCall(fn, where, ...)
  local ok, err = xpcall(fn, function(e) return { msg = e, stack = debug.traceback("", 2) } end, ...)
  if not ok then self:dispatchError(err.msg, where, err.stack) end
  return ok
end

---------------------------------------------------------------------------
-- Events and time
---------------------------------------------------------------------------
local function payloadSecret(h, e, args)
  if h.mode == "open" or not e then return false end
  if e.SecretPayloads then return true end
  return Api.returnsSecret(h, { args = e.payload, SecretReturns = nil,
    SecretWhenUnitSpellCastRestricted = e.SecretWhenUnitSpellCastRestricted,
    SecretWhenAurasRestricted = e.SecretWhenAurasRestricted,
    SecretWhenUnitIdentityRestricted = e.SecretWhenUnitIdentityRestricted,
    SecretWhenUnitPowerRestricted = e.SecretWhenUnitPowerRestricted,
    SecretInChatMessagingLockdown = e.SecretInChatMessagingLockdown,
    SecretWhenEncounterEvent = e.SecretWhenEncounterEvent,
    SecretWhenLossOfControlInfoRestricted = e.SecretWhenLossOfControlInfoRestricted }, args)
end

function Harness:fire(event, ...)
  self.stats.events = self.stats.events + 1
  local e = self.tags.events[event]
  local n = select("#", ...)
  if e and n > 0 and payloadSecret(self, e, { ... }) then
    local args = { ... }
    for i = 1, n do
      local f = e.payload and e.payload[i]
      local isUnit = f and (f[2] or ""):match("^UnitToken") and i == 1
      if not isUnit and not (f and f.NeverSecret) and type(args[i]) ~= "table" then args[i] = Secret.wrap(args[i]) end
    end
    return self.widgets.dispatch(event, unpack(args, 1, n))
  end
  return self.widgets.dispatch(event, ...)
end

-- Advance the fake clock; runs timers, OnUpdate scripts of visible frames, animations.
function Harness:advance(seconds, step)
  step = step or (1 / 30)
  local target = self.clock + (seconds or 0)
  local W = self.widgets
  repeat
    local dt = math.min(step, target - self.clock)
    if dt <= 0 then dt = 0 end
    self.clock = self.clock + dt
    self.stats.timerCalls = self.stats.timerCalls + Env.runTimers(self)
    local list = {}
    for obj in pairs(W.onUpdate) do list[#list + 1] = obj end
    table.sort(list, function(a, b) return W.state[a].created < W.state[b].created end)
    for _, obj in ipairs(list) do
      if W.isVisible(obj) then W.callScript(obj, "OnUpdate", dt) end
    end
    W.tickAnimations(dt)
  until self.clock >= target - 1e-9
end

-- One rendered frame (flushes self-hiding OnUpdate drivers).
function Harness:frame() self:advance(1 / 60, 1 / 60) end

---------------------------------------------------------------------------
-- Addon loading and boot
---------------------------------------------------------------------------
function Harness:loadToc(tocPath, opts)
  local Loader = require("loader")
  self.addon = Loader.load(self, tocPath, opts)
  return self.addon
end

-- savedVariables: { PerlInfinityDB = {...}, PerlInfinityCharDB = {...}, PerlInfinityLog = {...} }
function Harness:login(savedVariables, isReload)
  local addon = self.addon or {}
  for _, name in ipairs(addon.savedVariables or {}) do
    if savedVariables and savedVariables[name] ~= nil then self.env[name] = savedVariables[name] end
  end
  for _, name in ipairs(addon.savedVariablesPerCharacter or {}) do
    if savedVariables and savedVariables[name] ~= nil then self.env[name] = savedVariables[name] end
  end
  self:fire("ADDON_LOADED", self.addonName, false)
  self:fire("VARIABLES_LOADED")
  self:fire("SPELLS_CHANGED")
  self:fire("PLAYER_LOGIN")
  self:fire("PLAYER_ENTERING_WORLD", not isReload, isReload and true or false)
  if self.lem then self.lem:_login() end
  self:frame()
end

-- Serialize SavedVariables like the client does; secrets/functions/userdata fail.
function Harness:saveVariables()
  local SV = require("savedvars")
  local names = {}
  for _, n in ipairs(self.addon and self.addon.savedVariables or {}) do names[#names + 1] = n end
  for _, n in ipairs(self.addon and self.addon.savedVariablesPerCharacter or {}) do names[#names + 1] = n end
  self:fire("PLAYER_LOGOUT")
  local out, problems = SV.serialize(self.env, names)
  for _, p in ipairs(problems) do self:reportError("SavedVariables: " .. p, "saveVariables") end
  return out
end

-- Simulated /reload: save, then boot a fresh client with the saved data.
function Harness:reload(opts)
  local SV = require("savedvars")
  local text = self:saveVariables()
  local data = SV.parse(text)
  local h2 = Harness.new({ mode = (opts and opts.mode) or self.mode, addonName = self.addonName, verbose = self.verbose })
  if self.addon then h2:loadToc(self.addon.tocPath) end
  h2:login(data, true)
  return h2, text
end

return Harness
