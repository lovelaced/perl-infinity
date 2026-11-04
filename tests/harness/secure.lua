-- tests/harness/secure.lua
-- Secure templates and drivers (a simplified SecureGroupHeaders.lua / SecureStateDriver.lua):
--   * Secure* templates mark frames secure (protected): addon SetAttribute/SetPoint/
--     Show/Hide on them in combat are blocked and logged by widgets.lua.
--   * SecureGroupHeaderTemplate / pet headers spawn children from the `template`
--     attribute against the world roster and assign `unit` attributes.
--   * RegisterUnitWatch, RegisterStateDriver, RegisterAttributeDriver evaluate a
--     macro-condition subset after every event and clock step.
-- Restricted snippets (initialConfigFunction, _onstate-*) are recorded, not run.

local S = {}

function S.install(h)
  local env = h.env
  local W = h.widgets
  local w = h.world
  h.secureSnippets = {}
  local drivers = {}   -- frame -> { [key] = { kind, values, last } }
  local watched = {}   -- frame -> asState

  -- What the game's SecureButton_GetUnit reads: a button can take its unit from
  -- its parent ("useparent-unit") and add a suffix, so party1 + "pet" = partypet1.
  local function watchedUnit(frame)
    local attributes = W.st(frame).attributes
    local unit = attributes.unit
    if not unit and attributes["useparent-unit"] then
      unit = W.st(frame:GetParent()).attributes.unit
    end
    local suffix = attributes.unitsuffix
    if unit and suffix then
      unit = (unit .. suffix):gsub("^([^%d]+)(%d+)[pP][eE][tT]", "%1pet%2"):gsub("^[pP][lL][aA][yY][eE][rR][pP][eE][tT]", "pet")
    end
    return unit
  end

  -- Secure code paths change state without protection checks.
  local function secureSet(obj, name, value)
    local st = W.st(obj)
    local key = name:lower()
    st.attributes[key] = value
    if st.onAttributeInternal then st.onAttributeInternal(obj, key, value) end
    if st.attributes._ignore ~= "attributeChanges" then W.callScript(obj, "OnAttributeChanged", key, value) end
  end
  local function secureShow(obj, on)
    local st = W.st(obj)
    if st.shown == on then return end
    W.withVisibility(obj, function() st.shown = on end)
  end
  S.secureSet, S.secureShow = secureSet, secureShow

  ---------------------------------------------------------------------------
  -- Macro conditions: "[combat] a; [@party1,exists] b; c"
  ---------------------------------------------------------------------------
  local function condHolds(cond, target)
    local neg = false
    local name, arg = cond:match("^%s*([%w@]+)%s*:?%s*(.-)%s*$")
    if not name then return true end
    if name:sub(1, 2) == "no" and name ~= "nodead" and name ~= "noexists" then neg = true; name = name:sub(3) end
    if name == "nodead" then neg = true; name = "dead" end
    if name == "noexists" then neg = true; name = "exists" end
    local r
    if name == "combat" then r = w.inCombat
    elseif name == "group" then
      if arg == "raid" then r = w.group == "raid" elseif arg == "party" then r = w.group ~= nil else r = w.group ~= nil end
    elseif name == "exists" then r = w:get(target or "target") ~= nil
    elseif name == "dead" then local u = w:get(target or "target"); r = u ~= nil and u.dead == true
    elseif name == "help" then r = env.UnitCanAssist("player", target or "target")
    elseif name == "harm" then r = env.UnitCanAttack("player", target or "target")
    elseif name == "mod" or name == "modifier" then
      if arg == "" then r = h.modifiers.shift or h.modifiers.ctrl or h.modifiers.alt else r = h.modifiers[arg] == true end
    elseif name == "pet" then r = w:get("pet") ~= nil
    elseif name == "form" or name == "stance" then
      r = (arg == "" and (w.shapeshiftForm or 0) > 0) or tostring(w.shapeshiftForm or 0) == arg
    elseif name == "petbattle" or name == "vehicleui" or name == "overridebar" or name == "possessbar"
        or name == "bonusbar" or name == "flying" or name == "mounted" or name == "channeling" then r = false
    elseif name == "indoors" then r = false
    elseif name == "outdoors" then r = true
    else
      h:warn("macro condition not modelled: " .. cond)
      r = false
    end
    if neg then return not r end
    return r
  end

  local function clauseHolds(conds)
    local target
    local list = {}
    for c in conds:gmatch("[^,]+") do
      local t = c:match("^%s*@(%S+)%s*$") or c:match("^%s*target%s*=%s*(%S+)%s*$")
      if t then target = t else list[#list + 1] = c end
    end
    for _, c in ipairs(list) do if not condHolds(c, target) then return false end end
    return true
  end

  local function parseOptions(options)
    for clause in (options .. ";"):gmatch("([^;]*);") do
      local value = clause
      local holds = true
      local any = false
      for conds in clause:gmatch("%[(.-)%]") do
        any = true
        if clauseHolds(conds) then holds = true; break else holds = false end
      end
      if any then value = clause:gsub("%[.-%]", "") end
      value = value:match("^%s*(.-)%s*$")
      if holds then return value end
    end
    return nil
  end
  env.SecureCmdOptionParse = function(options) return parseOptions(options) end
  S.parseOptions = parseOptions

  ---------------------------------------------------------------------------
  -- Drivers (evaluated after every event/step, like Blizzard's 0.2 s OnUpdate)
  ---------------------------------------------------------------------------
  local function evaluate()
    for frame, list in pairs(drivers) do
      for key, d in pairs(list) do
        local v = parseOptions(d.values)
        if v ~= d.last then
          d.last = v
          if key == "visibility" or key == "state-visibility" then
            secureShow(frame, v == "show")
          elseif d.kind == "state" then
            secureSet(frame, "state-" .. key, v)
            if W.st(frame).attributes["_onstate-" .. key] then
              h.secureSnippets[#h.secureSnippets + 1] = { frame = frame, snippet = "_onstate-" .. key, value = v }
            end
          else
            secureSet(frame, key, v)
          end
        end
      end
    end
    for frame, asState in pairs(watched) do
      local unit = watchedUnit(frame)
      local exists = unit ~= nil and w:get(unit) ~= nil
      if asState then secureSet(frame, "state-unitexists", exists and true or false) else secureShow(frame, exists) end
    end
  end
  h.evaluateDrivers = evaluate
  local origFire = h.fire
  h.fire = function(self, ...)
    local n = origFire(self, ...)
    evaluate()
    return n
  end
  local origAdvance = h.advance
  h.advance = function(self, ...)
    origAdvance(self, ...)
    evaluate()
  end

  env.RegisterStateDriver = function(frame, state, values)
    drivers[frame] = drivers[frame] or {}
    drivers[frame][state] = { kind = "state", values = values }
    evaluate()
  end
  env.UnregisterStateDriver = function(frame, state) if drivers[frame] then drivers[frame][state] = nil end end
  env.RegisterAttributeDriver = function(frame, attribute, values)
    drivers[frame] = drivers[frame] or {}
    drivers[frame][attribute] = { kind = "attribute", values = values }
    evaluate()
  end
  env.UnregisterAttributeDriver = function(frame, attribute) if drivers[frame] then drivers[frame][attribute] = nil end end
  env.RegisterUnitWatch = function(frame, asState) watched[frame] = asState or false; evaluate() end
  env.UnregisterUnitWatch = function(frame) watched[frame] = nil end
  env.UnitWatchRegistered = function(frame) return watched[frame] ~= nil, watched[frame] end
  h.drivers, h.unitWatch = drivers, watched

  ---------------------------------------------------------------------------
  -- Secure templates
  ---------------------------------------------------------------------------
  local function secureTemplate(name, objType, extra)
    W.templates[name] = { name = name, type = objType, secure = true, apply = extra }
  end
  secureTemplate("SecureFrameTemplate", "Frame")
  secureTemplate("SecureActionButtonTemplate", "Button")
  secureTemplate("SecureUnitButtonTemplate", "Button", function(obj, st)
    st.secureClick = function(self, button)
      local attrs = W.st(self).attributes
      local t = attrs["*type" .. (button == "RightButton" and "2" or "1")] or attrs.type
      h.secureClicks = h.secureClicks or {}
      h.secureClicks[#h.secureClicks + 1] = { frame = self, button = button, action = t, unit = attrs.unit }
    end
  end)
  for _, n in ipairs({ "SecureHandlerBaseTemplate", "SecureHandlerStateTemplate", "SecureHandlerAttributeTemplate",
    "SecureHandlerShowHideTemplate", "SecureHandlerClickTemplate", "SecureHandlerEnterLeaveTemplate",
    "SecureHandlerDragTemplate", "SecureHandlerMouseUpDownTemplate", "SecureHandlerMouseWheelTemplate" }) do
    secureTemplate(n, "Frame")
  end
  env.SecureUnitButton_OnLoad = function(self, unit, menufunc)
    secureSet(self, "*type1", "target")
    secureSet(self, "*type2", menufunc and "menu" or "togglemenu")
    if unit then secureSet(self, "unit", unit) end
  end
  env.SecureHandlerSetFrameRef = function(frame, label, ref) W.st(frame).attributes["frameref-" .. label:lower()] = ref end
  env.SecureHandlerExecute = function(frame, body) h.secureSnippets[#h.secureSnippets + 1] = { frame = frame, snippet = body } end
  env.SecureHandlerWrapScript = function(frame, script, header, pre, post)
    h.secureSnippets[#h.secureSnippets + 1] = { frame = frame, snippet = "wrap:" .. script, pre = pre, post = post }
  end
  env.SecureHandlerUnwrapScript = function() end

  ---------------------------------------------------------------------------
  -- Group headers
  ---------------------------------------------------------------------------
  local function attr(header, name) return W.st(header).attributes[name:lower()] end
  local function truthy(v) return v ~= nil and v ~= false and v ~= "false" and v ~= 0 and v ~= "0" end

  local raw = require("secret").raw

  -- One roster row, as GetGroupRosterInfo builds it in SecureGroupHeaders.lua.
  local function unitInfo(token)
    local u = w:get(token)
    if not u then return nil end
    local _, class = env.UnitClass(token)
    return { token = token, name = u.name, class = raw(class), group = u.subgroup or 1,
      role = u.raidRole, assignedRole = u.role or "NONE", guid = u.guid }
  end

  local function fill(tbl, list)
    for k in tostring(list or ""):gmatch("[^,]+") do
      k = k:match("^%s*(.-)%s*$")
      tbl[tonumber(k) or k] = true
    end
  end

  -- Mirrors SecureGroupHeader_Update filtering (groupFilter/roleFilter/strict/nameList).
  local function filterUnits(header, list)
    local nameList = attr(header, "nameList")
    local groupFilter = attr(header, "groupFilter")
    local roleFilter = attr(header, "roleFilter")
    if not groupFilter and not roleFilter and not nameList then groupFilter = "1,2,3,4,5,6,7,8" end
    local r = {}
    if groupFilter or roleFilter then
      local strict = truthy(attr(header, "strictFiltering"))
      local tokens = {}
      if groupFilter and not roleFilter then
        fill(tokens, groupFilter)
        if strict then fill(tokens, "MAINTANK,MAINASSIST,TANK,HEALER,DAMAGER,NONE") end
      elseif roleFilter and not groupFilter then
        fill(tokens, roleFilter)
        if strict then fill(tokens, "1,2,3,4,5,6,7,8," .. table.concat(env.CLASS_SORT_ORDER, ",")) end
      else
        fill(tokens, groupFilter)
        fill(tokens, roleFilter)
      end
      for _, u in ipairs(list) do
        local nonStrict = tokens[u.group] or tokens[u.class or ""] or (u.role and tokens[u.role]) or tokens[u.assignedRole]
        local strictOk = tokens[u.group] and tokens[u.class or ""] and ((u.role and tokens[u.role]) or tokens[u.assignedRole])
        if u.name and ((not strict and nonStrict) or strictOk) then r[#r + 1] = u end
      end
    else
      local names = {}
      fill(names, nameList)
      for _, u in ipairs(list) do if names[u.name] then r[#r + 1] = u end end
    end
    return r
  end

  local function sortUnits(header, list)
    local sortMethod = attr(header, "sortMethod") or "INDEX"
    local groupBy = attr(header, "groupBy")
    local order = attr(header, "groupingOrder")
    local rank = {}
    if order then local i = 0; for t in tostring(order):gsub("%s+", ""):gmatch("[^,]+") do i = i + 1; rank[tonumber(t) or t] = i end end
    for i, u in ipairs(list) do u.index = i end
    table.sort(list, function(a, b)
      if groupBy then
        local function key(u)
          if groupBy == "GROUP" then return u.group elseif groupBy == "CLASS" then return u.class
          elseif groupBy == "ROLE" then return u.role end
          return u.assignedRole
        end
        local ka, kb = key(a), key(b)
        local ra, rb = rank[ka or ""] or 99, rank[kb or ""] or 99
        if ra ~= rb then return ra < rb end
      end
      if sortMethod == "NAME" then
        if a.name ~= b.name then return a.name < b.name end
      end
      return a.index < b.index
    end)
    if (attr(header, "sortDir") or "ASC") == "DESC" then
      local r = {}
      for i = #list, 1, -1 do r[#r + 1] = list[i] end
      return r
    end
    return list
  end

  local function collectUnits(header, pets)
    local list = {}
    local function add(token) local i = unitInfo(token); if i then list[#list + 1] = i end end
    if w.group == "raid" then
      if not truthy(attr(header, "showRaid")) then return list end
      for i = 1, 40 do
        if w:get("raid" .. i) then
          if pets then add("raidpet" .. i) else add("raid" .. i) end
        end
      end
    elseif w.group == "party" then
      if not truthy(attr(header, "showParty")) then return list end
      if truthy(attr(header, "showPlayer")) then if pets then add("pet") else add("player") end end
      for i = 1, 4 do if pets then add("partypet" .. i) else add("party" .. i) end end
    else
      -- showSolo implies showPlayer (SecureGroupHeaders.lua attribute notes)
      if truthy(attr(header, "showSolo")) then
        if pets then add("pet") else add("player") end
      end
    end
    if pets and truthy(attr(header, "filterOnPet")) then return filterUnits(header, list) end
    if pets then return list end
    return filterUnits(header, list)
  end

  local function relPoint(point)
    point = (point or "TOP"):upper()
    if point == "TOP" then return "BOTTOM", 0, -1 elseif point == "BOTTOM" then return "TOP", 0, 1
    elseif point == "LEFT" then return "RIGHT", 1, 0 elseif point == "RIGHT" then return "LEFT", -1, 0 end
    return "CENTER", 0, 0
  end

  local function setupChild(header, child)
    local tmpl = attr(header, "auraContainerTemplate")
    if tmpl then child.AuraContainer = env.CreateFrame("AuraContainer", nil, child, tmpl) end
    local code = attr(header, "initialConfigFunction")
    if type(code) == "string" then
      h.secureSnippets[#h.secureSnippets + 1] = { frame = child, snippet = "initialConfigFunction", body = code }
      -- the common sizing snippet: apply child-width/child-height from the header
      local cw, ch = attr(header, "child-width"), attr(header, "child-height")
      if cw then W.st(child).width = tonumber(cw) end
      if ch then W.st(child).height = tonumber(ch) end
    end
    local names = attr(header, "_initialAttributeNames")
    if type(names) == "string" then
      for n in names:gmatch("[^,]+") do secureSet(child, n, attr(header, "_initialAttribute-" .. n)) end
    end
  end

  local function updateHeader(header)
    local st = W.st(header)
    if st.updating or not W.isVisible(header) then return end
    st.updating = true
    local units = sortUnits(header, collectUnits(header, st.petHeader))
    local start = tonumber(attr(header, "startingIndex")) or 1
    local perCol = tonumber(attr(header, "unitsPerColumn"))
    local maxCols = tonumber(attr(header, "maxColumns")) or 1
    local displayed = #units - (start - 1)
    local cols = 1
    if perCol and displayed > perCol then cols = math.min(math.ceil(displayed / perCol), maxCols) else perCol = math.max(displayed, 0) end
    local finish = math.min((start - 1) + (perCol or 0) * cols, #units)
    local need = math.max(1, finish - (start - 1))
    local template = attr(header, "template")
    local templateType = attr(header, "templateType") or "Button"
    st.headerChildren = st.headerChildren or {}
    for i = 1, need do
      if not st.headerChildren[i] then
        local child = env.CreateFrame(templateType, st.name and (st.name .. "UnitButton" .. i), header, template)
        st.headerChildren[i] = child
        header[i] = child
        setupChild(header, child)
        local old = st.attributes._ignore
        st.attributes._ignore = "attributeChanges"
        st.attributes["child" .. i] = child
        st.attributes._ignore = old
      end
    end
    local point = attr(header, "point") or "TOP"
    local _, xm, ym = relPoint(point)
    local xOff, yOff = tonumber(attr(header, "xOffset")) or 0, tonumber(attr(header, "yOffset")) or 0
    local colSpacing = tonumber(attr(header, "columnSpacing")) or 0
    local colAnchor = attr(header, "columnAnchorPoint") or "LEFT"
    local _, cxm, cym = relPoint(colAnchor)
    -- With more than one column, Blizzard anchors the first button by both
    -- the growth point and the column anchor, so it sits in that corner.
    local anchor = point:upper()
    if cols > 1 then
      local v = anchor:match("TOP") or anchor:match("BOTTOM") or ""
      local hz = colAnchor:upper():match("LEFT") or colAnchor:upper():match("RIGHT") or ""
      if v == "" then
        v = colAnchor:upper():match("TOP") or colAnchor:upper():match("BOTTOM") or ""
        hz = anchor:match("LEFT") or anchor:match("RIGHT") or ""
      end
      anchor = (v .. hz) ~= "" and (v .. hz) or anchor
    end
    local n = 0
    for i = start, finish do
      n = n + 1
      local child = st.headerChildren[n]
      local cs = W.st(child)
      cs.points = {}
      local col = math.floor((n - 1) / math.max(perCol or 1, 1))
      local row = (n - 1) % math.max(perCol or 1, 1)
      local cw, ch = cs.width or 0, cs.height or 0
      local x = row * (xm * cw + xOff) + col * (cxm * (cw + colSpacing))
      local y = row * (ym * ch + yOff) + col * (cym * (ch + colSpacing))
      cs.points[1] = { point = anchor, rel = header, relPoint = anchor, x = x, y = y }
      -- A negative startingIndex (pre-creating buttons) shows buttons with no
      -- unit, like Blizzard's header does.
      local token = units[i] and units[i].token
      if cs.attributes.unit ~= token then secureSet(child, "unit", token) end
      secureShow(child, true)
    end
    for i = n + 1, #st.headerChildren do
      local child = st.headerChildren[i]
      secureShow(child, false)
      if W.st(child).attributes.unit ~= nil then secureSet(child, "unit", nil) end
    end
    -- Like Blizzard's configureChildren, the header resizes to wrap what it
    -- shows, so anchoring it by a corner lines the buttons up with that corner.
    if n > 0 then
      local first = W.st(st.headerChildren[1])
      local cw, ch = first.width or 0, first.height or 0
      local rows = math.min(math.max(perCol or n, 1), n)
      local width = math.abs(xm) * (rows - 1) * cw + (rows - 1) * math.abs(xOff) + cw
      local height = math.abs(ym) * (rows - 1) * ch + (rows - 1) * math.abs(yOff) + ch
      if cols > 1 then
        width = width + (cols - 1) * math.abs(cxm) * (width + colSpacing)
        height = height + (cols - 1) * math.abs(cym) * (height + colSpacing)
      end
      st.width, st.height = width, height
    else
      st.width = tonumber(attr(header, "minWidth")) or 0.1
      st.height = tonumber(attr(header, "minHeight")) or 0.1
    end
    st.updating = false
  end
  h.updateHeader = updateHeader

  local function headerApply(pets)
    return function(obj, st)
      st.isHeader, st.petHeader = true, pets
      st.onAttributeInternal = function(self, key)
        -- Like SecureGroupHeader_OnAttributeChanged: "_ignore" batches changes.
        if key == "_ignore" or W.st(self).attributes._ignore then return end
        if not key:match("^child%d") and not key:match("^frameref") then updateHeader(self) end
      end
      st.onShowInternal = function(self) updateHeader(self) end
      local f = env.CreateFrame("Frame", nil, obj)
      f:RegisterEvent("GROUP_ROSTER_UPDATE")
      f:RegisterEvent("UNIT_NAME_UPDATE")
      f:SetScript("OnEvent", function() updateHeader(obj) end)
      W.st(f).harnessInternal = true
      obj:Hide()
    end
  end
  secureTemplate("SecureGroupHeaderTemplate", "Frame", headerApply(false))
  secureTemplate("SecurePartyHeaderTemplate", "Frame", headerApply(false))
  secureTemplate("SecureRaidGroupHeaderTemplate", "Frame", headerApply(false))
  secureTemplate("SecureGroupPetHeaderTemplate", "Frame", headerApply(true))
  secureTemplate("SecurePartyPetHeaderTemplate", "Frame", headerApply(true))
  secureTemplate("SecureRaidPetHeaderTemplate", "Frame", headerApply(true))
end

return S
