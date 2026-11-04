-- tests/harness/widgets.lua
-- Widget object model: CreateFrame and regions, method tables built from api_tags
-- (every documented method exists; unit-frame ones are implemented in widget_types.lua),
-- secret argument rules, secret aspects, protected methods in combat, scripts,
-- event registration/dispatch, visibility (OnShow/OnHide), templates, simple anchor
-- resolution to absolute rects, and a call log for assertions.

local Secret = require("secret")
local Api = require("api")

local Widgets = {}

-- Implementation chains: first table that defines a method wins.
local IMPL_CHAIN = {
  Frame = { "Frame", "Common" },
  Button = { "Button", "Frame", "Common" },
  CheckButton = { "CheckButton", "Button", "Frame", "Common" },
  StatusBar = { "StatusBar", "Frame", "Common" },
  Cooldown = { "Cooldown", "Frame", "Common" },
  EditBox = { "EditBox", "Frame", "Common" },
  GameTooltip = { "GameTooltip", "Frame", "Common" },
  Model = { "Model", "Frame", "Common" },
  PlayerModel = { "Model", "Frame", "Common" },
  DressUpModel = { "Model", "Frame", "Common" },
  AuraContainer = { "Frame", "Common" },
  Slider = { "Slider", "Frame", "Common" },
  ScrollFrame = { "Frame", "Common" },
  EventFrame = { "Frame", "Common" },
  DropdownButton = { "Button", "Frame", "Common" },
  MessageFrame = { "Frame", "Common" },
  ColorSelect = { "Frame", "Common" },
  Texture = { "Texture", "Region", "Common" },
  MaskTexture = { "Texture", "Region", "Common" },
  Line = { "Texture", "Region", "Common" },
  FontString = { "FontString", "Region", "Common" },
  AnimationGroup = { "AnimationGroup", "Object" },
  Animation = { "Animation", "Object" },
  Alpha = { "Alpha", "Animation", "Object" },
  Scale = { "Scale", "Animation", "Object" },
  Translation = { "Translation", "Animation", "Object" },
  Rotation = { "Rotation", "Animation", "Object" },
  FlipBook = { "Animation", "Object" },
  Font = { "Font", "Object" },
  VertexColor = { "Animation", "Object" },
}
Widgets.IMPL_CHAIN = IMPL_CHAIN

-- IsObjectType hierarchy
local IS_A = {
  Frame = { "Frame", "Region", "ScriptRegion", "Object" },
  Texture = { "Texture", "TextureBase", "Region", "ScriptRegion", "Object" },
  FontString = { "FontString", "Region", "ScriptRegion", "Object" },
  AnimationGroup = { "AnimationGroup", "Object" },
  Animation = { "Animation", "Object" },
}
local function isA(objType, query)
  if objType == query then return true end
  local frameTypes = { Button = 1, CheckButton = 1, StatusBar = 1, Cooldown = 1, EditBox = 1, GameTooltip = 1,
    Model = 1, PlayerModel = 1, DressUpModel = 1, AuraContainer = 1, Slider = 1, ScrollFrame = 1, MessageFrame = 1, ColorSelect = 1 }
  local base = objType
  if frameTypes[objType] then
    if query == "Button" and objType == "CheckButton" then return true end
    if query == "Model" and (objType == "PlayerModel" or objType == "DressUpModel") then return true end
    base = "Frame"
  elseif objType == "MaskTexture" or objType == "Line" then base = "Texture"
  elseif IMPL_CHAIN[objType] and IMPL_CHAIN[objType][2] == "Animation" then base = "Animation" end
  for _, t in ipairs(IS_A[base] or {}) do if t == query then return true end end
  return false
end

