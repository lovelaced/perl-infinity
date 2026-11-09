-- tests/harness/widget_types.lua
-- Implementations of the widget methods unit frames use. Secret argument checks,
-- aspects, protection and call recording are applied by the wrapper in widgets.lua,
-- so these bodies only store raw state (Secret.raw where a sink took a secret).

local Secret = require("secret")

local T = {}

function T.install(W, h)
  local env = h.env
  local st = W.st
  local raw = Secret.raw
  local impl = W.impl

  local function setShown(self, shown)
    local s = st(self)
    shown = raw(shown) and true or false
    if s.shown == shown then return end
    W.withVisibility(self, function() s.shown = shown end)
  end

  local function regionCreate(objType, kind)
    return function(self, name, layer, inherits, sublevel)
      local obj, s = W.newObject(objType, kind, name, self)
      s.layer, s.sublevel = layer or "ARTWORK", sublevel or 0
      if objType == "FontString" then
        s.fontSize = 12
        if inherits then
          local fo = env[inherits]
          if type(fo) == "table" and fo.GetFont then s.fontObject = fo; s.font, s.fontSize = fo:GetFont() end
          if not (type(fo) == "table" and fo.GetFont) and not h.blizzardTemplates[inherits] and not W.templates[inherits] then
            W.unknownTemplates[inherits] = (W.unknownTemplates[inherits] or 0) + 1
            h:warn("unknown font object/template '" .. inherits .. "'")
          end
        end
      elseif inherits then
        W.applyTemplates(obj, inherits, {})
      end
      return obj
    end
  end

  ---------------------------------------------------------------------------
  -- Object basics (animations and everything else)
  ---------------------------------------------------------------------------
  impl.Object = {
    GetName = function(self) return st(self).name end,
    GetDebugName = function(self) local s = st(self); return s.name or ("<" .. s.type .. ">") end,
    GetObjectType = function(self) return st(self).type end,
    IsObjectType = function(self, t) return W.isA and W.isA(st(self).type, t) or st(self).type == t end,
    GetParent = function(self) return st(self).parent end,
    IsForbidden = function() return false end,
    SetParentKey = function(self, key) local s = st(self); if s.parent then s.parent[key] = self end end,
    GetParentKey = function(self)
      local s = st(self)
      if s.parent then for k, v in pairs(s.parent) do if v == self then return k end end end
    end,
    HasSecretAspect = function(self, a) return st(self).aspects[a] == true end,
    HasAnySecretAspect = function(self) return next(st(self).aspects) ~= nil end,
    HasSecretValues = function(self) return next(st(self).aspects) ~= nil end,
    IsPreventingSecretValues = function() return false end,
    SetToDefaults = function(self) st(self).aspects = {} end,
  }

  ---------------------------------------------------------------------------
  -- Shared by frames and regions (ScriptRegion + Resizing + Object)
  ---------------------------------------------------------------------------
  local Common = {}
  for k, v in pairs(impl.Object) do Common[k] = v end
  impl.Common = Common

  Common.Show = function(self) setShown(self, true) end
  Common.Hide = function(self) setShown(self, false) end
  Common.SetShown = function(self, shown) setShown(self, shown) end
  Common.IsShown = function(self) return st(self).shown end
  Common.IsVisible = function(self) return W.isVisible(self) end
  Common.SetParent = function(self, parent)
    if type(parent) == "string" then parent = env[parent] end
    local s = st(self)
    W.withVisibility(self, function()
      if s.parent then
        local ps = W.state[s.parent]
        local list = s.kind == "frame" and ps.children or ps.regions
        for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
      end
      s.parent = parent
      if parent then
        local ps = st(parent)
        local list = s.kind == "frame" and ps.children or ps.regions
        list[#list + 1] = self
      end
    end)
  end
  Common.GetParent = function(self) return st(self).parent end
  Common.SetScript = function(self, name, fn)
    local s = st(self)
    local valid = (s.kind == "frame" and W.FRAME_SCRIPTS[name]) or (s.kind ~= "frame" and W.REGION_SCRIPTS[name])
    if not valid then error(string.format('%s doesn\'t have a "%s" script', s.type, tostring(name)), 3) end
    if fn ~= nil and type(fn) ~= "function" then error("SetScript: handler must be a function or nil", 3) end
    s.scripts[name] = fn
    if name == "OnUpdate" then W.onUpdate[self] = fn and true or nil end
  end
  Common.GetScript = function(self, name) return st(self).scripts[name] end
  Common.HasScript = function(self, name)
    local s = st(self)
    return (s.kind == "frame" and W.FRAME_SCRIPTS[name] or W.REGION_SCRIPTS[name]) and true or false
  end
  Common.HookScript = function(self, name, fn)
    local s = st(self)
    s.hooks[name] = s.hooks[name] or {}
    table.insert(s.hooks[name], fn)
    if name == "OnUpdate" then W.onUpdate[self] = true end
  end
  Common.ClearScripts = function(self) local s = st(self); s.scripts, s.hooks = {}, {}; W.onUpdate[self] = nil end
  Common.EnableMouse = function(self, on) st(self).mouse = raw(on) and true or false end
  Common.IsMouseEnabled = function(self) return st(self).mouse == true end
  Common.EnableMouseWheel = function(self, on) st(self).mouseWheel = on end
  Common.EnableMouseMotion = function(self, on) st(self).mouseMotion = on end
  Common.SetMouseClickEnabled = function(self, on) st(self).mouseClick = on end
  Common.SetMouseMotionEnabled = function(self, on) st(self).mouseMotion = on end
  Common.IsMouseOver = function() return false end
  Common.IsMouseMotionFocus = function() return false end
  Common.IsProtected = function(self) local p = W.isProtected(self); return p, st(self).secure == true end
  Common.CanChangeProtectedState = function(self) return not (h.world.inCombat and W.isProtected(self)) end
  Common.IsAnchoringSecret = function(self) return W.anchoringSecret(self) end
  Common.IsAnchoringRestricted = function() return false end
  Common.IsRectValid = function(self) return W.rect(self) ~= nil end

  -- anchors
  Common.SetPoint = function(self, point, a, b, c, d)
    local s = st(self)
    local rel, relPoint, x, y
    if type(a) == "number" or a == nil and b == nil then
      rel, relPoint, x, y = s.parent, point, a or 0, b or 0
    else
      rel, relPoint, x, y = a, b, c or 0, d or 0
      if type(rel) == "string" then rel = env[rel] end
      if type(relPoint) == "number" then relPoint, x, y = point, b, c end
      relPoint = relPoint or point
    end
    if rel == self then error("SetPoint: Cannot anchor to itself", 3) end
    if rel ~= nil and not W.state[rel] then error("SetPoint: relativeTo is not a region", 3) end
    for i = #s.points, 1, -1 do if s.points[i].point == point:upper() then table.remove(s.points, i) end end
    s.points[#s.points + 1] = { point = point:upper(), rel = rel, relPoint = relPoint:upper(), x = x or 0, y = y or 0 }
    if rel then W.state[rel].dependents[self] = true end
  end
  Common.ClearAllPoints = function(self)
    local s = st(self)
    for _, p in ipairs(s.points) do if p.rel and W.state[p.rel] then W.state[p.rel].dependents[self] = nil end end
    s.points = {}
  end
  Common.ClearPoint = function(self, point)
    local s = st(self)
    for i = #s.points, 1, -1 do if s.points[i].point == point:upper() then table.remove(s.points, i) end end
  end
  Common.SetAllPoints = function(self, rel)
    rel = rel or st(self).parent
    Common.SetPoint(self, "TOPLEFT", rel, "TOPLEFT", 0, 0)
    Common.SetPoint(self, "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
  end
  Common.GetNumPoints = function(self) return #st(self).points end
  Common.GetPoint = function(self, i)
    local p = st(self).points[i or 1]
    if p then return p.point, p.rel, p.relPoint, p.x, p.y end
  end
  Common.GetPointByName = function(self, name)
    for _, p in ipairs(st(self).points) do if p.point == name:upper() then return p.point, p.rel, p.relPoint, p.x, p.y end end
  end
  Common.AdjustPointsOffset = function(self, dx, dy)
    for _, p in ipairs(st(self).points) do p.x, p.y = p.x + dx, p.y + dy end
  end
  -- Explicit size changes fire OnSizeChanged, as in the game. (Sizes that
  -- follow from anchors don't; the harness doesn't track those.)
  local function resized(self, w, hgt)
    local s = st(self)
    if s.width == w and s.height == hgt then return end
    s.width, s.height = w, hgt
    if s.kind == "frame" then W.callScript(self, "OnSizeChanged", w or 0, hgt or 0) end
  end
  Common.SetSize = function(self, w, hgt) resized(self, w, hgt or w) end
  Common.SetWidth = function(self, w) resized(self, w, st(self).height) end
  Common.SetHeight = function(self, hgt) resized(self, st(self).width, hgt) end
  Common.GetWidth = function(self)
    local r = W.rect(self)
    if r then return r[3] end
    local s = st(self)
    if s.type == "FontString" and not s.width then return W.stringWidth(self) end
    return s.width or 0
  end
  Common.GetHeight = function(self)
    local r = W.rect(self)
    return r and r[4] or st(self).height or 0
  end
  Common.GetSize = function(self) return Common.GetWidth(self), Common.GetHeight(self) end
  Common.GetRect = function(self) local r = W.rect(self); if r then return r[1], r[2], r[3], r[4] end end
  Common.GetScaledRect = Common.GetRect
  Common.GetLeft = function(self) local r = W.rect(self); return r and r[1] end
  Common.GetBottom = function(self) local r = W.rect(self); return r and r[2] end
  Common.GetRight = function(self) local r = W.rect(self); return r and r[1] + r[3] end
  Common.GetTop = function(self) local r = W.rect(self); return r and r[2] + r[4] end
  Common.GetCenter = function(self) local r = W.rect(self); if r then return r[1] + r[3] / 2, r[2] + r[4] / 2 end end

  -- alpha/scale/color shared by regions and frames
  Common.SetAlpha = function(self, a) st(self).alpha = raw(a) end
  Common.GetAlpha = function(self) return st(self).alpha end
  Common.SetAlphaFromBoolean = function(self, value, ifTrue, ifFalse)
    local s = st(self)
    local v = raw(value)
    s.alpha = v and (ifTrue or 1) or (ifFalse or 0)
    if s.alpha > 1 then s.alpha = s.alpha / 255 end
    s.alphaFromBoolean = { value = v, ifTrue = ifTrue, ifFalse = ifFalse, secret = Secret.is(value) }
  end
  Common.GetEffectiveAlpha = function(self)
    local a, s = 1, st(self)
    while s do a = a * (raw(s.alpha) or 1); s = s.parent and W.state[s.parent] end
    return a
  end
  Common.SetScale = function(self, sc) st(self).scale = sc end
  Common.GetScale = function(self) return st(self).scale end
  Common.GetEffectiveScale = function(self)
    local sc, s = 1, st(self)
    while s do sc = sc * (s.scale or 1); s = s.parent and W.state[s.parent] end
    return sc
  end
  Common.CreateAnimationGroup = function(self, name, inherits)
    local obj, s = W.newObject("AnimationGroup", "anim", name, self)
    s.anims, s.playing, s.looping = {}, false, "NONE"
    s.target = self
    W.animGroups[#W.animGroups + 1] = obj
    if inherits then W.applyTemplates(obj, inherits, {}) end
    return obj
  end
  Common.GetAnimationGroups = function(self)
    local r = {}
    for _, g in ipairs(W.animGroups) do if W.state[g].parent == self then r[#r + 1] = g end end
    return unpack(r)
  end
  Common.StopAnimating = function(self)
    for _, g in ipairs(W.animGroups) do if W.state[g].parent == self then W.state[g].playing = false end end
  end

  ---------------------------------------------------------------------------
  -- Regions (Texture, FontString)
  ---------------------------------------------------------------------------
  impl.Region = {
    SetVertexColor = function(self, r, g, b, a) st(self).vertexColor = { raw(r), raw(g), raw(b), raw(a) or 1 } end,
    GetVertexColor = function(self) local c = st(self).vertexColor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end,
    SetVertexColorFromBoolean = function(self, value, ifTrue, ifFalse)
      local c = raw(value) and ifTrue or ifFalse
      st(self).vertexColor = c and { c.r, c.g, c.b, c.a or 1 } or nil
      st(self).vertexColorFromBoolean = { value = raw(value), secret = Secret.is(value) }
    end,
    SetDrawLayer = function(self, layer, sub) local s = st(self); s.layer, s.sublevel = layer, sub or 0 end,
    GetDrawLayer = function(self) local s = st(self); return s.layer, s.sublevel end,
    SetIgnoreParentAlpha = function(self, on) st(self).ignoreParentAlpha = on end,
    SetIgnoreParentScale = function(self, on) st(self).ignoreParentScale = on end,
    IsObjectLoaded = function() return true end,
  }

  local function texState(self, key, v) st(self)[key] = v end
  impl.Texture = {
    SetTexture = function(self, tex, ...)
      if Secret.is(tex) and type(raw(tex)) == "string" then
        error("Cannot set texture to a secret string value.", 3)
      end
      -- Like the game, an atlas name isn't a file, so nothing draws.
      if type(raw(tex)) == "string" and h.atlasNames and h.atlasNames[raw(tex)] then
        return false
      end
      local s = st(self)
      s.texture, s.atlas, s.color = raw(tex), nil, nil
      s.textureSecret = Secret.is(tex) or nil
      return true
    end,
    GetTexture = function(self) local s = st(self); return s.texture or s.atlas end,
    GetTextureFileID = function(self) local t = st(self).texture; return type(t) == "number" and t or nil end,
    GetTextureFilePath = function(self) local t = st(self).texture; return type(t) == "string" and t or nil end,
    SetAtlas = function(self, atlas, useSize)
      local s = st(self)
      s.atlas, s.texture = raw(atlas), nil
      if h.validateAtlas and not h.validateAtlas(raw(atlas)) then h:warn("unknown atlas " .. tostring(raw(atlas))) end
      local _ = useSize
    end,
    GetAtlas = function(self) return st(self).atlas end,
    SetColorTexture = function(self, r, g, b, a) local s = st(self); s.color = { raw(r), raw(g), raw(b), raw(a) or 1 }; s.texture = nil end,
    SetTexCoord = function(self, ...) texState(self, "texCoord", { ... }) end,
    GetTexCoord = function(self) local c = st(self).texCoord or { 0, 1, 0, 1 }; return unpack(c) end,
    SetSpriteSheetCell = function(self, cell, rows, cols, w, hgt)
      st(self).spriteCell = { cell = raw(cell), rows = rows, cols = cols, secret = Secret.is(cell) }
      local _ = w or hgt
    end,
    SetDesaturated = function(self, on) st(self).desaturated = raw(on) end,
    IsDesaturated = function(self) return st(self).desaturated and true or false end,
    SetDesaturation = function(self, v) st(self).desaturation = raw(v) end,
    GetDesaturation = function(self) return st(self).desaturation or 0 end,
    SetBlendMode = function(self, mode) st(self).blendMode = mode end,
    GetBlendMode = function(self) return st(self).blendMode or "BLEND" end,
    SetTextureSliceMargins = function(self, l, t, r, b) st(self).sliceMargins = { l, t, r, b } end,
    SetTextureSliceMode = function(self, m) st(self).sliceMode = m end,
    SetRotation = function(self, r) st(self).rotation = raw(r) end,
    GetRotation = function(self) return st(self).rotation or 0 end,
    SetHorizTile = function(self, on) st(self).horizTile = on end,
    SetVertTile = function(self, on) st(self).vertTile = on end,
    SetGradient = function(self, orient, c1, c2) st(self).gradient = { orient, c1, c2 } end,
    SetSnapToPixelGrid = function() end,
    SetTexelSnappingBias = function() end,
    AddMaskTexture = function(self, m) local s = st(self); s.masks = s.masks or {}; table.insert(s.masks, m) end,
    RemoveMaskTexture = function() end,
    SetMask = function(self, m) st(self).mask = m end,
  }

  impl.FontString = {
    SetText = function(self, text)
      local s = st(self)
      s.text = text ~= nil and raw(text) or nil
      if type(s.text) == "number" then s.text = tostring(s.text) end
      s.textSecret = Secret.is(text) or nil
    end,
    GetText = function(self) return st(self).text end,
    SetFormattedText = function(self, fmt, ...)
      local s = st(self)
      local out = Secret.format(fmt, ...)
      s.text = raw(out)
      s.textSecret = Secret.is(out) or nil
      if s.textSecret then s.aspects.Text = true end
      s.formatted = { fmt = raw(fmt), n = select("#", ...), ... }
    end,
    SetTextToFit = function(self, text) impl.FontString.SetText(self, text) end,
    ClearText = function(self) st(self).text = nil end,
    SetTextColor = function(self, r, g, b, a) st(self).textColor = { raw(r), raw(g), raw(b), raw(a) or 1 } end,
    GetTextColor = function(self) local c = st(self).textColor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end,
    SetFont = function(self, path, size, flags)
      local s = st(self)
      if type(size) ~= "number" or size <= 0 then error("SetFont: invalid font height", 3) end
      s.font, s.fontSize, s.fontFlags = path, size, flags
      return true
    end,
    GetFont = function(self) local s = st(self); return s.font, s.fontSize, s.fontFlags end,
    SetFontObject = function(self, fo)
      if type(fo) == "string" then fo = env[fo] end
      local s = st(self)
      s.fontObject = fo
      if type(fo) == "table" and fo.GetFont then s.font, s.fontSize, s.fontFlags = fo:GetFont() end
    end,
    GetFontObject = function(self) return st(self).fontObject end,
    SetJustifyH = function(self, j) st(self).justifyH = j end,
    GetJustifyH = function(self) return st(self).justifyH or "CENTER" end,
    SetJustifyV = function(self, j) st(self).justifyV = j end,
    GetJustifyV = function(self) return st(self).justifyV or "MIDDLE" end,
    SetWordWrap = function(self, on) st(self).wordWrap = on end,
    CanWordWrap = function(self) return st(self).wordWrap ~= false end,
    SetNonSpaceWrap = function(self, on) st(self).nonSpaceWrap = on end,
    SetMaxLines = function(self, n) st(self).maxLines = n end,
    GetMaxLines = function(self) return st(self).maxLines or 0 end,
    GetStringWidth = function(self) return W.stringWidth(self) end,
    GetUnboundedStringWidth = function(self) return W.stringWidth(self) end,
    GetStringHeight = function(self) return st(self).fontSize or 12 end,
    GetNumLines = function(self) return st(self).text and 1 or 0 end,
    IsTruncated = function(self)
      local s = st(self)
      return s.width ~= nil and s.width > 0 and W.stringWidth(self) > s.width
    end,
    SetShadowColor = function(self, ...) st(self).shadowColor = { ... } end,
    SetShadowOffset = function(self, x, y) st(self).shadowOffset = { x, y } end,
    SetSpacing = function(self, v) st(self).spacing = v end,
    SetTextHeight = function(self, v) st(self).fontSize = v end,
    SetTextScale = function(self, v) st(self).textScale = v end,
    SetIndentedWordWrap = function(self, on) st(self).indentedWordWrap = on end,
  }

  ---------------------------------------------------------------------------
  -- Frames
  ---------------------------------------------------------------------------
  impl.Frame = {
    CreateTexture = regionCreate("Texture", "region"),
    CreateMaskTexture = regionCreate("MaskTexture", "region"),
    CreateLine = regionCreate("Line", "region"),
    CreateFontString = regionCreate("FontString", "region"),
    GetChildren = function(self) return unpack(st(self).children) end,
    GetNumChildren = function(self) return #st(self).children end,
    GetRegions = function(self) return unpack(st(self).regions) end,
    GetNumRegions = function(self) return #st(self).regions end,
    SetFrameLevel = function(self, l) st(self).level = l end,
    GetFrameLevel = function(self) return st(self).level end,
    SetFrameStrata = function(self, s) st(self).strata = s end,
    GetFrameStrata = function(self) return st(self).strata end,
    SetFixedFrameStrata = function(self, on) st(self).fixedStrata = on end,
    SetFixedFrameLevel = function(self, on) st(self).fixedLevel = on end,
    SetToplevel = function(self, on) st(self).toplevel = on end,
    Raise = function() end,
    Lower = function() end,
    SetID = function(self, id) st(self).id = raw(id) end,
    GetID = function(self) return st(self).id or 0 end,
    SetMovable = function(self, on) st(self).movable = on end,
    IsMovable = function(self) return st(self).movable == true end,
    SetResizable = function(self, on) st(self).resizable = on end,
    SetClampedToScreen = function(self, on) st(self).clamped = on end,
    IsClampedToScreen = function(self) return st(self).clamped == true end,
    SetClampRectInsets = function() end,
    SetHitRectInsets = function(self, ...) st(self).hitRectInsets = { ... } end,
    SetDontSavePosition = function(self, on) st(self).dontSavePosition = on end,
    SetUserPlaced = function(self, on) st(self).userPlaced = on end,
    IsUserPlaced = function(self) return st(self).userPlaced == true end,
    StartMoving = function(self) st(self).moving = true end,
    StopMovingOrSizing = function(self) st(self).moving = false end,
    RegisterForDrag = function(self, ...) st(self).dragButtons = { ... } end,
    EnableKeyboard = function(self, on) st(self).keyboard = on end,
    SetPropagateKeyboardInput = function(self, on) st(self).propagateKeyboard = on end,
    SetClipsChildren = function(self, on) st(self).clipsChildren = on end,
    DoesClipChildren = function(self) return st(self).clipsChildren == true end,
    SetFlattensRenderLayers = function() end,
    SetIgnoreParentAlpha = function(self, on) st(self).ignoreParentAlpha = on end,
    SetIgnoreParentScale = function(self, on) st(self).ignoreParentScale = on end,
    SetUsingParentLevel = function() end,
    SetOnUpdateMode = function(self, mode) st(self).onUpdateMode = mode end,
    SetRolesets = function(self, rolesets)
      local s = st(self)
      s.rolesets = rolesets
      local blocked = false
      local list = type(rolesets) == "table" and rolesets or { rolesets }
      for _, r in ipairs(list) do if r == "alwaysBlocked" then blocked = true end end
      W.withVisibility(self, function() s.rolesetFiltered = blocked end)
    end,
    AddRoleset = function(self, r)
      local s = st(self)
      s.rolesets = s.rolesets or {}
      if type(s.rolesets) == "string" then s.rolesets = { s.rolesets } end
      table.insert(s.rolesets, r)
      if r == "alwaysBlocked" then W.withVisibility(self, function() s.rolesetFiltered = true end) end
    end,
    RemoveRoleset = function(self) local s = st(self); W.withVisibility(self, function() s.rolesetFiltered = false end) end,
    IsRolesetFiltered = function(self) return st(self).rolesetFiltered == true end,
    -- events
    RegisterEvent = function(self, event)
      if W.checkEvent(event, "RegisterEvent") then W.registerEvent(self, event) end
      return true
    end,
    RegisterUnitEvent = function(self, event, ...)
      if not W.checkEvent(event, "RegisterUnitEvent") then return false end
      local units = {}
      for i = 1, select("#", ...) do local u = select(i, ...); if u then units[#units + 1] = u end end
      W.registerEvent(self, event, #units > 0 and units or nil)
      return true
    end,
    UnregisterEvent = function(self, event)
      local e = h.tags.events[event]
      if e and e.HasRestrictions then h:forbidden("UnregisterEvent(" .. event .. ")"); return end
      W.unregisterEvent(self, event)
    end,
    UnregisterAllEvents = function(self)
      for event in pairs(st(self).events) do W.unregisterEvent(self, event) end
    end,
    IsEventRegistered = function(self, event)
      local r = st(self).events[event]
      if r == nil then return false end
      if type(r) == "table" then return true, unpack(r) end
      return true
    end,
    -- attributes
    SetAttribute = function(self, name, value)
      local s = st(self)
      if type(name) ~= "string" then error("SetAttribute: name must be a string", 3) end
      local key = name:lower()
      s.attributes[key] = value
      if s.onAttributeInternal then s.onAttributeInternal(self, key, value) end
      if s.attributes._ignore ~= "attributeChanges" then W.callScript(self, "OnAttributeChanged", key, value) end
    end,
    SetAttributeNoHandler = function(self, name, value) st(self).attributes[name:lower()] = value end,
    GetAttribute = function(self, name)
      local attrs = st(self).attributes
      if type(name) ~= "string" then return nil end
      local key = name:lower()
      local v = attrs[key]
      if v ~= nil then return v end
      -- modifier/button wildcards (*type1, type*)
      local base = key:gsub("^%*", "")
      return attrs["*" .. base] or attrs[base:gsub("%d+$", "") .. "*"]
    end,
    ClearAttribute = function(self, name) st(self).attributes[name:lower()] = nil end,
    ClearAttributes = function(self) st(self).attributes = {} end,
    GetEffectiveAlpha = Common.GetEffectiveAlpha,
    SetHyperlinksEnabled = function() end,
    SetResizeBounds = function() end,
    SetDrawLayerEnabled = function() end,
  }

  impl.Button = {
    RegisterForClicks = function(self, ...) st(self).clicks = { ... } end,
    RegisterForMouse = function(self, ...) st(self).mouseButtons = { ... } end,
    Click = function(self, button, down)
      button = button or "LeftButton"
      W.callScript(self, "PreClick", button, down)
      if st(self).secureClick then st(self).secureClick(self, button, down) end
      W.callScript(self, "OnClick", button, down)
      W.callScript(self, "PostClick", button, down)
    end,
    SetText = function(self, text) st(self).text = text end,
    GetText = function(self) return st(self).text end,
    SetFormattedText = function(self, fmt, ...) st(self).text = string.format(fmt, ...) end,
    Enable = function(self) st(self).disabled = false end,
    Disable = function(self) st(self).disabled = true end,
    SetEnabled = function(self, on) st(self).disabled = not on end,
    IsEnabled = function(self) return not st(self).disabled end,
    SetNormalTexture = function(self, t) st(self).normalTexture = t end,
    GetNormalTexture = function(self) return st(self).normalTextureObj end,
    SetPushedTexture = function(self, t) st(self).pushedTexture = t end,
    SetHighlightTexture = function(self, t, mode) st(self).highlightTexture = t; st(self).highlightMode = mode end,
    GetHighlightTexture = function(self) return st(self).highlightTextureObj end,
    SetDisabledTexture = function(self, t) st(self).disabledTexture = t end,
    SetFontString = function(self, fs) st(self).fontString = fs end,
    GetFontString = function(self) return st(self).fontString end,
    SetNormalFontObject = function() end,
    SetHighlightFontObject = function() end,
    SetDisabledFontObject = function() end,
    SetButtonState = function(self, s) st(self).buttonState = s end,
    GetButtonState = function(self) return st(self).buttonState or "NORMAL" end,
    SetMotionScriptsWhileDisabled = function() end,
  }
  impl.CheckButton = {
    SetChecked = function(self, on) st(self).checked = on and true or false end,
    GetChecked = function(self) return st(self).checked == true end,
  }

  impl.StatusBar = {
    SetMinMaxValues = function(self, min, max, interp)
      local s = st(self)
      s.min, s.max = raw(min), raw(max)
      s.minMaxSecret = Secret.anySecret(min, max) or nil
      s.minMaxInterp = interp
      if s.value then
        if s.value < s.min then s.value = s.min elseif s.value > s.max then s.value = s.max end
      end
      W.callScript(self, "OnMinMaxChanged", min, max)
    end,
    GetMinMaxValues = function(self) local s = st(self); return s.min or 0, s.max or 1 end,
    SetValue = function(self, v, interp)
      local s = st(self)
      local rv = raw(v)
      if type(rv) ~= "number" then error("StatusBar:SetValue: value must be a number", 3) end
      local lo, hi = s.min or 0, s.max or 1
      if rv < lo then rv = lo elseif rv > hi then rv = hi end
      s.value, s.valueSecret, s.interpolation = rv, Secret.is(v) or nil, interp
      s.timerDuration = nil
      W.callScript(self, "OnValueChanged", v)
    end,
    GetValue = function(self) return st(self).value or 0 end,
    GetInterpolatedValue = function(self) return st(self).value or 0 end,
    SetToTargetValue = function(self) st(self).snapped = (st(self).snapped or 0) + 1 end,
    IsInterpolating = function() return false end,
    SetStatusBarTexture = function(self, tex)
      local s = st(self)
      if type(tex) == "table" and W.state[tex] then s.barTexture = tex; return true end
      if not s.barTexture then s.barTexture = impl.Frame.CreateTexture(self, nil, "ARTWORK") end
      W.state[s.barTexture].texture = raw(tex)
      return true
    end,
    GetStatusBarTexture = function(self)
      local s = st(self)
      if not s.barTexture then s.barTexture = impl.Frame.CreateTexture(self, nil, "ARTWORK") end
      return s.barTexture
    end,
    SetStatusBarColor = function(self, r, g, b, a) st(self).barColor = { raw(r), raw(g), raw(b), raw(a) or 1 } end,
    GetStatusBarColor = function(self) local c = st(self).barColor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end,
    SetStatusBarDesaturated = function(self, on) st(self).barDesaturated = raw(on) end,
    SetFillStyle = function(self, style) st(self).fillStyle = style end,
    GetFillStyle = function(self) return st(self).fillStyle or 0 end,
    SetReverseFill = function(self, on) st(self).reverseFill = on end,
    GetReverseFill = function(self) return st(self).reverseFill == true end,
    SetOrientation = function(self, o) st(self).orientation = o end,
    GetOrientation = function(self) return st(self).orientation or "HORIZONTAL" end,
    SetRotatesTexture = function(self, on) st(self).rotatesTexture = on end,
    SetTimerDuration = function(self, dur, interp, direction)
      if type(dur) ~= "table" or not dur.__isDuration then error("SetTimerDuration: expected a duration object", 3) end
      st(self).timerDuration = { duration = dur, interpolation = interp, direction = direction }
    end,
    ClearTimerDuration = function(self) st(self).timerDuration = nil end,
  }

  impl.Slider = {
    SetMinMaxValues = function(self, a, b) local s = st(self); s.min, s.max = a, b end,
    GetMinMaxValues = function(self) local s = st(self); return s.min or 0, s.max or 1 end,
    SetValue = function(self, v) st(self).value = v; W.callScript(self, "OnValueChanged", v, false) end,
    GetValue = function(self) return st(self).value or 0 end,
    SetValueStep = function(self, v) st(self).step = v end,
    SetObeyStepOnDrag = function() end,
    SetOrientation = function(self, o) st(self).orientation = o end,
  }

  impl.Cooldown = {
    SetCooldown = function(self, start, duration, modRate)
      local s = st(self)
      s.cooldown = { start = start, duration = duration, modRate = modRate }
      local _ = modRate
    end,
    SetCooldownDuration = function(self, duration) st(self).cooldown = { start = h.clock, duration = duration } end,
    SetCooldownFromExpirationTime = function(self, exp, dur) st(self).cooldown = { start = exp - dur, duration = dur } end,
    SetCooldownFromDurationObject = function(self, dur, clearIfZero)
      if type(dur) ~= "table" or not dur.__isDuration then error("SetCooldownFromDurationObject: expected a duration object", 3) end
      st(self).cooldown = { durationObject = dur, clearIfZero = clearIfZero }
    end,
    GetCooldownTimes = function(self)
      local c = st(self).cooldown
      if c and c.start then return c.start * 1000, c.duration * 1000 end
      return 0, 0
    end,
    GetCooldownDuration = function(self) local c = st(self).cooldown; return c and c.duration and c.duration * 1000 or 0 end,
    Clear = function(self) st(self).cooldown = nil end,
    SetDrawSwipe = function(self, on) st(self).drawSwipe = raw(on) end,
    SetDrawEdge = function(self, on) st(self).drawEdge = raw(on) end,
    SetDrawBling = function(self, on) st(self).drawBling = raw(on) end,
    SetReverse = function(self, on) st(self).reverse = on end,
    SetHideCountdownNumbers = function(self, on) st(self).hideCountdown = on end,
    SetSwipeColor = function(self, ...) st(self).swipeColor = { ... } end,
    SetSwipeTexture = function(self, t) st(self).swipeTexture = t end,
    SetEdgeTexture = function(self, t) st(self).edgeTexture = t end,
    SetUseCircularEdge = function(self, on) st(self).circularEdge = on end,
    Pause = function(self) st(self).paused = true end,
    Resume = function(self) st(self).paused = false end,
    IsPaused = function(self) return st(self).paused == true end,
  }

  impl.EditBox = {
    SetText = function(self, t) st(self).text = t; W.callScript(self, "OnTextChanged", false) end,
    GetText = function(self) return st(self).text or "" end,
    Insert = function(self, t) local s = st(self); s.text = (s.text or "") .. t end,
    SetAutoFocus = function(self, on) st(self).autoFocus = on end,
    SetFocus = function(self) st(self).focus = true end,
    ClearFocus = function(self) st(self).focus = false end,
    HasFocus = function(self) return st(self).focus == true end,
    HighlightText = function() end,
    SetMaxLetters = function(self, n) st(self).maxLetters = n end,
    SetNumeric = function(self, on) st(self).numeric = on end,
    SetMultiLine = function(self, on) st(self).multiLine = on end,
    SetFontObject = function(self, fo) st(self).fontObject = fo end,
    SetFont = function(self, ...) st(self).font = { ... }; return true end,
    SetTextInsets = function() end,
    SetCursorPosition = function() end,
    SetJustifyH = function() end,
  }

  impl.GameTooltip = {
    SetOwner = function(self, owner, anchor) local s = st(self); s.owner, s.anchor, s.lines = owner, anchor, {} end,
    GetOwner = function(self) return st(self).owner end,
    IsOwned = function(self, f) return st(self).owner == f end,
    ClearLines = function(self) st(self).lines = {} end,
    AddLine = function(self, text, r, g, b, wrap)
      local s = st(self)
      s.lines = s.lines or {}
      s.lines[#s.lines + 1] = { text = raw(text), secret = Secret.is(text) or nil, r = r, g = g, b = b, wrap = wrap }
    end,
    AddDoubleLine = function(self, l, r)
      local s = st(self)
      s.lines = s.lines or {}
      s.lines[#s.lines + 1] = { text = raw(l), right = raw(r) }
    end,
    SetText = function(self, text) st(self).lines = { { text = raw(text), secret = Secret.is(text) or nil } } end,
    AppendText = function(self, text) local s = st(self); s.lines = s.lines or {}; s.lines[#s.lines + 1] = { text = raw(text) } end,
    NumLines = function(self) return #(st(self).lines or {}) end,
    SetUnit = function(self, unit) st(self).unit = unit end,
    SetSpellByID = function(self, id) st(self).spellID = id end,
    SetUnitAura = function() end,
    SetUnitBuffByAuraInstanceID = function() end,
    SetUnitDebuffByAuraInstanceID = function() end,
    SetMinimumWidth = function() end,
    SetPadding = function() end,
    FadeOut = function(self) setShown(self, false) end,
  }

  impl.Model = {
    SetUnit = function(self, unit)
      if h.world:identitySecret(unit) then error("PlayerModel:SetUnit: unit identity is secret", 3) end
      st(self).unit = unit
      return true
    end,
    ClearModel = function(self) st(self).unit = nil end,
    SetPortraitZoom = function(self, z) st(self).portraitZoom = z end,
    SetCamDistanceScale = function(self, v) st(self).camDistance = v end,
    SetPosition = function(self, ...) st(self).position = { ... } end,
    SetRotation = function(self, r) st(self).modelRotation = r end,
    SetModelScale = function(self, s) st(self).modelScale = s end,
    RefreshUnit = function() end,
    RefreshCamera = function() end,
    SetDisplayInfo = function(self, id) st(self).displayInfo = id end,
    SetKeepModelOnHide = function() end,
  }

  ---------------------------------------------------------------------------
  -- Animations (driven by the fake clock in harness:advance)
  ---------------------------------------------------------------------------
  impl.AnimationGroup = {
    Play = function(self, reverse)
      local s = st(self)
      s.playing, s.elapsed, s.reverse, s.paused = true, 0, reverse, false
      s.plays = (s.plays or 0) + 1
      W.callScript(self, "OnPlay")
    end,
    Restart = function(self) impl.AnimationGroup.Play(self) end,
    Stop = function(self)
      local s = st(self)
      if s.playing then s.playing = false; W.callScript(self, "OnStop", false) end
    end,
    Finish = function(self) local s = st(self); if s.playing then s.elapsed = math.huge end end,
    Pause = function(self) st(self).paused = true end,
    IsPlaying = function(self) local s = st(self); return s.playing and not s.paused or false end,
    IsPaused = function(self) return st(self).paused == true end,
    IsDone = function(self) return not st(self).playing end,
    SetLooping = function(self, l) st(self).looping = l end,
    GetLooping = function(self) return st(self).looping or "NONE" end,
    SetToFinalAlpha = function(self, on) st(self).toFinalAlpha = on end,
    GetDuration = function(self)
      local total, s = 0, st(self)
      local byOrder = {}
      for _, a in ipairs(s.anims) do
        local as = W.state[a]
        local o = as.order or 1
        local d = (as.duration or 0) + (as.startDelay or 0) + (as.endDelay or 0)
        byOrder[o] = math.max(byOrder[o] or 0, d)
      end
      for _, d in pairs(byOrder) do total = total + d end
      return total
    end,
    CreateAnimation = function(self, animType, name, inherits)
      animType = animType or "Animation"
      local ok = { Animation = 1, Alpha = 1, Scale = 1, Translation = 1, Rotation = 1, FlipBook = 1, VertexColor = 1,
        LineScale = 1, LineTranslation = 1, Path = 1, TextureCoordTranslation = 1 }
      if not ok[animType] then error("CreateAnimation: unknown animation type " .. tostring(animType), 3) end
      local cls = W.IMPL_CHAIN[animType] and animType or "Animation"
      local obj, s = W.newObject(cls, "anim", name, self)
      s.duration, s.order = 0, 1
      table.insert(st(self).anims, obj)
      if inherits then W.applyTemplates(obj, inherits, {}) end
      return obj
    end,
    GetAnimations = function(self) return unpack(st(self).anims) end,
    SetScript = function(self, name, fn)
      if not W.ANIM_SCRIPTS[name] then error(string.format('AnimationGroup doesn\'t have a "%s" script', tostring(name)), 3) end
      st(self).scripts[name] = fn
    end,
    GetScript = function(self, name) return st(self).scripts[name] end,
    HookScript = Common.HookScript,
  }
  impl.Animation = {
    SetDuration = function(self, d) st(self).duration = d end,
    GetDuration = function(self) return st(self).duration or 0 end,
    SetStartDelay = function(self, d) st(self).startDelay = d end,
    SetEndDelay = function(self, d) st(self).endDelay = d end,
    SetOrder = function(self, o) st(self).order = o end,
    GetOrder = function(self) return st(self).order or 1 end,
    SetSmoothing = function(self, s) st(self).smoothing = s end,
    SetChildKey = function(self, k) st(self).childKey = k end,
    SetTarget = function(self, t) st(self).target = t end,
    SetTargetKey = function(self, k) st(self).targetKey = k end,
    GetRegionParent = function(self) local g = st(self).parent; return g and W.state[g].parent end,
    Play = function(self) st(self).playing = true end,
    Stop = function(self) st(self).playing = false end,
    IsPlaying = function(self) return st(self).playing == true end,
    SetScript = function(self, name, fn) st(self).scripts[name] = fn end,
  }
  impl.Alpha = {
    SetFromAlpha = function(self, a) st(self).fromAlpha = a end,
    SetToAlpha = function(self, a) st(self).toAlpha = a end,
    GetFromAlpha = function(self) return st(self).fromAlpha or 0 end,
    GetToAlpha = function(self) return st(self).toAlpha or 0 end,
  }
  impl.Scale = {
    SetScaleFrom = function(self, x, y) st(self).scaleFrom = { x, y } end,
    SetScaleTo = function(self, x, y) st(self).scaleTo = { x, y } end,
    SetFromScale = function(self, x, y) st(self).scaleFrom = { x, y } end,
    SetToScale = function(self, x, y) st(self).scaleTo = { x, y } end,
    SetOrigin = function(self, p, x, y) st(self).origin = { p, x, y } end,
  }
  impl.Translation = { SetOffset = function(self, x, y) st(self).offset = { x, y } end }
  impl.Rotation = {
    SetDegrees = function(self, d) st(self).degrees = d end,
    SetRadians = function(self, r) st(self).degrees = math.deg(r) end,
    SetOrigin = function(self, p, x, y) st(self).origin = { p, x, y } end,
  }

  -- Advance playing animation groups by dt; fire OnFinished/OnLoop.
  function W.tickAnimations(dt)
    for _, g in ipairs(W.animGroups) do
      local s = W.state[g]
      if s and s.playing and not s.paused then
        s.elapsed = (s.elapsed or 0) + dt
        local dur = impl.AnimationGroup.GetDuration(g)
        if s.elapsed >= dur then
          if s.looping == "REPEAT" or s.looping == "BOUNCE" then
            s.elapsed = 0
            W.callScript(g, "OnLoop", "FORWARD")
          else
            s.playing = false
            W.callScript(g, "OnFinished", false)
          end
        end
      end
    end
  end
end

return T
