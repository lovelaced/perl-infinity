-- tests/harness/auracontainer.lua
-- CustomAuraContainerTemplate mock (Blizzard_CustomAuraContainer.lua inbound API).
-- Records groups, slots, filters, sort, layout and button styling, and enforces:
--   * no creating containers, groups, slots or buttons, and no touching buttons,
--     while aura data is secret (combat/encounter restrictions);
--   * AddDispelTypeTexture errors on double registration of one texture;
--   * a warning when includeSpellIDs is set on a HARMFUL filter (ignored in game for
--     debuffs on friendly units).
-- The container's size is secret once a group exists, so anything anchored to it
-- reports secret geometry (Blizzard wraps it to hide aura counts).

local A = {}

local FILTER_TOKENS = { HELPFUL = 1, HARMFUL = 1, PLAYER = 1, RAID = 1, CANCELABLE = 1, NOT_CANCELABLE = 1,
  INCLUDE_NAME_PLATE_ONLY = 1, MAW = 1, EXTERNAL_DEFENSIVE = 1, CROWD_CONTROL = 1, RAID_IN_COMBAT = 1,
  RAID_PLAYER_DISPELLABLE = 1, BIG_DEFENSIVE = 1, IMPORTANT = 1, DISPELLABLE = 1 }

local function validFilter(f)
  if type(f) ~= "string" or f == "" then return false end
  local hasKind = false
  for tok in f:gmatch("[^|%s]+") do
    local t = tok:gsub("^!", "")
    if not FILTER_TOKENS[t] then return false, "unknown filter token '" .. tok .. "'" end
    if t == "HELPFUL" or t == "HARMFUL" then hasKind = true end
  end
  if not hasKind then return false, "filter needs HELPFUL or HARMFUL" end
  return true
end
A.validFilter = validFilter