local FRAME_SCRIPTS = {}
for _, s in ipairs({ "OnEvent", "OnUpdate", "OnShow", "OnHide", "OnLoad", "OnAttributeChanged", "OnEnter",
  "OnLeave", "OnMouseDown", "OnMouseUp", "OnMouseWheel", "OnClick", "PreClick", "PostClick", "OnDoubleClick",
  "OnSizeChanged", "OnValueChanged", "OnMinMaxChanged", "OnDragStart", "OnDragStop", "OnReceiveDrag",
  "OnTextChanged", "OnEnterPressed", "OnEscapePressed", "OnTabPressed", "OnSpacePressed", "OnEditFocusLost",
  "OnEditFocusGained", "OnChar", "OnKeyDown", "OnKeyUp", "OnCooldownDone", "OnModelLoaded", "OnTooltipSetDefaultAnchor",
  "OnTooltipCleared", "OnTooltipSetItem", "OnTooltipSetUnit", "OnTooltipSetSpell", "OnHyperlinkClick",
  "OnHyperlinkEnter", "OnHyperlinkLeave", "OnTextSet", "OnCursorChanged", "OnInputLanguageChanged",
  "OnGamePadButtonDown", "OnGamePadButtonUp", "OnGamePadStick", "OnVerticalScroll", "OnHorizontalScroll",
  "OnScrollRangeChanged", "OnArrowPressed", "OnDisable", "OnEnable", "OnChar", "OnColorSelect", "OnUpdateModel" }) do
  FRAME_SCRIPTS[s] = true
end
local REGION_SCRIPTS = { OnShow = true, OnHide = true, OnEnter = true, OnLeave = true, OnMouseDown = true, OnMouseUp = true,
  OnSizeChanged = true, OnLoad = true }
local ANIM_SCRIPTS = { OnPlay = true, OnFinished = true, OnStop = true, OnLoop = true, OnPause = true, OnUpdate = true, OnLoad = true }

-- Protected in combat on protected frames, in addition to the doc's IsProtectedFunction tag.
local EXTRA_PROTECTED = { SetAttribute = true, ClearAttribute = true }

