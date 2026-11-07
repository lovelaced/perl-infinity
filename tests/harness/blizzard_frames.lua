-- tests/harness/blizzard_frames.lua
-- Blizzard UI objects the addon touches: default unit frames (secure, so hiding them
-- in combat is blocked), cast bars, buff frames, compact frames, EditModeManagerFrame,
-- AddonCompartmentFrame, GameTooltip, chat frame, ColorPickerFrame, menus, panels.

local Secret = require("secret")

local F = {}

function F.install(h)
  local env = h.env
  local W = h.widgets
  local UIParent = env.UIParent
  h.chatLines, h.compartment, h.menus, h.panels = {}, {}, {}, {}

  local function frame(name, template, parent, objType)
    local f = env.CreateFrame(objType or "Frame", name, parent or UIParent, template)
    W.st(f).blizzard = true
    return f
  end
  local function unitFrame(name, unit)
    local f = frame(name, "SecureUnitButtonTemplate", UIParent, "Button")
    W.st(f).attributes.unit = unit
    f.healthbar = frame(nil, nil, f, "StatusBar")
    f.manabar = frame(nil, nil, f, "StatusBar")
    f.spellbar = frame(nil, nil, f, "StatusBar")
    f.totFrame = nil
    f:RegisterEvent("UNIT_HEALTH")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:SetRolesets("unitFrames")
    return f
  end
  env.PlayerFrame = unitFrame("PlayerFrame", "player")
  env.TargetFrame = unitFrame("TargetFrame", "target")
  env.FocusFrame = unitFrame("FocusFrame", "focus")
  env.PetFrame = unitFrame("PetFrame", "pet")
  env.TargetFrameToT = unitFrame("TargetFrameToT", "targettarget")
  env.TargetFrame.totFrame = env.TargetFrameToT
  env.FocusFrame.totFrame = unitFrame("FocusFrameToT", "focustarget")
  env.TotemFrame = frame("TotemFrame", nil, env.PlayerFrame)
  env.ComboFrame = frame("ComboFrame", nil, env.TargetFrame)
  env.PartyFrame = frame("PartyFrame")
  local members = {}
  for i = 1, 4 do members[i] = unitFrame("PartyMemberFrame" .. i, "party" .. i); members[i]:SetParent(env.PartyFrame) end
  env.PartyFrame.PartyMemberFramePool = { EnumerateActive = function() local i = 0
    return function() i = i + 1; local m = members[i]; if m then return m, true end end end }
  env.CompactPartyFrame = frame("CompactPartyFrame", nil, env.PartyFrame)
  for i = 1, 5 do env["CompactPartyFrameMember" .. i] = unitFrame("CompactPartyFrameMember" .. i, i == 1 and "player" or ("party" .. (i - 1))) end
  env.CompactRaidFrameManager = frame("CompactRaidFrameManager")
  env.CompactRaidFrameContainer = frame("CompactRaidFrameContainer")
  env.CompactRaidFrameManager_SetSetting = function(k, v) h:warn("CompactRaidFrameManager_SetSetting(" .. tostring(k) .. ") persists the user's setting") end
  env.BossTargetFrameContainer = frame("BossTargetFrameContainer")
  env.BuffFrame = frame("BuffFrame")
  env.DebuffFrame = frame("DebuffFrame")
  env.BuffFrame:RegisterEvent("UNIT_AURA")
  env.DebuffFrame:RegisterEvent("UNIT_AURA")
  env.PlayerCastingBarFrame = frame("PlayerCastingBarFrame", nil, UIParent, "StatusBar")
  env.PetCastingBarFrame = frame("PetCastingBarFrame", nil, UIParent, "StatusBar")
  env.PlayerCastingBarFrame:RegisterEvent("UNIT_SPELLCAST_START")
  env.MinimapCluster = frame("MinimapCluster")
  env.Minimap = frame("Minimap", nil, env.MinimapCluster)

  ---------------------------------------------------------------------------
  -- Edit Mode
  ---------------------------------------------------------------------------
  local emm = frame("EditModeManagerFrame")
  emm:Hide()
  emm.IsEditModeActive = function(self) return self:IsShown() end
  emm.ClearSelectedSystem = function() end
  emm.EnterEditMode = function(self) h:enterEditMode() end
  emm.ExitEditMode = function(self) h:exitEditMode() end
  -- Edit Mode's "Snap" option, on by default as in the game.
  emm.snapEnabled = true
  emm.IsSnapEnabled = function(self) return self.snapEnabled end
  env.EditModeManagerFrame = emm
  -- Blizzard's snapping state: frames to snap to, and grid lines while the
  -- grid shows (absolute positions in UIParent units).
  env.EditModeMagnetismManager = { magneticFrames = {}, magneticGridLines = nil }
  h.editModeLayouts = { activeLayout = 1, layouts = { { layoutName = "Modern", layoutType = 0 }, { layoutName = "Classic", layoutType = 0 } } }
  env.C_EditMode = env.C_EditMode or {}
  env.C_EditMode.GetLayouts = function() return h.editModeLayouts end
  env.CanEnterEditMode = function() return not h.world.inCombat end
  function h:enterEditMode()
    if self.world.inCombat then self:blockedAction("EnterEditMode"); return false end
    W.withVisibility(emm, function() W.st(emm).shown = true end)
    env.EventRegistry:TriggerEvent("EditMode.Enter")
    if self.lem then self.lem:_enter() end
    return true
  end
  function h:exitEditMode()
    W.withVisibility(emm, function() W.st(emm).shown = false end)
    env.EventRegistry:TriggerEvent("EditMode.Exit")
    if self.lem then self.lem:_exit() end
  end
  env.ShowUIPanel = function(f)
    if f == emm then return h:enterEditMode() end
    h.panels[#h.panels + 1] = f
    if f and f.Show then f:Show() end
  end
  env.HideUIPanel = function(f)
    if f == emm then return h:exitEditMode() end
    if f and f.Hide then f:Hide() end
  end

  ---------------------------------------------------------------------------
  -- Addon Compartment
  ---------------------------------------------------------------------------
  local acf = frame("AddonCompartmentFrame")
  acf.registeredAddons = {}
  acf.RegisterAddon = function(self, info) table.insert(self.registeredAddons, info); h.compartment[#h.compartment + 1] = info end
  acf.UnregisterAddon = function() end
  env.AddonCompartmentFrame = acf

  ---------------------------------------------------------------------------
  -- Tooltip, chat, color picker, menus
  ---------------------------------------------------------------------------
  env.GameTooltip = env.CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate")
  env.GameTooltip:Hide()
  env.GameTooltip_SetDefaultAnchor = function(tt, parent) tt:SetOwner(parent, "ANCHOR_NONE") end
  env.GameTooltip_Hide = function() env.GameTooltip:Hide() end
  -- SharedTooltipTemplates' line helpers, which all end in AddLine.
  local function lineHelper(r, g, b)
    return function(tt, text, wrap) tt:AddLine(text, r, g, b, wrap) end
  end
  env.GameTooltip_SetTitle = function(tt, text, color, wrap) tt:SetText(text) end
  env.GameTooltip_AddNormalLine = lineHelper(1, 0.82, 0)
  env.GameTooltip_AddHighlightLine = lineHelper(1, 1, 1)
  env.GameTooltip_AddErrorLine = lineHelper(1, 0.13, 0.13)
  env.GameTooltip_AddInstructionLine = lineHelper(0, 1, 0)
  env.GameTooltip_AddDisabledLine = lineHelper(0.5, 0.5, 0.5)
  env.GameTooltip_AddColoredLine = function(tt, text, color, wrap) tt:AddLine(text, nil, nil, nil, wrap) end
  env.GameTooltip_AddBlankLineToTooltip = function(tt) tt:AddLine(" ") end
  env.TooltipDataProcessor = { AddTooltipPostCall = function() end, AllTypes = "ALL" }
  env.Enum.TooltipDataType = env.Enum.TooltipDataType or { Unit = 2, Spell = 1, Item = 0 }

  local chat = frame("ChatFrame1")
  chat.AddMessage = function(_, text, r, g, b)
    h.chatLines[#h.chatLines + 1] = tostring(Secret.raw(text))
    h.printed[#h.printed + 1] = tostring(Secret.raw(text))
    if h.verbose then io.write("[chat] ", tostring(Secret.raw(text)), "\n") end
  end
  env.DEFAULT_CHAT_FRAME = chat
  env.SELECTED_CHAT_FRAME = chat

  local cp = frame("ColorPickerFrame")
  cp:Hide()
  cp.SetupColorPickerAndShow = function(self, info) self.info = info; self:Show() end
  cp.GetColorRGB = function(self) local i = self.info or {}; return i.r or 1, i.g or 1, i.b or 1 end
  cp.GetColorAlpha = function(self) return (self.info and self.info.opacity) or 1 end
  cp.GetPreviousValues = function(self) local i = self.info or {}; return i.r or 1, i.g or 1, i.b or 1, i.opacity end
  env.ColorPickerFrame = cp

  env.MenuUtil = {
    CreateContextMenu = function(owner, generator)
      local root = { items = {} }
      local function node(t)
        return setmetatable(t, { __index = {
          CreateButton = function(self, text, fn) local n = node({ kind = "button", text = text, fn = fn, items = {} }); table.insert(self.items, n); return n end,
          CreateCheckbox = function(self, text, isSel, setSel) local n = node({ kind = "checkbox", text = text, isSelected = isSel, setSelected = setSel, items = {} }); table.insert(self.items, n); return n end,
          CreateRadio = function(self, text, isSel, setSel) local n = node({ kind = "radio", text = text, isSelected = isSel, setSelected = setSel, items = {} }); table.insert(self.items, n); return n end,
          CreateTitle = function(self, text) local n = node({ kind = "title", text = text, items = {} }); table.insert(self.items, n); return n end,
          CreateDivider = function(self) table.insert(self.items, { kind = "divider" }) end,
          SetTooltip = function(self, fn) self.tooltip = fn end,
          SetEnabled = function(self, v) self.enabled = v end,
        } })
      end
      node(root)
      h:protectedCall(generator, "MenuUtil generator", owner, root)
      h.menus[#h.menus + 1] = root
      return root
    end,
  }

  ---------------------------------------------------------------------------
  -- UnitFrameUtil secure delegates (accept secrets; record what they would show)
  ---------------------------------------------------------------------------
  env.UnitFrameUtil = {
    UpdateUnitPvPIndicator = function(elements, unit) if elements and elements.pvpIcon then elements.pvpIcon.__pvpUnit = unit end end,
    GetUnitPvPIndicatorDisplayInfo = function() return nil end,
    GetUnitRoleIconDisplayInfo = function(unit, options)
      local role = env.UnitGroupRolesAssigned(unit)
      local show = Secret.is(role) and Secret.wrap(Secret.raw(role) ~= "NONE") or role ~= "NONE"
      return { texture = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES", atlas = nil, show = show, role = role, options = options }
    end,
    UpdateUnitFrameRoleIcon = function() end,
  }
end

return F
