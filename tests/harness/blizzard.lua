-- tests/harness/blizzard.lua
-- FrameXML-level helpers the addon leans on: utilities, ColorMixin, class/power/debuff
-- colors, number/text helpers (secret-aware sinks), EventRegistry, StaticPopup,
-- slash commands, sounds, addon metadata, profiler, fonts and BackdropTemplate.

local Secret = require("secret")
local Api = require("api")

local B = {}

local CLASS_COLORS = {
  WARRIOR = { 0.78, 0.61, 0.43, "ffc79c6e" }, PALADIN = { 0.96, 0.55, 0.73, "fff58cba" },
  HUNTER = { 0.67, 0.83, 0.45, "ffabd473" }, ROGUE = { 1.00, 0.96, 0.41, "fffff569" },
  PRIEST = { 1.00, 1.00, 1.00, "ffffffff" }, SHAMAN = { 0.00, 0.44, 0.87, "ff0070de" },
  MAGE = { 0.25, 0.78, 0.92, "ff3fc7eb" }, WARLOCK = { 0.53, 0.53, 0.93, "ff8787ed" },
  DRUID = { 1.00, 0.49, 0.04, "ffff7d0a" },
}

function B.install(h)
  local env = h.env
  local W = h.widgets
  local raw = Secret.raw

  h.sounds, h.popupsShown, h.registryEvents, h.slashCalls = {}, {}, {}, {}
  h.modifiers = { shift = false, ctrl = false, alt = false }

  ---------------------------------------------------------------------------
  -- Table/math utilities (TableUtil.lua, MathUtil.lua, FunctionUtil.lua)
  ---------------------------------------------------------------------------
  local function CopyTable(t, shallow)
    local r = {}
    for k, v in pairs(t) do
      if type(v) == "table" and not shallow then r[k] = CopyTable(v) else r[k] = v end
    end
    return r
  end
  env.CopyTable = CopyTable
  env.tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
  env.tIndexOf = function(t, v) for i, x in ipairs(t) do if x == v then return i end end end
  env.tInvert = function(t) local r = {}; for k, v in pairs(t) do r[v] = k end; return r end
  env.tDeleteItem = function(t, v)
    local n = 0
    for i = #t, 1, -1 do if t[i] == v then table.remove(t, i); n = n + 1 end end
    return n
  end
  env.tAppendAll = function(t, src) for _, v in ipairs(src) do t[#t + 1] = v end end
  env.MergeTable = function(dst, src) for k, v in pairs(src) do dst[k] = v end; return dst end
  env.SafePack = function(...) return { n = select("#", ...), ... } end
  env.SafeUnpack = function(t) return unpack(t, 1, t.n) end
  env.Clamp = function(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
  env.Saturate = function(v) return env.Clamp(v, 0, 1) end
  env.Lerp = function(a, b, t) return a + (b - a) * t end
  env.Round = function(v) return math.floor(v + 0.5) end
  env.FormatPercentage = function(v, round) v = v * 100; if round then v = math.floor(v + 0.5) end; return v .. "%" end
  env.FormatPercentageRounded = function(v) return env.FormatPercentage(v, true) end
  env.nop = function() end
  env.GenerateClosure = function(f, ...)
    local a = { n = select("#", ...), ... }
    return function(...) local b = { ... }; local args = {}; for i = 1, a.n do args[i] = a[i] end
      for i = 1, select("#", ...) do args[a.n + i] = b[i] end; return f(unpack(args, 1, a.n + select("#", ...))) end
  end
  env.RunNextFrame = function(fn) env.C_Timer.After(0, fn) end
  env.IsShiftKeyDown = function() return h.modifiers.shift end
  env.IsControlKeyDown = function() return h.modifiers.ctrl end
  env.IsAltKeyDown = function() return h.modifiers.alt end
  env.IsModifierKeyDown = function() return h.modifiers.shift or h.modifiers.ctrl or h.modifiers.alt end
  env.GetCursorPosition = function() return 960, 540 end
  env.GetScreenWidth = function() return 1920 end
  env.GetScreenHeight = function() return 1080 end
  env.SECONDS_PER_MIN, env.SECONDS_PER_HOUR, env.SECONDS_PER_DAY = 60, 3600, 86400

  ---------------------------------------------------------------------------
  -- Colors
  ---------------------------------------------------------------------------
  local ColorMixin = {}
  function ColorMixin:OnLoad(r, g, b, a) self:SetRGBA(r, g, b, a) end
  function ColorMixin:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
  function ColorMixin:SetRGB(r, g, b) self:SetRGBA(r, g, b, nil) end
  function ColorMixin:GetRGB() return self.r, self.g, self.b end
  function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a or 1 end
  function ColorMixin:GetRGBAsBytes() return self.r * 255, self.g * 255, self.b * 255 end
  function ColorMixin:IsRGBEqualTo(o) return self.r == o.r and self.g == o.g and self.b == o.b end
  function ColorMixin:IsEqualTo(o) return self:IsRGBEqualTo(o) and (self.a or 1) == (o.a or 1) end
  function ColorMixin:GenerateHexColor()
    return string.format("ff%02x%02x%02x", math.floor(self.r * 255 + 0.5), math.floor(self.g * 255 + 0.5), math.floor(self.b * 255 + 0.5))
  end
  function ColorMixin:GenerateHexColorMarkup() return "|c" .. self:GenerateHexColor() end
  function ColorMixin:WrapTextInColorCode(text) return "|c" .. self:GenerateHexColor() .. text .. "|r" end
  env.ColorMixin = ColorMixin
  local function CreateColor(r, g, b, a)
    local c = setmetatable({}, { __index = ColorMixin })
    c:SetRGBA(r, g, b, a)
    return c
  end
  env.CreateColor = CreateColor
  env.CreateColorFromHexString = function(hex)
    if type(hex) ~= "string" or #hex ~= 8 then error("CreateColorFromHexString: expected AARRGGBB", 2) end
    local a, r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16), tonumber(hex:sub(7, 8), 16)
    return CreateColor(r / 255, g / 255, b / 255, a / 255)
  end
  env.CreateColorFromBytes = function(r, g, b, a) return CreateColor(r / 255, g / 255, b / 255, (a or 255) / 255) end
  env.WrapTextInColorCode = function(text, hex) return "|c" .. hex .. text .. "|r" end
  env.WHITE_FONT_COLOR, env.NORMAL_FONT_COLOR = CreateColor(1, 1, 1), CreateColor(1, 0.82, 0)
  env.HIGHLIGHT_FONT_COLOR, env.RED_FONT_COLOR = CreateColor(1, 1, 1), CreateColor(1, 0.1, 0.1)
  env.GREEN_FONT_COLOR, env.GRAY_FONT_COLOR = CreateColor(0.1, 1, 0.1), CreateColor(0.5, 0.5, 0.5)
  env.DISABLED_FONT_COLOR = CreateColor(0.5, 0.5, 0.5)

  local rcc = {}
  for token, c in pairs(CLASS_COLORS) do
    local col = CreateColor(c[1], c[2], c[3], 1)
    col.colorStr = c[4]
    rcc[token] = col
  end
  env.RAID_CLASS_COLORS = rcc
  env.CLASS_SORT_ORDER = { "WARRIOR", "PALADIN", "PRIEST", "SHAMAN", "DRUID", "ROGUE", "MAGE", "WARLOCK", "HUNTER" }
  local names = {}
  for token, c in pairs(h.world.CLASSES) do names[token] = c.name end
  env.LOCALIZED_CLASS_NAMES_MALE, env.LOCALIZED_CLASS_NAMES_FEMALE = names, CopyTable(names)
  env.CLASS_ICON_TCOORDS = {}
  for token in pairs(CLASS_COLORS) do env.CLASS_ICON_TCOORDS[token] = { 0, 0.25, 0, 0.25 } end

  local function pc(r, g, b) return CreateColor(r, g, b) end
  local PowerBarColor = {
    MANA = pc(0, 0, 1), RAGE = pc(1, 0, 0), FOCUS = pc(1, 0.5, 0.25), ENERGY = pc(1, 1, 0),
    HAPPINESS = pc(0, 1, 1), COMBO_POINTS = pc(1, 0.96, 0.41), RUNIC_POWER = pc(0, 0.82, 1),
  }
  PowerBarColor[0], PowerBarColor[1], PowerBarColor[2], PowerBarColor[3] = PowerBarColor.MANA, PowerBarColor.RAGE, PowerBarColor.FOCUS, PowerBarColor.ENERGY
  PowerBarColor[4], PowerBarColor[27] = PowerBarColor.COMBO_POINTS, PowerBarColor.HAPPINESS
  env.PowerBarColor = PowerBarColor
  -- Forever has no DebuffTypeColor table (the in-game manifest check reports it
  -- missing). Debuff colors come from AuraUtil, as in Forever's AuraUtil.lua.
  local debuffColors = {
    Magic = pc(0.2, 0.6, 1), Curse = pc(0.6, 0, 1), Disease = pc(0.6, 0.4, 0), Poison = pc(0, 0.6, 0),
    Bleed = pc(1, 0, 0), None = pc(0.8, 0, 0),
  }
  env.AuraUtil = env.AuraUtil or {}
  env.AuraUtil.GetAuraBorderColor = function(dispelType)
    return debuffColors[dispelType] or debuffColors.None
  end
  -- On Forever the ready check "textures" are atlas names
  -- (Blizzard_FrameXML/Mainline/ReadyCheck.lua), so only SetAtlas draws them.
  env.READY_CHECK_READY_TEXTURE = "UI-LFG-ReadyMark"
  env.READY_CHECK_NOT_READY_TEXTURE = "UI-LFG-DeclineMark"
  env.READY_CHECK_WAITING_TEXTURE = "UI-LFG-PendingMark"
  h.atlasNames = h.atlasNames or {}
  for _, name in ipairs({ "UI-LFG-ReadyMark", "UI-LFG-DeclineMark", "UI-LFG-PendingMark" }) do
    h.atlasNames[name] = true
  end
  env.FACTION_BAR_COLORS = {}
  for i = 1, 8 do env.FACTION_BAR_COLORS[i] = { r = i < 4 and 0.8 or 0, g = i >= 4 and 0.6 or 0.3, b = 0 } end

  Api.set(h, "C_ClassColor.GetClassColor", function(className)
    local c = rcc[raw(className)]
    if not c then return nil end
    if Secret.is(className) then
      return CreateColor(Secret.wrap(c.r), Secret.wrap(c.g), Secret.wrap(c.b), 1)
    end
    return CreateColor(c.r, c.g, c.b, 1)
  end)

  ---------------------------------------------------------------------------
  -- Number/text sinks: accept secrets, return secret strings
  ---------------------------------------------------------------------------
  local function abbrev(n)
    n = tonumber(n) or 0
    local a = math.abs(n)
    local s
    if a >= 1e9 then s = string.format("%.1fB", n / 1e9)
    elseif a >= 1e6 then s = string.format("%.1fM", n / 1e6)
    elseif a >= 1e4 then s = string.format("%.1fK", n / 1e3)
    else s = tostring(math.floor(n + 0.5)) end
    return (s:gsub("%.0([KMB])", "%1"))
  end
  local function breakUp(n)
    local s = tostring(math.floor((tonumber(n) or 0) + 0.5))
    local neg = s:sub(1, 1) == "-"
    if neg then s = s:sub(2) end
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (neg and "-" or "") .. s
  end
  local function sink(f)
    return function(v, ...)
      local out = f(raw(v), ...)
      if Secret.is(v) then return Secret.new("string", out) end
      return out
    end
  end
  Api.set(h, "AbbreviateNumbers", sink(abbrev))
  Api.set(h, "AbbreviateLargeNumbers", sink(abbrev))
  Api.set(h, "BreakUpLargeNumbers", sink(breakUp))
  env.C_StringUtil = env.C_StringUtil or {}
  local function defineStr(name, f)
    if h.tags.functions["C_StringUtil." .. name] then Api.set(h, "C_StringUtil." .. name, f) else env.C_StringUtil[name] = f end
  end
  defineStr("TruncateWhenZero", sink(function(n) if n == 0 then return "" end return tostring(n) end))
  defineStr("RoundToNearestString", sink(function(n) return tostring(math.floor(n + 0.5)) end))
  defineStr("FloorToNearestString", sink(function(n) return tostring(math.floor(n)) end))
  defineStr("WrapString", function(infix, prefix, suffix)
    local r = raw(infix)
    local out = (r ~= nil and r ~= "") and ((raw(prefix) or "") .. r .. (raw(suffix) or "")) or ""
    if Secret.anySecret(infix, prefix, suffix) then return Secret.new("string", out) end
    return out
  end)
  defineStr("EscapeLuaPatterns", sink(function(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end))
  defineStr("StripHyperlinks", sink(function(s) return (s:gsub("|H.-|h(.-)|h", "%1")) end))

  ---------------------------------------------------------------------------
  -- EventRegistry / EventUtil
  ---------------------------------------------------------------------------
  local registry = { callbacks = {} }
  function registry:RegisterCallback(event, fn, owner, ...)
    if type(fn) ~= "function" then error("EventRegistry:RegisterCallback: function expected", 2) end
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], { fn = fn, owner = owner or fn, args = { n = select("#", ...), ... } })
    return owner or fn
  end
  function registry:RegisterCallbackWithHandle(event, fn, owner, ...)
    local o = self:RegisterCallback(event, fn, owner, ...)
    return { Unregister = function() registry:UnregisterCallback(event, o) end }
  end
  function registry:UnregisterCallback(event, owner)
    local list = self.callbacks[event] or {}
    for i = #list, 1, -1 do if list[i].owner == owner then table.remove(list, i) end end
  end
  function registry:TriggerEvent(event, ...)
    h.registryEvents[#h.registryEvents + 1] = event
    local list = {}
    for i, cb in ipairs(self.callbacks[event] or {}) do list[i] = cb end
    for _, cb in ipairs(list) do
      local args = {}
      for i = 1, cb.args.n do args[i] = cb.args[i] end
      local n = cb.args.n
      for i = 1, select("#", ...) do args[n + i] = select(i, ...) end
      if cb.owner ~= cb.fn then
        h:protectedCall(cb.fn, "EventRegistry:" .. event, cb.owner, unpack(args, 1, n + select("#", ...)))
      else
        h:protectedCall(cb.fn, "EventRegistry:" .. event, unpack(args, 1, n + select("#", ...)))
      end
    end
  end
  function registry:RegisterFrameEventAndCallback(frameEvent, fn, owner)
    local f = env.CreateFrame("Frame")
    f:RegisterEvent(frameEvent)
    f:SetScript("OnEvent", function(_, ...) if owner then fn(owner, ...) else fn(...) end end)
    return owner or fn
  end
  env.EventRegistry = registry
  env.CallbackRegistryMixin = {
    OnLoad = function(self) self.callbacks = {} end,
    RegisterCallback = registry.RegisterCallback, UnregisterCallback = registry.UnregisterCallback,
    TriggerEvent = function(self, event, ...)
      local list = self.callbacks and self.callbacks[event] or {}
      for _, cb in ipairs(list) do h:protectedCall(cb.fn, "callback:" .. event, cb.owner, ...) end
    end,
    GenerateCallbackEvents = function(self, events) self.Event = self.Event or {}; for _, e in ipairs(events) do self.Event[e] = e end end,
  }
  env.EventUtil = {
    ContinueOnAddOnLoaded = function(addon, fn)
      local f = env.CreateFrame("Frame")
      f:RegisterEvent("ADDON_LOADED")
      f:SetScript("OnEvent", function(self, _, name) if name == addon then self:UnregisterAllEvents(); fn() end end)
    end,
    RegisterOnceFrameEventAndCallback = function(event, fn)
      local f = env.CreateFrame("Frame")
      f:RegisterEvent(event)
      f:SetScript("OnEvent", function(self, ...) self:UnregisterAllEvents(); fn(...) end)
    end,
  }

  ---------------------------------------------------------------------------
  -- StaticPopup
  ---------------------------------------------------------------------------
  env.StaticPopupDialogs = {}
  env.StaticPopup_Show = function(which, text1, text2, data)
    local info = env.StaticPopupDialogs[which]
    if not info then return nil end
    if info.hideOnEscape == nil then h:warn("StaticPopup '" .. which .. "' without hideOnEscape") end
    local dialog = env.CreateFrame("Frame", nil, env.UIParent)
    dialog.which, dialog.data = which, data
    dialog.editBox = env.CreateFrame("EditBox", nil, dialog)
    dialog.EditBox = dialog.editBox
    dialog.GetEditBox = function(self) return self.editBox end
    dialog.text1, dialog.text2 = text1, text2
    h.popupsShown[#h.popupsShown + 1] = dialog
    if info.OnShow then h:protectedCall(info.OnShow, "StaticPopup:" .. which, dialog, data) end
    return dialog
  end
  env.StaticPopup_Hide = function(which)
    for _, d in ipairs(h.popupsShown) do if d.which == which then d:Hide() end end
  end
  env.StaticPopup_Visible = function(which)
    for _, d in ipairs(h.popupsShown) do if d.which == which and d:IsShown() then return d end end
  end
  -- test helper: press button1 (accept) on the latest dialog of this kind
  function h:acceptPopup(which, text)
    for i = #self.popupsShown, 1, -1 do
      local d = self.popupsShown[i]
      if d.which == which and d:IsShown() then
        if text then d.editBox:SetText(text) end
        local info = env.StaticPopupDialogs[which]
        if info.OnAccept then self:protectedCall(info.OnAccept, "StaticPopup:" .. which, d, d.data) end
        d:Hide()
        return true
      end
    end
    return false
  end

  ---------------------------------------------------------------------------
  -- Slash commands (ChatEdit_ParseText behaviour)
  ---------------------------------------------------------------------------
  env.SlashCmdList = {}
  env.hash_SlashCmdList = {}
  function h:slash(line)
    local cmd, rest = line:match("^(/%S+)%s*(.-)$")
    cmd = cmd:upper()
    for key, fn in pairs(env.SlashCmdList) do
      local i = 1
      while env["SLASH_" .. key .. i] do
        if env["SLASH_" .. key .. i]:upper() == cmd then
          env.hash_SlashCmdList[cmd] = fn
          self.slashCalls[#self.slashCalls + 1] = line
          self:protectedCall(fn, "slash " .. cmd, rest, nil)
          return true
        end
        i = i + 1
      end
    end
    return false
  end

  ---------------------------------------------------------------------------
  -- Sounds
  ---------------------------------------------------------------------------
  env.SOUNDKIT = {
    IG_CREATURE_AGGRO_SELECT = 873, IG_CHARACTER_NPC_SELECT = 867, IG_CREATURE_NEUTRAL_SELECT = 871,
    INTERFACE_SOUND_LOST_TARGET_UNIT = 684, IG_PVP_UPDATE = 4574, IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
    IG_MAINMENU_OPTION_CHECKBOX_OFF = 857, U_CHAT_SCROLL_BUTTON = 1115, READY_CHECK = 8960, RAID_WARNING = 8959,
    IG_MAINMENU_OPEN = 850, IG_MAINMENU_CLOSE = 851, IG_QUEST_LIST_OPEN = 875, ALARM_CLOCK_WARNING_3 = 12889,
    UI_RAID_BOSS_WHISPER_WARNING = 37666, PVP_THROUGH_QUEUE = 8459, IG_SPELLBOOK_OPEN = 829, IG_SPELLBOOK_CLOSE = 830,
  }
  local function playSound(id, channel)
    if id == nil then error("PlaySound: soundKitID is nil (unknown SOUNDKIT key?)", 2) end
    h.sounds[#h.sounds + 1] = { id = id, channel = channel }
    return true, #h.sounds
  end
  Api.set(h, "PlaySound", playSound)
  env.PlaySoundFile = function(path) h.sounds[#h.sounds + 1] = { file = path }; return true end

  ---------------------------------------------------------------------------
  -- AddOns, profiler, misc documented helpers with real behaviour
  ---------------------------------------------------------------------------
  local function meta(addon, field)
    local a = h.addon
    if a and (addon == a.name or addon == 1) then return a.meta[field] or a.meta[field:lower()] end
  end
  Api.set(h, "C_AddOns.GetAddOnMetadata", meta)
  Api.set(h, "C_AddOns.IsAddOnLoaded", function(addon)
    local loaded = h.addon and addon == h.addon.name
    return loaded and true or false, loaded and true or false
  end)
  Api.set(h, "C_AddOns.DoesAddOnExist", function(addon) return h.addon ~= nil and addon == h.addon.name end)
  Api.set(h, "C_AddOnProfiler.IsEnabled", function() return true end)
  Api.set(h, "C_AddOnProfiler.MeasureCall", function(fn, ...)
    local t0, m0 = os.clock(), collectgarbage("count")
    local res = { pcall(fn, ...) }
    local elapsed, alloc = (os.clock() - t0) * 1000, math.max(0, (collectgarbage("count") - m0) * 1024)
    if not res[1] then h:dispatchError(res[2], "C_AddOnProfiler.MeasureCall") end
    return { elapsedMilliseconds = elapsed, allocatedBytes = alloc, deallocatedBytes = 0 }, unpack(res, 2, table.maxn(res))
  end)
  Api.set(h, "InCombatLockdown", function() return h.world.inCombat end)
  Api.set(h, "C_EventUtils.IsEventValid", function(ev) return h.tags.events[ev] ~= nil or W.EXTRA_EVENTS[ev] == true end)
  Api.set(h, "C_XMLUtil.GetTemplateInfo", function(name)
    local t = W.templates[name] or h.blizzardTemplates[name]
    if not t then return nil end
    return { type = t.type or t.objType or "Frame", width = t.size and t.size.x or 0, height = t.size and t.size.y or 0, keyValues = {}, inherits = t.inherits }
  end)
  Api.set(h, "C_Texture.GetAtlasInfo", function(atlas)
    if h.knownAtlases and not h.knownAtlases[atlas] then return nil end
    return { width = 16, height = 16, file = 1, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 }
  end)
  env.GetFileIDFromPath = function(path) if type(path) ~= "string" then return nil end return 100000 + #path end

  ---------------------------------------------------------------------------
  -- Fonts
  ---------------------------------------------------------------------------
  W.impl.Font = {
    GetFont = function(self) local s = W.st(self); return s.font, s.fontSize, s.fontFlags end,
    SetFont = function(self, path, size, flags) local s = W.st(self); s.font, s.fontSize, s.fontFlags = path, size, flags; return true end,
    SetFontObject = function(self, fo) local s = W.st(self); if fo and fo.GetFont then s.font, s.fontSize, s.fontFlags = fo:GetFont() end end,
    CopyFontObject = function(self, fo) W.impl.Font.SetFontObject(self, type(fo) == "string" and env[fo] or fo) end,
    SetTextColor = function(self, ...) W.st(self).textColor = { ... } end,
    GetTextColor = function(self) local c = W.st(self).textColor or { 1, 1, 1, 1 }; return unpack(c) end,
    SetShadowColor = function() end, SetShadowOffset = function() end,
    SetJustifyH = function() end, SetJustifyV = function() end, SetSpacing = function() end,
    GetName = function(self) return W.st(self).name end,
  }
  local function CreateFont(name, size)
    local obj, st = W.newObject("Font", "font", name, nil)
    st.font, st.fontSize, st.fontFlags = "Fonts\\FRIZQT__.TTF", size or 12, ""
    return obj
  end
  env.CreateFont = function(name) return CreateFont(name, 12) end
  for name, size in pairs({ GameFontNormal = 12, GameFontHighlight = 12, GameFontNormalSmall = 10,
    GameFontHighlightSmall = 10, GameFontDisable = 12, GameFontDisableSmall = 10, GameFontNormalLarge = 16,
    GameFontHighlightLarge = 16, GameFontWhite = 12, GameFontRed = 12, GameFontGreen = 12, GameFontNormalMed3 = 14,
    NumberFontNormal = 14, NumberFontNormalSmall = 12, NumberFontNormalLarge = 16, NumberFont_Outline_Med = 13,
    NumberFont_Shadow_Small = 12, SystemFont_Shadow_Small = 10, SystemFont_Shadow_Med1 = 12, SystemFont_Outline_Small = 10,
    TextStatusBarText = 10, Tooltip_Med = 12, GameTooltipText = 12, GameTooltipTextSmall = 10, ChatFontNormal = 14,
    GameFontNormalTiny = 9, GameFontHighlightTiny = 9 }) do
    CreateFont(name, size)
  end
  env.STANDARD_TEXT_FONT, env.UNIT_NAME_FONT, env.DAMAGE_TEXT_FONT = "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT__.TTF"

  ---------------------------------------------------------------------------
  -- BackdropTemplate
  ---------------------------------------------------------------------------
  local Backdrop = {}
  function Backdrop:SetBackdrop(info)
    W.st(self).backdrop = info and CopyTable(info) or nil
    if info and info.edgeSize and info.edgeSize < 0 then error("SetBackdrop: negative edgeSize", 2) end
  end
  function Backdrop:GetBackdrop() local b = W.st(self).backdrop; return b and CopyTable(b) end
  function Backdrop:ApplyBackdrop() end
  function Backdrop:ClearBackdrop() W.st(self).backdrop = nil end
  function Backdrop:SetBackdropColor(r, g, b, a) W.st(self).backdropColor = { raw(r), raw(g), raw(b), raw(a) or 1 } end
  function Backdrop:GetBackdropColor() local c = W.st(self).backdropColor or { 1, 1, 1, 1 }; return unpack(c) end
  function Backdrop:SetBackdropBorderColor(r, g, b, a) W.st(self).backdropBorderColor = { raw(r), raw(g), raw(b), raw(a) or 1 } end
  function Backdrop:GetBackdropBorderColor() local c = W.st(self).backdropBorderColor or { 1, 1, 1, 1 }; return unpack(c) end
  function Backdrop:OnBackdropLoaded() end
  function Backdrop:OnBackdropSizeChanged() end
  env.BackdropTemplateMixin = Backdrop
  W.templates.BackdropTemplate = { name = "BackdropTemplate", type = "Frame", mixin = "BackdropTemplateMixin" }
  env.BACKDROP_TOOLTIP_16_16_5555 = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileEdge = true, tileSize = 16, edgeSize = 16, insets = { left = 5, right = 5, top = 5, bottom = 5 },
  }
  W.templates.CooldownFrameTemplate = { name = "CooldownFrameTemplate", type = "Cooldown" }
  W.templates.UIPanelButtonTemplate = { name = "UIPanelButtonTemplate", type = "Button" }
  W.templates.DisableUntrustedLayoutScriptsTemplate = { name = "DisableUntrustedLayoutScriptsTemplate", type = "Frame" }
  -- FrameXML: Blizzard_FrameXMLUtil/Mainline/DifficultyUtil.lua
  env.GetCreatureDifficultyColor = function(level)
    local diff = (level or 0) - (env.UnitLevel and env.UnitLevel("player") or 60)
    if diff >= 5 then return { r = 1, g = 0.1, b = 0.1 }
    elseif diff >= 3 then return { r = 1, g = 0.5, b = 0.25 }
    elseif diff >= -2 then return { r = 1, g = 1, b = 0 }
    elseif diff >= -8 then return { r = 0.25, g = 0.75, b = 0.25 }
    end
    return { r = 0.5, g = 0.5, b = 0.5 }
  end

end

return B