function Widgets.install(h)
  local W = {
    h = h, state = setmetatable({}, { __mode = "k" }), classes = {}, impl = {},
    templates = {}, unknownTemplates = {}, unimplementedTemplates = {},
    eventOrder = {}, eventSets = {}, onUpdate = {}, all = {}, calls = {}, record = true,
    animGroups = {}, created = 0,
  }
  h.widgets = W
  W.FRAME_SCRIPTS, W.REGION_SCRIPTS, W.ANIM_SCRIPTS, W.isA = FRAME_SCRIPTS, REGION_SCRIPTS, ANIM_SCRIPTS, isA
  W.IMPL_CHAIN = IMPL_CHAIN
  local tags = h.tags
  local env = h.env

  ---------------------------------------------------------------------------
  -- State helpers
  ---------------------------------------------------------------------------
  function W.st(obj)
    local st = W.state[obj]
    if not st then error("not a widget (did you call a method with '.' instead of ':'?)", 3) end
    return st
  end
  W.inspect = function(obj) return W.state[obj] end

  function W.recordCall(obj, method, ...)
    if not W.record then return end
    W.calls[#W.calls + 1] = { obj = obj, method = method, n = select("#", ...), ... }
  end

  function W.callsTo(obj, method)
    local r = {}
    for _, c in ipairs(W.calls) do
      if (obj == nil or c.obj == obj) and (method == nil or c.method == method) then r[#r + 1] = c end
    end
    return r
  end

  function W.clearCalls() W.calls = {} end

  ---------------------------------------------------------------------------
  -- Script calls (errors go through the WoW-style handler chain)
  ---------------------------------------------------------------------------
  local function traceback(e)
    if type(e) == "table" then return e end
    return { msg = e, stack = debug.traceback("", 2) }
  end

  function W.callScript(obj, name, ...)
    local st = W.state[obj]
    if not st then return end
    local fn = st.scripts[name]
    local hooks = st.hooks[name]
    if not fn and not hooks then return false end
    h.stats.scriptCalls = h.stats.scriptCalls + 1
    if name == "OnUpdate" then h.stats.onUpdateCalls = h.stats.onUpdateCalls + 1 end
    if fn then
      local ok, err = xpcall(fn, traceback, obj, ...)
      if not ok then h:dispatchError(err.msg, (st.name or st.type) .. ":" .. name, err.stack) end
    end
    if hooks then
      for _, hook in ipairs(hooks) do
        local ok, err = xpcall(hook, traceback, obj, ...)
        if not ok then h:dispatchError(err.msg, (st.name or st.type) .. ":" .. name .. " (hook)", err.stack) end
      end
    end
    return true
  end

  ---------------------------------------------------------------------------
  -- Visibility
  ---------------------------------------------------------------------------
  function W.isVisible(obj)
    local st = W.state[obj]
    while st do
      if not st.shown or st.rolesetFiltered then return false end
      if not st.parent then return true end -- top-level frames (no parent) render too
      st = W.state[st.parent]
    end
    return false
  end

  -- Run fn (which changes shown/parent state) and fire OnShow/OnHide for every frame
  -- in obj's subtree whose effective visibility flipped, parents first.
  function W.withVisibility(obj, fn)
    local before = {}
    local function collect(o, list)
      list[#list + 1] = o
      local s = W.state[o]
      for _, c in ipairs(s.children) do collect(c, list) end
      for _, r in ipairs(s.regions or {}) do list[#list + 1] = r end
    end
    local list = {}
    collect(obj, list)
    for _, o in ipairs(list) do before[o] = W.isVisible(o) end
    fn()
    for _, o in ipairs(list) do
      local now = W.isVisible(o)
      if now ~= before[o] then
        local s = W.state[o]
        if s.kind == "frame" then W.callScript(o, now and "OnShow" or "OnHide") end
        if now and s.onShowInternal then s.onShowInternal(o) end
      end
    end
  end

  ---------------------------------------------------------------------------
  -- Protection and secret anchoring
  ---------------------------------------------------------------------------
  function W.isProtected(obj, seen)
    local st = W.state[obj]
    if not st then return false end
    if st.secure then return true end
    seen = seen or {}
    if seen[obj] then return false end
    seen[obj] = true
    for _, c in ipairs(st.children) do if W.isProtected(c, seen) then return true end end
    for dep in pairs(st.dependents) do if W.isProtected(dep, seen) then return true end end
    return false
  end

  function W.anchoringSecret(obj, seen)
    local st = W.state[obj]
    if not st then return false end
    if st.secretSize or (st.aspects.Text and st.type == "FontString") then return true end
    seen = seen or {}
    if seen[obj] then return false end
    seen[obj] = true
    for _, p in ipairs(st.points) do
      if p.rel and W.anchoringSecret(p.rel, seen) then return true end
    end
    return false
  end

  ---------------------------------------------------------------------------
  -- Geometry: resolve anchors to absolute rects (UIParent = 0,0 .. 1920,1080)
  ---------------------------------------------------------------------------
  local SCREEN_W, SCREEN_H = 1920, 1080
  local function pointXY(rect, point)
    local l, b, w, hgt = rect[1], rect[2], rect[3], rect[4]
    point = point:upper()
    local x = l + w / 2
    if point:find("LEFT") then x = l elseif point:find("RIGHT") then x = l + w end
    local y = b + hgt / 2
    if point:find("TOP") then y = b + hgt elseif point:find("BOTTOM") then y = b end
    return x, y
  end

  function W.effectiveScale(obj)
    local scale, st = 1, W.state[obj]
    while st do
      scale = scale * (st.scale or 1)
      st = st.parent and W.state[st.parent]
    end
    return scale
  end

  function W.rect(obj, depth)
    depth = (depth or 0) + 1
    if depth > 64 then error("anchor family loop", 0) end
    local st = W.state[obj]
    if st.isRoot then return { 0, 0, SCREEN_W, SCREEN_H } end
    local w, hgt = st.width, st.height
    if st.type == "FontString" and (w == nil or w == 0) then w = W.stringWidth(obj) end
    if st.type == "FontString" and (hgt == nil or hgt == 0) then hgt = st.fontSize or 12 end
    local pts = st.points
    if #pts == 0 then return nil end
    local xs, ys = {}, {}
    for _, p in ipairs(pts) do
      local relObj = p.rel or st.parent
      local rr = relObj and W.rect(relObj, depth)
      if rr then
        -- A rect is in its frame's own scaled units, and so are that frame's
        -- anchor offsets, so the anchor spot converts from the other frame's units.
        local ax, ay = pointXY(rr, p.relPoint)
        local k = W.effectiveScale(relObj) / W.effectiveScale(obj)
        ax, ay = ax * k + (p.x or 0), ay * k + (p.y or 0)
        local P = p.point:upper()
        if P:find("LEFT") then xs.l = ax elseif P:find("RIGHT") then xs.r = ax else xs.c = ax end
        if P:find("TOP") then ys.t = ay elseif P:find("BOTTOM") then ys.b = ay else ys.c = ay end
      end
    end
    w, hgt = w or 0, hgt or 0
    local l, b
    if xs.l and xs.r then l = xs.l; w = xs.r - xs.l
    elseif xs.l then l = xs.l elseif xs.r then l = xs.r - w elseif xs.c then l = xs.c - w / 2 end
    if ys.t and ys.b then b = ys.b; hgt = ys.t - ys.b
    elseif ys.b then b = ys.b elseif ys.t then b = ys.t - hgt elseif ys.c then b = ys.c - hgt / 2 end
    if not l or not b then return nil end
    return { l, b, w, hgt }
  end

  function W.stringWidth(obj)
    local st = W.state[obj]
    local text = Secret.raw(st.text)
    if text == nil then return 0 end
    text = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return #text * (st.fontSize or 12) * 0.5
  end

  ---------------------------------------------------------------------------
  -- Events
  ---------------------------------------------------------------------------
  local EXTRA_EVENTS = {} -- events the harness accepts even though the docs lack them
  W.EXTRA_EVENTS = EXTRA_EVENTS

  function W.checkEvent(event, what)
    if type(event) ~= "string" then error(what .. ": event must be a string", 3) end
    local e = tags.events[event]
    if not e and not EXTRA_EVENTS[event] then
      error(string.format('%s: Attempt to register unknown event "%s"', what, event), 3)
    end
    if e and e.HasRestrictions then
      h:forbidden(what .. "(" .. event .. ")")
      return false
    end
    return true
  end

  function W.registerEvent(obj, event, units)
    local list = W.eventOrder[event]
    if not list then list = {}; W.eventOrder[event] = list; W.eventSets[event] = {} end
    local set = W.eventSets[event]
    if not set[obj] then
      list[#list + 1] = obj
      set[obj] = true
    end
    local st = W.state[obj]
    st.events[event] = units or true
  end

  function W.unregisterEvent(obj, event)
    local set = W.eventSets[event]
    if set and set[obj] then
      set[obj] = nil
      local list = W.eventOrder[event]
      for i = #list, 1, -1 do if list[i] == obj then table.remove(list, i) end end
    end
    W.state[obj].events[event] = nil
  end

  function W.dispatch(event, ...)
    local list = W.eventOrder[event]
    if not list then return 0 end
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    local n = 0
    local unit = ...
    for _, obj in ipairs(snapshot) do
      local st = W.state[obj]
      local reg = st and st.events[event]
      if reg then
        local deliver = true
        if type(reg) == "table" then
          deliver = false
          for _, u in ipairs(reg) do if u == unit then deliver = true end end
        end
        if deliver then
          n = n + 1
          W.callScript(obj, "OnEvent", event, ...)
        end
      end
    end
    return n
  end

  ---------------------------------------------------------------------------
  -- Method tables
  ---------------------------------------------------------------------------
  local function docEntry(objType, method)
    local chain = tags.widgetTypes[objType]
    if not chain then return nil end
    for _, doc in ipairs(chain) do
      local d = tags.widgets[doc] or tags.objects[doc]
      if d and d[method] then return d[method], doc end
    end
  end
  W.docEntry = docEntry

  local function wrapMethod(objType, method, impl, entry)
    local label = objType .. ":" .. method
    local protectedTag = entry and entry.IsProtectedFunction or EXTRA_PROTECTED[method]
    local addAspects = entry and entry.SecretArgumentsAddAspect
    local aspectReturns = entry and entry.SecretReturnsForAspect
    local anchorSecret = entry and entry.SecretWhenAnchoringSecret
    return function(self, ...)
      local st = W.state[self]
      if not st then error(label .. ": called on a non-widget (use ':' not '.')", 2) end
      W.recordCall(self, method, ...)
      if entry then Api.checkSecretArgs(label, entry, ...) end
      if protectedTag and h.world.inCombat and W.isProtected(self) then
        h:blockedAction(label, self)
        return
      end
      if addAspects and Secret.anySecret(...) then
        for _, a in ipairs(addAspects) do st.aspects[a] = true end
      end
      local res
      if impl then
        res = { pcall(impl, self, ...) }
        if not res[1] then error(W.relocate(res[2]), 2) end
        table.remove(res, 1)
      else
        res = {}
        W.stubCalls[label] = (W.stubCalls[label] or 0) + 1
        for i, r in ipairs(entry and entry.rets or {}) do
          if not r.nilable then
            local t = r[2]
            if t == "bool" then res[i] = false
            elseif t == "number" or t == "uiUnit" or t == "SingleColorValue" then res[i] = 0
            elseif t == "cstring" or t == "string" then res[i] = "" end
          end
        end
      end
      local n = table.maxn(res)
      if n > 0 then
        local wrap = false
        if aspectReturns then for _, a in ipairs(aspectReturns) do if st.aspects[a] then wrap = true end end end
        if anchorSecret and W.anchoringSecret(self) then wrap = true end
        if wrap then for i = 1, n do res[i] = Secret.wrap(res[i]) end end
      end
      return unpack(res, 1, n)
    end
  end

  W.stubCalls = {}

  -- Errors raised inside harness code are re-raised at the addon's call site.
  -- Parameter names WoW gives inline XML script handlers.
  W.SCRIPT_PARAMS = {
    OnEvent = "self, event, ...",
    OnAttributeChanged = "self, name, value",
    OnClick = "self, button, down",
    PreClick = "self, button, down",
    PostClick = "self, button, down",
    OnEnter = "self, motion",
    OnLeave = "self, motion",
    OnUpdate = "self, elapsed",
    OnMouseDown = "self, button",
    OnMouseUp = "self, button",
    OnMouseWheel = "self, delta",
    OnValueChanged = "self, value, userInput",
    OnSizeChanged = "self, width, height",
    OnTextChanged = "self, userInput",
    OnDragStart = "self, button",
    OnLoad = "self",
    OnShow = "self",
    OnHide = "self",
  }

  function W.relocate(e)
    -- PERLINFINITY_RAW=1 keeps the harness location, for debugging the harness itself.
    if os.getenv("PERLINFINITY_RAW") then return e end
    if type(e) == "string" then e = e:gsub("^[^\n]-tests/harness/[^:]*:%d+: ", "") end
    return e
  end

  function W.class(objType)
    local cls = W.classes[objType]
    if cls then return cls end
    cls = {}
    -- documented methods first (generic stubs), then implementations override
    for _, doc in ipairs(tags.widgetTypes[objType] or {}) do
      for method in pairs(tags.widgets[doc] or tags.objects[doc] or {}) do
        if not cls[method] then cls[method] = wrapMethod(objType, method, nil, (docEntry(objType, method))) end
      end
    end
    local chain = IMPL_CHAIN[objType] or { "Frame", "Common" }
    for i = #chain, 1, -1 do
      for method, impl in pairs(W.impl[chain[i]] or {}) do
        cls[method] = wrapMethod(objType, method, impl, (docEntry(objType, method)))
      end
    end
    W.classes[objType] = { __index = cls, __tostring = function(o)
      local s = W.state[o]; return s and ("<" .. s.type .. " " .. tostring(s.name or "anon") .. ">") or "<widget>" end }
    return W.classes[objType]
  end

  ---------------------------------------------------------------------------
  -- Object creation
  ---------------------------------------------------------------------------
  local function resolveParent(parent)
    if type(parent) == "string" then return env[parent] end
    return parent
  end

  function W.newObject(objType, kind, name, parent)
    local obj = setmetatable({ [0] = newproxy() }, W.class(objType))
    local st = {
      type = objType, kind = kind, name = name, parent = parent, children = {}, regions = {},
      shown = true, points = {}, dependents = setmetatable({}, { __mode = "k" }), alpha = 1, scale = 1,
      scripts = {}, hooks = {}, events = {}, attributes = {}, aspects = {}, id = 0,
      strata = "MEDIUM", level = 0, created = W.created,
    }
    W.created = W.created + 1
    W.state[obj] = st
    W.all[#W.all + 1] = obj
    if name then
      name = name:gsub("%$parent", parent and W.state[parent] and W.state[parent].name or "")
      st.name = name
      env[name] = obj
    end
    if parent and W.state[parent] then
      local ps = W.state[parent]
      if kind == "frame" then ps.children[#ps.children + 1] = obj else ps.regions[#ps.regions + 1] = obj end
      st.level = (ps.level or 0) + 1
      st.strata = ps.strata
    end
    return obj, st
  end

  -- Template application (inherits first, comma lists left to right).
  function W.applyTemplates(obj, templateList, loadQueue, seen)
    if not templateList or templateList == "" then return end
    seen = seen or {}
    for name in tostring(templateList):gmatch("[^,%s]+") do
      if not seen[name] then
        seen[name] = true
        local t = W.templates[name]
        if t then
          if t.inherits then W.applyTemplates(obj, t.inherits, loadQueue, seen) end
          W.applyTemplate(obj, t, loadQueue)
        elseif h.blizzardTemplates[name] then
          W.unimplementedTemplates[name] = (W.unimplementedTemplates[name] or 0) + 1
          local bt = h.blizzardTemplates[name]
          if bt.inherits then W.applyTemplates(obj, bt.inherits, loadQueue, seen) end
          if bt.mixin then
            for m in bt.mixin:gmatch("[^,%s]+") do if type(env[m]) == "table" then env.Mixin(obj, env[m]) end end
          end
        else
          W.unknownTemplates[name] = (W.unknownTemplates[name] or 0) + 1
          h:warn("unknown template '" .. name .. "'")
        end
      end
    end
  end

  function W.applyTemplate(obj, t, loadQueue)
    local st = W.state[obj]
    if t.secure then st.secure = true end
    if t.mixin then
      for m in t.mixin:gmatch("[^,%s]+") do
        local mix = env[m]
        if type(mix) ~= "table" then
          h:dispatchError(string.format("template %s: mixin '%s' is not defined", t.name or "?", m), "CreateFrame")
        else
          env.Mixin(obj, mix)
        end
      end
    end
    if t.keyValues then for k, v in pairs(t.keyValues) do obj[k] = v end end
    if t.size then
      if t.size.x then st.width = t.size.x end
      if t.size.y then st.height = t.size.y end
    end
    if t.attributes then for k, v in pairs(t.attributes) do st.attributes[k:lower()] = v; st.attrNames = st.attrNames end end
    if t.children then for _, c in ipairs(t.children) do W.createChildFromSpec(obj, c) end end
    if t.scripts then
      for scriptName, s in pairs(t.scripts) do
        local fn
        if s.method then
          local m = s.method
          fn = function(self, ...)
            local f = self[m]
            if type(f) ~= "function" then error(string.format("script %s: method '%s' missing", scriptName, m), 2) end
            return f(self, ...)
          end
        elseif s.func then
          local fname = s.func
          fn = function(self, ...)
            local f = env[fname]
            if type(f) ~= "function" then error(string.format("script %s: function '%s' missing", scriptName, fname), 2) end
            return f(self, ...)
          end
        elseif s.code then
          -- Inline XML handlers get WoW's parameter names for each script type.
          local params = W.SCRIPT_PARAMS[scriptName] or "self, ..."
          local chunk, err = loadstring("return function(" .. params .. ") " .. s.code .. "\nend", "=" .. (t.name or "xml") .. ":" .. scriptName)
          if not chunk then h:dispatchError(err, "template " .. tostring(t.name)) else setfenv(chunk, env); fn = chunk() end
        end
        if fn then
          if scriptName == "OnLoad" then loadQueue[#loadQueue + 1] = fn
          elseif s.intrinsicOrder == "postcall" and st.scripts[scriptName] then
            st.hooks[scriptName] = st.hooks[scriptName] or {}
            table.insert(st.hooks[scriptName], fn)
          else
            st.scripts[scriptName] = fn
          end
        end
      end
    end
    if t.apply then t.apply(obj, st, h) end
  end

  function W.createChildFromSpec(parent, c)
    local child
    if c.objType == "Texture" or c.objType == "FontString" or c.objType == "MaskTexture" then
      local creator = c.objType == "FontString" and parent.CreateFontString or parent.CreateTexture
      if c.objType == "MaskTexture" then creator = parent.CreateMaskTexture end
      child = creator(parent, c.name, c.layer, c.inherits)
    else
      child = env.CreateFrame(c.objType, c.name, parent, c.inherits)
    end
    local cs = W.state[child]
    if c.size then cs.width, cs.height = c.size.x or cs.width, c.size.y or cs.height end
    if c.setAllPoints then child:SetAllPoints(parent) end
    for _, a in ipairs(c.anchors or {}) do
      local rel = a.relativeKey and parent[a.relativeKey:gsub("^%$parent%.", "")] or (a.relativeTo and env[a.relativeTo]) or parent
      child:SetPoint(a.point, rel, a.relativePoint or a.point, a.x or 0, a.y or 0)
    end
    if c.hidden then cs.shown = false end
    if c.parentKey then parent[c.parentKey] = child end
    if c.parentArray then parent[c.parentArray] = parent[c.parentArray] or {}; table.insert(parent[c.parentArray], child) end
    if c.file and child.SetTexture then child:SetTexture(c.file) end
    if c.atlas and child.SetAtlas then child:SetAtlas(c.atlas) end
    if c.text and child.SetText then child:SetText(c.text) end
    return child
  end

  local VALID_FRAME_TYPES = {}
  for t in pairs(IMPL_CHAIN) do VALID_FRAME_TYPES[t] = true end
  for _, t in ipairs({ "Texture", "FontString", "MaskTexture", "Line", "AnimationGroup", "Animation", "Alpha",
    "Scale", "Translation", "Rotation", "FlipBook", "VertexColor" }) do VALID_FRAME_TYPES[t] = nil end

  env.CreateFrame = function(frameType, name, parent, template, id)
    if Secret.anySecret(frameType, name, parent, template, id) then error("CreateFrame: Object did not allow secret", 2) end
    if type(frameType) ~= "string" then error("CreateFrame: frameType must be a string", 2) end
    local ft = frameType
    for t in pairs(VALID_FRAME_TYPES) do if t:lower() == frameType:lower() then ft = t end end
    if not VALID_FRAME_TYPES[ft] then error('CreateFrame: Unknown frame type "' .. tostring(frameType) .. '"', 2) end
    parent = resolveParent(parent)
    local obj, st = W.newObject(ft, "frame", name, parent)
    if id then st.id = id end
    if W.onCreate[ft] then W.onCreate[ft](obj, st) end
    local loadQueue = {}
    W.applyTemplates(obj, template, loadQueue)
    st.template = template
    for _, fn in ipairs(loadQueue) do
      local ok, err = xpcall(fn, traceback, obj)
      if not ok then h:dispatchError(err.msg, (name or ft) .. ":OnLoad", err.stack) end
    end
    if W.state[obj].scripts.OnLoad then W.callScript(obj, "OnLoad") end
    return obj
  end

  W.onCreate = {}

  -- Deterministic text dump of a frame tree for golden layout snapshots:
  -- one line per shown region: path, type, rect (L,B,W,H), and visual state.
  function W.layoutDump(rootObj, opts)
    opts = opts or {}
    local lines = {}
    local function fmt(n) return n and string.format("%.1f", Secret.raw(n)) or "?" end
    local function label(o, parentPath, i)
      local s = W.state[o]
      local key
      if s.parent then for k, v in pairs(s.parent) do if v == o and type(k) == "string" then key = k end end end
      return parentPath .. "/" .. (key or s.name or (s.type .. "#" .. i))
    end
    local function visit(o, path, depth)
      local s = W.state[o]
      if not s.shown and not opts.includeHidden then return end
      local r = W.rect(o)
      local parts = { path, s.type, r and (fmt(r[1]) .. "," .. fmt(r[2]) .. "," .. fmt(r[3]) .. "," .. fmt(r[4])) or "unanchored" }
      if s.layer then parts[#parts + 1] = "layer=" .. s.layer end
      if s.texture then parts[#parts + 1] = "tex=" .. tostring(s.texture) end
      if s.atlas then parts[#parts + 1] = "atlas=" .. tostring(s.atlas) end
      local function rgba(c) local t = {}; for i = 1, 4 do t[i] = fmt(c[i] or 1) end; return table.concat(t, ",") end
      if s.color then parts[#parts + 1] = "color=" .. rgba(s.color) end
      if s.vertexColor then parts[#parts + 1] = "vc=" .. rgba(s.vertexColor) end
      if s.barColor then parts[#parts + 1] = "bar=" .. rgba(s.barColor) end
      if s.textColor then parts[#parts + 1] = "tc=" .. rgba(s.textColor) end
      if s.backdropColor then parts[#parts + 1] = "bg=" .. rgba(s.backdropColor) end
      if s.backdropBorderColor then parts[#parts + 1] = "border=" .. rgba(s.backdropBorderColor) end
      if s.fontSize and s.type == "FontString" then parts[#parts + 1] = "size=" .. fmt(s.fontSize) end
      if s.text then parts[#parts + 1] = "text=" .. string.format("%q", tostring(s.text)) .. (s.textSecret and "(secret)" or "") end
      if s.value then parts[#parts + 1] = string.format("value=%s/%s..%s", fmt(s.value), fmt(s.min), fmt(s.max)) end
      if s.alpha ~= 1 then parts[#parts + 1] = "alpha=" .. fmt(s.alpha) end
      lines[#lines + 1] = string.rep("  ", depth) .. table.concat(parts, " ")
      for i, rg in ipairs(s.regions) do visit(rg, label(rg, path, i), depth + 1) end
      for i, c in ipairs(s.children) do visit(c, label(c, path, i), depth + 1) end
    end
    visit(rootObj, W.state[rootObj].name or W.state[rootObj].type, 0)
    return table.concat(lines, "\n")
  end

  require("widget_types").install(W, h)

  -- Root frames
  local function root(name, isRoot)
    local obj, st = W.newObject("Frame", "frame", name, nil)
    st.isRoot = isRoot
    st.width, st.height = SCREEN_W, SCREEN_H
    return obj
  end
  W.UIParent = root("UIParent", true)
  W.WorldFrame = root("WorldFrame", true)
  return W
end

return Widgets
