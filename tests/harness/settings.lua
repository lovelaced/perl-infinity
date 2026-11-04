-- tests/harness/settings.lua
-- Recording mock of Blizzard's Settings API (Blizzard_Settings_Shared, this branch's
-- signatures). Builds an inspectable tree in h.settings and enforces the rules the
-- real bridge enforces: unique variables, variableType == type(default), typed
-- SetValue, no function defaults outside proxy settings, and OpenToCategory being
-- restricted in combat.
--
-- Tree: h.settings.categories[i] = { name, id, layout, subcategories = {...},
--   initializers = {...}, addon = bool }; h.settings.byVariable[var] = setting.

local Secret = require("secret")

local S = {}

function S.install(h)
  local env = h.env
  local T = { categories = {}, byVariable = {}, opened = {}, notified = {}, nextID = 1000 }
  h.settings = T

  local Settings = {}
  env.Settings = Settings
  Settings.VarType = { Boolean = "boolean", String = "string", Number = "number" }
  Settings.Default = { True = true, False = false }
  Settings.CommitFlag = { None = 0, ClientRestart = 1, GxRestart = 2, UpdateWindow = 4, SaveBindings = 8,
    Revertable = 16, Apply = 32, IgnoreApply = 64, KioskProtected = 128, UIReload = 256 }
  Settings.CategorySet = { Game = 1, AddOns = 2 }
  Settings.ControlType = { Radio = 1, Checkbox = 2 }

  local function noSecrets(what, ...)
    for i = 1, select("#", ...) do
      if Secret.is((select(i, ...))) then error(what .. ": secret values are not allowed for settings APIs", 3) end
    end
  end

  ---------------------------------------------------------------------------
  -- Categories and layouts
  ---------------------------------------------------------------------------
  local CategoryMT = { __index = {
    GetID = function(self) return self.id end,
    GetName = function(self) return self.name end,
    SetShouldSortAlphabetically = function(self, v) self.sortAlpha = v end,
    GetParentCategory = function(self) return self.parent end,
    GetSubcategories = function(self) return self.subcategories end,
    SetOrder = function(self, o) self.order = o end,
  } }
  local LayoutMT = { __index = {
    AddInitializer = function(self, init)
      if type(init) ~= "table" or not init.__isInitializer then error("AddInitializer: initializer expected", 2) end
      table.insert(self.category.initializers, init)
      init.category = self.category
    end,
    GetInitializers = function(self) return self.category.initializers end,
    IsVerticalLayout = function(self) return self.vertical end,
  } }

  local function newCategory(name, parent, vertical, frame)
    if type(name) ~= "string" or name == "" then error("Settings: category name must be a non-empty string", 3) end
    noSecrets("RegisterCategory", name)
    T.nextID = T.nextID + 1
    local c = setmetatable({ name = name, id = T.nextID, parent = parent, subcategories = {}, initializers = {},
      vertical = vertical, frame = frame }, CategoryMT)
    c.layout = setmetatable({ category = c, vertical = vertical }, LayoutMT)
    if parent then table.insert(parent.subcategories, c) end
    return c, c.layout
  end
  function Settings.RegisterVerticalLayoutCategory(name) return newCategory(name, nil, true) end
  function Settings.RegisterVerticalLayoutSubcategory(parent, name)
    if getmetatable(parent) ~= CategoryMT then error("RegisterVerticalLayoutSubcategory: parent category expected", 2) end
    return newCategory(name, parent, true)
  end
  function Settings.RegisterCanvasLayoutCategory(frame, name) return newCategory(name, nil, false, frame) end
  function Settings.RegisterCanvasLayoutSubcategory(parent, frame, name) return newCategory(name, parent, false, frame) end
  function Settings.RegisterAddOnCategory(category)
    if getmetatable(category) ~= CategoryMT then error("RegisterAddOnCategory: category expected", 2) end
    if category.addon then error("RegisterAddOnCategory: category registered twice", 2) end
    category.addon = true
    table.insert(T.categories, category)
  end
  function Settings.RegisterCategory(category) table.insert(T.categories, category) end
  function Settings.GetCategory(name)
    -- Blizzard bug on this branch: compares a name against IDs; keep your own reference.
    for _, c in ipairs(T.categories) do if c.id == name then return c end end
  end
  function Settings.OpenToCategory(categoryID, scrollTo)
    if h.world.inCombat then h:blockedAction("Settings.OpenToCategory (C_SettingsUtil.OpenSettingsPanel)"); return false end
    T.opened[#T.opened + 1] = { id = categoryID, scrollTo = scrollTo }
    h:fire("SETTINGS_PANEL_OPEN")
    return true
  end

  ---------------------------------------------------------------------------
  -- Settings
  ---------------------------------------------------------------------------
  local SettingMT = { __index = {} }
  local SM = SettingMT.__index
  function SM:GetVariable() return self.variable end
  function SM:GetName() return self.name end
  function SM:GetVariableType() return self.variableType end
  function SM:GetDefaultValue() return self.default end
  function SM:GetValue()
    if self.getter then
      local ok, v = pcall(self.getter)
      if not ok then h:reportError("Settings getter " .. self.variable .. ": " .. tostring(v), "Settings"); return self.default end
      return v
    end
    return self.tbl[self.key]
  end
  function SM:SetValue(value, force)
    if type(value) ~= self.variableType then
      error(string.format("Settings %s: SetValue type %s, expected %s", self.variable, type(value), self.variableType), 2)
    end
    noSecrets("SetValue", value)
    local old = self:GetValue()
    if self.setter then h:protectedCall(self.setter, "Settings setter " .. self.variable, value)
    else self.tbl[self.key] = value end
    if old ~= value or force then
      for _, cb in ipairs(self.callbacks) do h:protectedCall(cb.fn, "Settings callback " .. self.variable, self, value) end
    end
  end
  function SM:SetValueToDefault() if self.default ~= nil then self:SetValue(self.default, true) end end
  function SM:SetValueChangedCallback(fn, owner) table.insert(self.callbacks, { fn = fn, owner = owner }) end
  function SM:SetCommitFlags(...) self.commitFlags = { ... } end
  function SM:HasCommitFlag() return false end
  function SM:NotifyUpdate() T.notified[#T.notified + 1] = self.variable end

  local function register(category, variable, variableType, name, default, extra)
    if getmetatable(category) ~= CategoryMT then error("Settings: category expected", 3) end
    if type(variable) ~= "string" or variable == "" then error("Settings: variable must be a string", 3) end
    if T.byVariable[variable] then error("Settings: variable '" .. variable .. "' was previously registered", 3) end
    if variableType ~= "boolean" and variableType ~= "string" and variableType ~= "number" then
      error("Settings: invalid variableType " .. tostring(variableType), 3)
    end
    if default ~= nil and type(default) ~= variableType then
      error(string.format("Settings %s: default is %s, variableType is %s", variable, type(default), variableType), 3)
    end
    if type(name) ~= "string" then error("Settings " .. variable .. ": name must be a string", 3) end
    noSecrets("RegisterSetting", variable, name, default)
    local s = setmetatable({ category = category, variable = variable, variableType = variableType, name = name,
      default = default, callbacks = {} }, SettingMT)
    for k, v in pairs(extra or {}) do s[k] = v end
    T.byVariable[variable] = s
    category.settings = category.settings or {}
    table.insert(category.settings, s)
    return s
  end
  function Settings.RegisterAddOnSetting(category, variable, key, tbl, variableType, name, default)
    if type(default) == "function" then error("Function values are not allowed for settings APIs", 2) end
    if type(tbl) ~= "table" then error("RegisterAddOnSetting: variableTbl must be a table", 2) end
    local s = register(category, variable, variableType, name, default, { tbl = tbl, key = key })
    if tbl[key] == nil then tbl[key] = default end
    return s
  end
  function Settings.RegisterProxySetting(category, variable, variableType, name, default, getValue, setValue)
    if type(getValue) ~= "function" or type(setValue) ~= "function" then
      error("RegisterProxySetting: getValue and setValue must be functions", 2)
    end
    return register(category, variable, variableType, name, default, { getter = getValue, setter = setValue })
  end
  function Settings.RegisterCVarSetting(category, cvar, variableType, name)
    return register(category, cvar, variableType, name, nil, { tbl = {}, key = cvar, cvar = true })
  end
  function Settings.GetSetting(variable) return T.byVariable[variable] end
  function Settings.GetValue(variable)
    local s = T.byVariable[variable]
    if not s then error("Settings.GetValue: unknown variable " .. tostring(variable), 2) end
    return s:GetValue()
  end
  function Settings.SetValue(variable, value, force)
    local s = T.byVariable[variable]
    if not s then error("Settings.SetValue: unknown variable " .. tostring(variable), 2) end
    s:SetValue(value, force)
  end
  function Settings.NotifyUpdate(variable)
    if not T.byVariable[variable] then h:warn("Settings.NotifyUpdate: unknown variable " .. tostring(variable)) end
    T.notified[#T.notified + 1] = variable
  end
  function Settings.SetOnValueChangedCallback(variable, fn, owner)
    local s = T.byVariable[variable]
    if not s then error("SetOnValueChangedCallback: unknown variable " .. tostring(variable), 2) end
    s:SetValueChangedCallback(fn, owner)
    return { Unregister = function() end }
  end
  function Settings.CallWhenRegistered(variable, fn) if T.byVariable[variable] then fn(T.byVariable[variable]) end end
  -- test helper: press Defaults ("These Settings") on one category
  function T.defaults(category)
    for _, s in ipairs(category.settings or {}) do s:SetValueToDefault() end
    env.EventRegistry:TriggerEvent("Settings.CategoryDefaulted", category)
  end
  function T.find(name)
    local function walk(list)
      for _, c in ipairs(list) do
        if c.name == name then return c end
        local r = walk(c.subcategories)
        if r then return r end
      end
    end
    return walk(T.categories)
  end

  ---------------------------------------------------------------------------
  -- Initializers and controls
  ---------------------------------------------------------------------------
  local InitMT = { __index = {} }
  local IM = InitMT.__index
  function IM:SetParentInitializer(parent, predicate) self.parentInit, self.parentPredicate = parent, predicate end
  function IM:AddModifyPredicate(fn) self.modifyPredicates = self.modifyPredicates or {}; table.insert(self.modifyPredicates, fn) end
  function IM:AddShownPredicate(fn) self.shownPredicates = self.shownPredicates or {}; table.insert(self.shownPredicates, fn) end
  function IM:AddSearchTags(...) self.searchTags = self.searchTags or {}; for _, t in ipairs({ ... }) do table.insert(self.searchTags, t) end end
  function IM:AddEvaluateStateFrameEvent(e) self.stateEvents = self.stateEvents or {}; table.insert(self.stateEvents, e) end
  function IM:AddEvaluateStateCVar() end
  function IM:Indent() self.indent = true end
  function IM:GetSetting() return self.data and self.data.setting end
  function IM:GetData() return self.data end
  function IM:GetTemplate() return self.template end
  function IM:SetSetting(s) self.data = self.data or {}; self.data.setting = s end
  function IM:IsShown()
    for _, f in ipairs(self.shownPredicates or {}) do if not f() then return false end end
    return true
  end
  function IM:IsEnabled()
    if self.parentPredicate and not self.parentPredicate() then return false end
    for _, f in ipairs(self.modifyPredicates or {}) do if not f() then return false end end
    return true
  end
  function IM:GetExtent() return self.extent end
  function IM:SetExtent(e) self.extent = e end

  local function newInit(kind, template, data)
    return setmetatable({ __isInitializer = true, kind = kind, template = template, data = data or {} }, InitMT)
  end
  local function control(kind, template)
    return function(category, setting, a, b)
      if getmetatable(setting) ~= SettingMT then error("Settings.Create" .. kind .. ": setting expected", 2) end
      local init = newInit(kind, template, { setting = setting, name = setting.name })
      if kind == "Slider" then init.data.options, init.data.tooltip = a, b
      elseif kind == "Dropdown" then
        init.data.options, init.data.tooltip = a, b
        if type(a) ~= "function" then error("Settings.CreateDropdown: options must be a function", 2) end
        local ok, opts = pcall(a)
        if not ok then h:reportError("dropdown options function failed: " .. tostring(opts), "Settings") end
        init.data.optionValues = ok and opts or nil
      elseif kind == "ColorSwatch" then init.data.tooltip, init.data.options = a, b
      else init.data.tooltip = a end
      category.layout:AddInitializer(init)
      return init
    end
  end
  Settings.CreateCheckbox = control("Checkbox", "SettingsCheckboxControlTemplate")
  Settings.CreateSlider = control("Slider", "SettingsSliderControlTemplate")
  Settings.CreateDropdown = control("Dropdown", "SettingsDropdownControlTemplate")
  Settings.CreateColorSwatch = control("ColorSwatch", "SettingsColorSwatchControlTemplate")
  function Settings.CreateCheckboxWithOptions(category, setting, options, tooltip)
    local init = control("Checkbox", "SettingsCheckboxControlTemplate")(category, setting, tooltip)
    init.data.options = options
    return init
  end
  function Settings.CreateSliderOptions(minValue, maxValue, rate)
    if type(minValue) ~= "number" or type(maxValue) ~= "number" then error("CreateSliderOptions: min and max must be numbers", 2) end
    return {
      minValue = minValue, maxValue = maxValue, steps = rate and (maxValue - minValue) / rate or 100, rate = rate,
      SetLabelFormatter = function(self, labelType, value) self.formatters = self.formatters or {}; self.formatters[labelType] = value end,
    }
  end
  function Settings.CreateControlTextContainer()
    local data = {}
    return {
      Add = function(_, value, label, tooltip) table.insert(data, { value = value, label = label, tooltip = tooltip }); return data[#data] end,
      AddCheckbox = function(_, value, label, tooltip) table.insert(data, { value = value, label = label, tooltip = tooltip, checkbox = true }); return data[#data] end,
      GetData = function() return data end,
    }
  end
  function Settings.CreatePanelInitializer(template, data)
    if type(template) ~= "string" then error("CreatePanelInitializer: template name expected", 2) end
    local t = h.widgets.templates[template] or h.blizzardTemplates[template]
    if not t then h:warn("Settings.CreatePanelInitializer: template '" .. template .. "' is not defined") end
    return newInit("Panel", template, data)
  end
  function Settings.CreateElementInitializer(template, data) return newInit("Element", template, data) end
  function Settings.CreateSettingInitializer(template, data) return newInit("Setting", template, data) end
  function Settings.InitTooltip(name, tooltip) return function() return name, tooltip end end
  env.CreateSettingsListSectionHeaderInitializer = function(name, tooltip)
    if type(name) ~= "string" then error("CreateSettingsListSectionHeaderInitializer: name must be a string", 2) end
    return newInit("SectionHeader", "SettingsListSectionHeaderTemplate", { name = name, tooltip = tooltip })
  end
  env.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip, addSearchTags)
    if addSearchTags == nil then error("CreateSettingsButtonInitializer: addSearchTags must not be nil", 2) end
    if type(onClick) ~= "function" then error("CreateSettingsButtonInitializer: buttonClick must be a function", 2) end
    return newInit("Button", "SettingButtonControlTemplate", { name = name, buttonText = buttonText, buttonClick = onClick, tooltip = tooltip })
  end
  env.CreateSettingsCheckboxSliderInitializer = function(cb, cbLabel, cbTooltip, slider, opts, sLabel, sTooltip)
    return newInit("CheckboxSlider", "SettingsCheckboxSliderControlTemplate", { cbSetting = cb, cbLabel = cbLabel,
      cbTooltip = cbTooltip, sliderSetting = slider, sliderOptions = opts, sliderLabel = sLabel, sliderTooltip = sTooltip, setting = cb })
  end
  env.CreateSettingsCheckboxDropdownInitializer = function(cb, cbLabel, cbTooltip, dd, ddOptions, ddLabel, ddTooltip)
    return newInit("CheckboxDropdown", "SettingsCheckboxDropdownControlTemplate", { cbSetting = cb, cbLabel = cbLabel,
      cbTooltip = cbTooltip, dropdownSetting = dd, dropdownOptions = ddOptions, dropdownLabel = ddLabel, dropdownTooltip = ddTooltip, setting = cb })
  end
  env.CreateSettingsCheckboxWithButtonInitializer = function(setting, buttonText, onClick, evaluateState, clickRequiresSet, tooltip)
    return newInit("CheckboxWithButton", "SettingsCheckboxWithButtonControlTemplate", { setting = setting,
      buttonText = buttonText, buttonClick = onClick, clickRequiresSet = clickRequiresSet, tooltip = tooltip })
  end
  env.CreateSettingsCheckboxWithColorSwatchInitializer = function(setting, tooltip, swatchClick, clickRequiresSet, invert, colorFn, title, text)
    return newInit("CheckboxWithColorSwatch", "SettingsCheckboxWithColorSwatchControlTemplate", { setting = setting,
      tooltip = tooltip, swatchClick = swatchClick, colorFn = colorFn, swatchTitle = title, swatchText = text })
  end
  env.CreateSettingsAddOnDisabledLabelInitializer = function() return newInit("DisabledLabel", "SettingsAddOnDisabledLabelTemplate", {}) end
  env.MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 }, Event = { OnValueChanged = "OnValueChanged" } }
  env.CreateMinimalSliderFormatter = function(_, fn) return fn end
  env.SettingsPanel = h.widgets and env.CreateFrame("Frame", "SettingsPanel", env.UIParent) or nil
  if env.SettingsPanel then env.SettingsPanel:Hide() end
end

return S
