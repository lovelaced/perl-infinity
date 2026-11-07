-- tests/harness/stubs/LibEditMode.lua
-- Recording stub of LibEditMode's public API (p3lim, tag 18; namespaced mode sets
-- ns.LibEditMode). The loader substitutes it for PerlInfinity/Libs/LibEditMode/*. Callback
-- signatures match the real library:
--   AddFrame callback: (frame, layoutName, point, x, y)
--   'layout': (layoutName, layoutIndex)   'enter'/'exit': ()
--   'create': (layoutName, layoutIndex, sourceLayoutName)   'rename': (old, new, index)
--   'delete': (layoutName)
-- Test helpers (on h.lem): enter(), exit(), switchLayout(name), move(frame, point, x, y),
-- drag(frame, point, x, y) (through the drag handle, so snapping runs),
-- resetPosition(frame),
-- createLayout(name, source), renameLayout(old, new), deleteLayout(name),
-- changeSetting(frame, settingName, value), clickButton(frame, text).

local function new(h)
  local env = h.env
  local lib = {
    frameSelections = {},
    frames = {}, frameOrder = {}, frameSettings = {}, frameButtons = {}, systemSettings = {},
    callbacks = { enter = {}, exit = {}, layout = {}, create = {}, rename = {}, delete = {} },
    isEditing = false, activeLayout = nil, log = {},
  }
  lib.SettingType = { Dropdown = 0, Checkbox = 1, Slider = 2, ColorPicker = 10, Divider = "divider", Expander = "expander" }

  local function layoutName(i)
    local l = h.editModeLayouts.layouts[i or lib.activeLayout or 1]
    return l and l.layoutName
  end
  local function call(fn, where, ...)
    lib.log[#lib.log + 1] = where
    return h:protectedCall(fn, "LibEditMode " .. where, ...)
  end
  local function validSetting(s, where)
    if type(s) ~= "table" then error(where .. ": setting must be a table", 3) end
    if s.kind ~= lib.SettingType.Divider and s.kind ~= lib.SettingType.Expander then
      if type(s.name) ~= "string" then error(where .. ": setting.name must be a string", 3) end
      if type(s.get) ~= "function" or type(s.set) ~= "function" then error(where .. ": setting '" .. tostring(s.name) .. "' needs get and set", 3) end
    end
    local known = false
    for _, v in pairs(lib.SettingType) do if v == s.kind then known = true end end
    if not known then error(where .. ": unknown setting kind " .. tostring(s.kind), 3) end
    if s.kind == lib.SettingType.Slider and (s.minValue == nil or s.maxValue == nil) then
      error(where .. ": slider '" .. tostring(s.name) .. "' needs minValue and maxValue", 3)
    end
    if s.kind == lib.SettingType.Dropdown and not (s.values or s.generator) then
      error(where .. ": dropdown '" .. tostring(s.name) .. "' needs values or generator", 3)
    end
  end

  function lib:AddFrame(frame, callback, default, name)
    if type(frame) ~= "table" or not h.widgets.state[frame] then error("AddFrame: frame expected", 2) end
    if type(callback) ~= "function" then error("AddFrame: callback must be a function", 2) end
    if type(default) ~= "table" or type(default.point) ~= "string" or type(default.x) ~= "number" or type(default.y) ~= "number" then
      error("AddFrame: default must be { point = string, x = number, y = number }", 2)
    end
    if lib.frames[frame] then error("AddFrame: frame registered twice", 2) end
    lib.frames[frame] = { callback = callback, default = default, name = name or frame:GetName() }
    table.insert(lib.frameOrder, frame)
    -- The drag handle, like the real library's selection frame: dragging
    -- moves the frame, and dropping it reports the frame's anchor.
    local selection = env.CreateFrame("Frame", nil, frame)
    selection:SetAllPoints()
    selection.parent = frame
    selection:SetScript("OnDragStart", function(self) self.parent:StartMoving() end)
    selection:SetScript("OnDragStop", function(self)
      local f = self.parent
      f:StopMovingOrSizing()
      local point, _, _, x, y = f:GetPoint(1)
      call(lib.frames[f].callback, "position", f, layoutName(), point, x, y)
    end)
    lib.frameSelections[frame] = selection
  end
  function lib:AddFrameSettings(frame, settings)
    if not lib.frames[frame] then error("frame must be registered", 2) end
    for _, s in ipairs(settings) do validSetting(s, "AddFrameSettings") end
    lib.frameSettings[frame] = settings
  end
  local function findSetting(frame, name)
    for _, s in ipairs(lib.frameSettings[frame] or {}) do if s.name == name then return s end end
  end
  function lib:EnableFrameSetting(frame, name) local s = findSetting(frame, name); if s then s.disabled = false end end
  function lib:DisableFrameSetting(frame, name) local s = findSetting(frame, name); if s then s.disabled = true end end
  function lib:AddFrameSettingsButton(frame, data)
    if not lib.frames[frame] then error("frame must be registered", 2) end
    if type(data) ~= "table" or type(data.text) ~= "string" or type(data.click) ~= "function" then
      error("AddFrameSettingsButton: { text = string, click = function } expected", 2)
    end
    lib.frameButtons[frame] = lib.frameButtons[frame] or {}
    table.insert(lib.frameButtons[frame], data)
  end
  function lib:AddFrameSettingsButtons(frame, buttons) for _, b in ipairs(buttons) do lib:AddFrameSettingsButton(frame, b) end end
  function lib:RefreshFrameSettings(frame) lib.log[#lib.log + 1] = "refresh" ; local _ = frame end
  function lib:AddSystemSettings(systemID, settings, sub) lib.systemSettings[#lib.systemSettings + 1] = { systemID, settings, sub } end
  function lib:AddSystemSettingsButtons() end
  function lib:EnableSystemSetting() end
  function lib:DisableSystemSetting() end
  function lib:RegisterCallback(event, callback)
    assert(type(event) == "string", "event must be a string")
    assert(type(callback) == "function", "callback must be a function")
    local list = lib.callbacks[event]
    if not list then error('invalid callback event "' .. event .. '"', 2) end
    table.insert(list, callback)
    if event == "layout" and lib.activeLayout then call(callback, "layout", layoutName(), lib.activeLayout) end
  end
  function lib:GetActiveLayout() return lib.activeLayout end
  function lib:GetActiveLayoutName() return lib.activeLayout and layoutName() end
  function lib:IsInEditMode() return lib.isEditing end
  function lib:GetFrameDefaultPosition(frame) return lib.frames[frame] and lib.frames[frame].default end

  -- harness lifecycle
  function lib:_login()
    if lib.activeLayout then return end
    lib.activeLayout = h.editModeLayouts.activeLayout
    for _, cb in ipairs(lib.callbacks.layout) do call(cb, "layout", layoutName(), lib.activeLayout) end
  end
  function lib:_enter()
    lib.isEditing = true
    for _, cb in ipairs(lib.callbacks.enter) do call(cb, "enter") end
  end
  function lib:_exit()
    lib.isEditing = false
    for _, cb in ipairs(lib.callbacks.exit) do call(cb, "exit") end
  end

  -- test helpers
  function lib:enter() return h:enterEditMode() end
  function lib:exit() return h:exitEditMode() end
  function lib:switchLayout(name)
    for i, l in ipairs(h.editModeLayouts.layouts) do
      if l.layoutName == name then
        h.editModeLayouts.activeLayout = i
        lib.activeLayout = i
        for _, cb in ipairs(lib.callbacks.layout) do call(cb, "layout", name, i) end
        return true
      end
    end
    error("no such layout " .. tostring(name), 2)
  end
  -- Drags a frame by its handle to (point, x, y) and drops it there.
  function lib:drag(frame, point, x, y)
    local selection = lib.frameSelections[frame]
    if not selection then error("drag: frame not registered with LibEditMode", 2) end
    h.widgets.callScript(selection, "OnDragStart")
    frame:ClearAllPoints()
    frame:SetPoint(point, env.UIParent, point, x, y)
    h:frame()
    h.widgets.callScript(selection, "OnDragStop")
  end
  function lib:move(frame, point, x, y)
    local f = lib.frames[frame]
    if not f then error("move: frame not registered with LibEditMode", 2) end
    if h.world.inCombat then return false end -- the real library refuses drags in combat
    frame:ClearAllPoints()
    frame:SetPoint(point, env.UIParent, point, x, y)
    call(f.callback, "position", frame, layoutName(), point, x, y)
    return true
  end
  -- The "Reset position" button in a frame's Edit Mode popup.
  function lib:resetPosition(frame)
    local f = lib.frames[frame]
    if not f then error("resetPosition: frame not registered with LibEditMode", 2) end
    local pos = f.default
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, env.UIParent, pos.point, pos.x, pos.y)
    call(f.callback, "position", frame, layoutName(), pos.point, pos.x, pos.y)
  end
  function lib:createLayout(name, source)
    table.insert(h.editModeLayouts.layouts, { layoutName = name, layoutType = 1 })
    local idx = #h.editModeLayouts.layouts
    for _, cb in ipairs(lib.callbacks.create) do call(cb, "create", name, idx, source) end
    lib:switchLayout(name)
  end
  function lib:renameLayout(old, newName)
    for i, l in ipairs(h.editModeLayouts.layouts) do
      if l.layoutName == old then
        l.layoutName = newName
        for _, cb in ipairs(lib.callbacks.rename) do call(cb, "rename", old, newName, i) end
        return
      end
    end
  end
  function lib:deleteLayout(name)
    for i, l in ipairs(h.editModeLayouts.layouts) do
      if l.layoutName == name then
        table.remove(h.editModeLayouts.layouts, i)
        for _, cb in ipairs(lib.callbacks.delete) do call(cb, "delete", name) end
        if lib.activeLayout == i then lib:switchLayout(h.editModeLayouts.layouts[1].layoutName) end
        return
      end
    end
  end
  function lib:changeSetting(frame, name, value)
    local s = findSetting(frame, name)
    if not s then error("changeSetting: no setting '" .. tostring(name) .. "'", 2) end
    call(s.set, "set " .. name, layoutName(), value)
    return s.get(layoutName())
  end
  function lib:clickButton(frame, text)
    for _, b in ipairs(lib.frameButtons[frame] or {}) do
      if b.text == text then return call(b.click, "button " .. text) end
    end
    error("clickButton: no button '" .. tostring(text) .. "'", 2)
  end

  h.lem = lib
  return lib
end

return { new = new }