function A.install(h)
  local env = h.env
  local W = h.widgets
  local w = h.world

  env.AuraContainerSortMethod = { Default = 0, BigDefensive = 1, UnitFrameDebuff = 2, ImportantOnly = 3,
    Expiration = 4, ExpirationOnly = 5, Name = 6, NameOnly = 7, AuraInstanceIDOnly = 8 }
  env.AuraContainerSortDirection = { Normal = 0, Reverse = 1 }
  env.AuraContainerItemEnchantmentSlot = { MainHand = 0, OffHand = 1, Ranged = 2 }
  env.AuraContainerItemEnchantmentSortMethod = { Slot = 0, Duration = 1 }
  env.CustomAuraContainerItemEnchantmentPlacement = { BeforeAuraGroups = 0, AfterAuraGroups = 1 }
  env.CustomAuraContainerAuraProcessingPolicy = { None = 0, ProcessAura = 1 }
  env.AnchorUtil = env.AnchorUtil or {}
  env.AnchorUtil.FlowLayoutAxis = { Horizontal = 1, Vertical = 2 }
  env.AnchorUtil.FlowDirection = { Left = 1, Right = 2, Up = 3, Down = 4 }

  local function secretNow() return h.mode ~= "open" and w:aurasRestricted() end
  local function guard(what)
    if secretNow() then
      error(what .. ": aura frames cannot be created or changed while auras are secret (tainted by '" .. h.addonName .. "')", 3)
    end
  end
  local function cst(self)
    local s = W.st(self)
    if not s.aura then error("not an aura container", 3) end
    return s.aura
  end

  -- Buttons: Button frames with the CustomAuraButton API.
  local ButtonAPI = {}
  local function bst(self) return W.st(self).auraButton end
  local function buttonGuard(self, what)
    local b = bst(self)
    if b and b.ready and secretNow() then
      error(what .. ": aura button access denied while auras are secret (tainted by '" .. h.addonName .. "')", 3)
    end
  end
  for _, m in ipairs({ "SetApplicationBar", "SetApplicationCount", "SetDispelTypeText", "SetDurationCooldown",
    "SetDurationText", "SetDurationBar", "SetIcon", "SetSpellName", "SetCasterName" }) do
    ButtonAPI[m] = function(self, region, options)
      buttonGuard(self, m)
      bst(self).bindings[m] = { region = region, options = options }
    end
    ButtonAPI["Get" .. m:sub(4)] = function(self) local b = bst(self).bindings[m]; return b and b.region end
    ButtonAPI["Clear" .. m:sub(4)] = function(self) bst(self).bindings[m] = nil end
  end
  function ButtonAPI:AddDispelTypeTexture(tex, options)
    buttonGuard(self, "AddDispelTypeTexture")
    local b = bst(self)
    for _, d in ipairs(b.dispelTextures) do
      if d.texture == tex then error("AddDispelTypeTexture: texture is already registered on this button", 2) end
    end
    b.dispelTextures[#b.dispelTextures + 1] = { texture = tex, options = options }
  end
  function ButtonAPI:RemoveDispelTypeTexture(tex)
    local b = bst(self)
    for i = #b.dispelTextures, 1, -1 do if b.dispelTextures[i].texture == tex then table.remove(b.dispelTextures, i) end end
  end
  function ButtonAPI:ClearDispelTypeTextures() bst(self).dispelTextures = {} end
  function ButtonAPI:GetDispelTypeTextureCount() return #bst(self).dispelTextures end
  function ButtonAPI:GetDispelTypeTexture(i) local d = bst(self).dispelTextures[i]; return d and d.texture end
  function ButtonAPI:SetCancelAuraButtons(v) bst(self).cancelButtons = v; self.testCancelButtons = v end
  function ButtonAPI:SetTooltipAnchorPoint(p, x, y) bst(self).tooltipAnchor = { p, x, y } end
  function ButtonAPI:GetTooltipAnchorPoint() local t = bst(self).tooltipAnchor; if t then return t[1], t[2], t[3] end end
  function ButtonAPI:SetHideTooltipInCombat(v) bst(self).hideTooltipInCombat = v end
  function ButtonAPI:ShouldHideTooltipInCombat() return bst(self).hideTooltipInCombat == true end
  for _, kind in ipairs({ "PandemicRegion", "PandemicEnterAnimation", "PandemicActiveAnimation",
    "PandemicLeaveAnimation", "AuraAssignedAnimation", "AuraShownAnimation" }) do
    ButtonAPI["Add" .. kind] = function(self, x)
      local list = bst(self).lists
      list[kind] = list[kind] or {}
      table.insert(list[kind], x)
    end
    ButtonAPI["Remove" .. kind] = function() end
    ButtonAPI["Clear" .. kind .. "s"] = function(self) bst(self).lists[kind] = nil end
  end

  local function createButton(container, spec)
    guard("aura button creation")
    local templates = spec.templateNames and table.concat(spec.templateNames, ",") or nil
    local btn = env.CreateFrame("Button", nil, container, templates)
    local s = W.st(btn)
    s.auraButton = { bindings = {}, dispelTextures = {}, lists = {}, group = spec.key }
    for k, f in pairs(ButtonAPI) do btn[k] = f end
    btn:Hide()
    if spec.initializeFrame then
      h:protectedCall(spec.initializeFrame, "AuraContainer initializeFrame (" .. tostring(spec.key) .. ")", btn)
    end
    s.auraButton.ready = true
    return btn
  end

  local function checkCandidateFilters(filter, cf, what)
    if cf == nil then return end
    if type(cf) ~= "table" then error(what .. ": candidateFilters must be a table or nil", 3) end
    if cf.includeSpellIDs and tostring(filter):upper():find("HARMFUL") then
      h:warn(what .. ": includeSpellIDs on a HARMFUL filter is ignored in game for debuffs on friendly units")
    end
    for _, k in ipairs({ "isFromPlayerOrPlayerPet", "isRoleAura", "isPriorityAura", "isStealable",
      "nameplateShowAll", "nameplateShowPersonal", "canApplyAura", "isBossAura", "isBossOrRoleAura" }) do
      if cf[k] ~= nil and type(cf[k]) ~= "boolean" then error(what .. ": " .. k .. " must be a boolean or nil", 3) end
    end
  end

  local function checkSort(m, d, what)
    if m ~= nil then
      local ok = false
      for _, v in pairs(env.AuraContainerSortMethod) do if v == m then ok = true end end
      if not ok then error(what .. ": sortMethod must be a valid AuraContainerSortMethod", 3) end
    end
    if d ~= nil and d ~= 0 and d ~= 1 then error(what .. ": sortDirection must be a valid AuraContainerSortDirection", 3) end
  end

  local API = {}
  function API:IsEnabled() return cst(self).enabled end
  function API:SetEnabled(on) cst(self).enabled = on and true or false end
  function API:GetUnit() return cst(self).unit end
  function API:SetUnit(unit) cst(self).unit = unit; cst(self).updates = cst(self).updates + 1 end
  function API:UpdateAllAuras() cst(self).updates = cst(self).updates + 1 end
  function API:IsEditModePreviewEnabled() return cst(self).editModePreview end
  function API:SetEditModePreviewEnabled(on) cst(self).editModePreview = on end
  function API:AddAuraGroup(key, filter, options)
    if type(key) ~= "string" or key == "" then error("AddAuraGroup: groupKey must be a non-empty string.", 2) end
    local ok, why = validFilter(filter)
    if not ok then error("AddAuraGroup: invalid filter string " .. tostring(filter) .. (why and (": " .. why) or ""), 2) end
    local c = cst(self)
    if c.groups[key] then error(string.format("AddAuraGroup: aura group '%s' already exists with this key.", key), 2) end
    guard("AddAuraGroup")
    options = options or {}
    checkCandidateFilters(filter, options.candidateFilters, "AddAuraGroup")
    checkSort(options.sortMethod, options.sortDirection, "AddAuraGroup")
    local g = { key = key, filter = filter, options = options, maxFrameCount = options.maxFrameCount or math.huge,
      candidateFilters = options.candidateFilters, sortMethod = options.sortMethod, sortDirection = options.sortDirection,
      layout = options.layout, enabled = true, frames = {} }
    c.groups[key] = g
    c.order[#c.order + 1] = key
    for i = 1, 10 do g.frames[i] = createButton(self, { key = key, templateNames = options.templateNames, initializeFrame = options.initializeFrame }) end
    W.st(self).secretSize = true
  end
  function API:HasAuraGroup(key) return cst(self).groups[key] ~= nil end
  local function group(self, key, what)
    local g = cst(self).groups[key]
    if not g then error(string.format("%s: aura group '%s' was not found with this key.", what, tostring(key)), 3) end
    return g
  end
  function API:GetAuraGroupFrame(key, i)
    local g = group(self, key, "GetAuraGroupFrame")
    return g.frames[i]
  end
  function API:GetAuraGroupFrameCount(key)
    -- Every button the group owns, in use or not, as in the real container.
    return #group(self, key, "GetAuraGroupFrameCount").frames
  end
  function API:IsAuraGroupEnabled(key) return group(self, key, "IsAuraGroupEnabled").enabled end
  function API:SetAuraGroupEnabled(key, on) group(self, key, "SetAuraGroupEnabled").enabled = on and true or false end
  function API:SetAuraGroupFilterString(key, filter)
    local ok, why = validFilter(filter)
    if not ok then error("SetAuraGroupFilterString: invalid filter " .. tostring(filter) .. (why and (": " .. why) or ""), 2) end
    group(self, key, "SetAuraGroupFilterString").filter = filter
  end
  function API:SetAuraGroupMaxFrameCount(key, n)
    if type(n) ~= "number" or n < 0 then error("maxFrameCount must be a non-negative integer or infinity.", 2) end
    group(self, key, "SetAuraGroupMaxFrameCount").maxFrameCount = n
  end
  function API:SetAuraGroupCandidateFilters(key, cf)
    local g = group(self, key, "SetAuraGroupCandidateFilters")
    checkCandidateFilters(g.filter, cf, "SetAuraGroupCandidateFilters")
    g.candidateFilters = cf
  end
  function API:SetAuraGroupSortMethod(key, m, d)
    checkSort(m, d, "SetAuraGroupSortMethod")
    local g = group(self, key, "SetAuraGroupSortMethod")
    g.sortMethod, g.sortDirection = m, d
  end
  function API:SetAuraGroupLayout(key, layout)
    local g = group(self, key, "SetAuraGroupLayout")
    if secretNow() and layout and (layout.elementWidth or layout.elementHeight) then
      guard("SetAuraGroupLayout (resize)")
    end
    g.layout = layout
  end
  function API:AddAuraSlot(key, filter, options)
    local ok, why = validFilter(filter)
    if not ok then error("AddAuraSlot: invalid filter " .. tostring(filter) .. (why and (": " .. why) or ""), 2) end
    local c = cst(self)
    if c.slots[key] then error(string.format("AddAuraSlot: aura slot '%s' already exists.", key), 2) end
    guard("AddAuraSlot")
    options = options or {}
    checkCandidateFilters(filter, options.candidateFilters, "AddAuraSlot")
    checkSort(options.sortMethod, options.sortDirection, "AddAuraSlot")
    c.slots[key] = { key = key, filter = filter, options = options, enabled = true,
      frame = createButton(self, { key = key, templateNames = options.templateNames, initializeFrame = options.initializeFrame }) }
  end
  local function slot(self, key, what)
    local s = cst(self).slots[key]
    if not s then error(string.format("%s: aura slot '%s' was not found with this key.", what, tostring(key)), 3) end
    return s
  end
  function API:GetAuraSlotFrame(key) return slot(self, key, "GetAuraSlotFrame").frame end
  function API:IsAuraSlotEnabled(key) return slot(self, key, "IsAuraSlotEnabled").enabled end
  function API:SetAuraSlotEnabled(key, on) slot(self, key, "SetAuraSlotEnabled").enabled = on and true or false end
  function API:SetAuraSlotFilterString(key, f) slot(self, key, "SetAuraSlotFilterString").filter = f end
  function API:SetAuraSlotCandidateFilters(key, cf)
    local s = slot(self, key, "SetAuraSlotCandidateFilters")
    checkCandidateFilters(s.filter, cf, "SetAuraSlotCandidateFilters")
    s.candidateFilters = cf
  end
  function API:SetAuraSlotSortMethod(key, m, d) checkSort(m, d, "SetAuraSlotSortMethod"); local s = slot(self, key, "x"); s.sortMethod, s.sortDirection = m, d end
  function API:AddItemEnchantment(slotId, options)
    guard("AddItemEnchantment")
    local c = cst(self)
    if c.enchants[slotId] then error("AddItemEnchantment: slot already added", 2) end
    options = options or {}
    c.enchants[slotId] = { options = options, enabled = true,
      frame = createButton(self, { key = "enchant" .. tostring(slotId), templateNames = options.templateNames, initializeFrame = options.initializeFrame }) }
  end
  function API:GetItemEnchantmentFrame(slotId) local e = cst(self).enchants[slotId]; return e and e.frame end
  function API:IsItemEnchantmentEnabled(slotId) local e = cst(self).enchants[slotId]; return e and e.enabled or false end
  function API:SetItemEnchantmentEnabled(slotId, on) local e = cst(self).enchants[slotId]; if e then e.enabled = on end end
  function API:SetItemEnchantmentSortMethod(m, d) cst(self).enchantSort = { m, d } end
  function API:SetItemEnchantmentLayout(l) cst(self).enchantLayout = l end
  function API:ResetItemEnchantmentLayout() cst(self).enchantLayout = nil end
  function API:GetAuraProcessingPolicy() return cst(self).policy or 0 end
  function API:SetAuraProcessingPolicy(p, o) cst(self).policy, cst(self).policyOptions = p, o end
  for _, prop in ipairs({ "Axis", "AnchorPoint", "MaximumLineSize" }) do
    API["SetFlowLayout" .. prop] = function(self, v) cst(self).flow[prop] = v end
    API["GetFlowLayout" .. prop] = function(self) return cst(self).flow[prop] end
  end
  function API:SetFlowLayoutGrowthDirection(hd, vd) cst(self).flow.GrowthDirection = { hd, vd } end
  function API:GetFlowLayoutGrowthDirection() local g = cst(self).flow.GrowthDirection or {}; return g[1], g[2] end
  function API:SetFlowLayoutPadding(l, r, t, b) cst(self).flow.Padding = { l, r, t, b } end
  function API:GetFlowLayoutPadding() local p = cst(self).flow.Padding or { 0, 0, 0, 0 }; return unpack(p) end
  function API:ResetFlowLayoutOptions() cst(self).flow = {} end

  W.templates.CustomAuraContainerTemplate = {
    name = "CustomAuraContainerTemplate", type = "AuraContainer",
    apply = function(obj, st)
      if st.type ~= "AuraContainer" then error("CustomAuraContainerTemplate requires frame type AuraContainer", 0) end
      guard("CreateFrame(AuraContainer)")
      st.aura = { enabled = true, groups = {}, order = {}, slots = {}, enchants = {}, flow = {}, updates = 0, editModePreview = true }
      for k, f in pairs(API) do obj[k] = f end
    end,
  }
  W.templates.CustomAuraButtonTemplate = { name = "CustomAuraButtonTemplate", type = "Button" }
end

return A
