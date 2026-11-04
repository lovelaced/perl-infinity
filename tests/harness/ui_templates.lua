-- tests/harness/ui_templates.lua
-- Stand-ins for the Blizzard UI templates Perl Infinity's options window is built
-- from (the Settings panel's frame, checkbox, slider and dropdown, search box,
-- color swatch, scroll bar), plus C_EncodingUtil for profile export. They
-- create the child keys and methods Perl Infinity uses, and record what was set, so
-- the window can be exercised offline. Real look and behaviour are checked in
-- game (self-test screenshots).

local U = {}

function U.install(h)
  local env = h.env
  local W = h.widgets

  local function template(name, frameType, apply)
    W.templates[name] = { name = name, type = frameType, apply = apply }
  end

  -- Callback registry used by the slider and dropdown stand-ins.
  local function AddCallbacks(obj)
    obj.callbacks = {}
    function obj:RegisterCallback(event, fn, owner)
      self.callbacks[#self.callbacks + 1] = { event = event, fn = fn, owner = owner }
    end
    function obj:TriggerEvent(event, ...)
      for _, cb in ipairs(self.callbacks) do
        if cb.event == event then
          h:protectedCall(cb.fn, "callback " .. tostring(event), cb.owner, ...)
        end
      end
    end
  end

  template("SettingsFrameTemplate", "Frame", function(obj)
    obj.Bg = env.CreateFrame("Frame", nil, obj)
    obj.NineSlice = env.CreateFrame("Frame", nil, obj)
    obj.NineSlice.Text = obj.NineSlice:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    obj.ClosePanelButton = env.CreateFrame("Button", nil, obj)
  end)

  template("SearchBoxTemplate", "EditBox", function(obj)
    obj.Instructions = obj:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  end)

  template("InsetFrameTemplate", "Frame")

  template("PanelResizeButtonTemplate", "Button", function(obj)
    function obj:Init(target, minWidth, minHeight, maxWidth, maxHeight)
      self.target, self.minWidth, self.minHeight, self.maxWidth, self.maxHeight = target, minWidth, minHeight, maxWidth, maxHeight
    end
    function obj:SetMinWidth(width) self.minWidth = width end
    function obj:SetMinHeight(height) self.minHeight = height end
    -- Test helper: drag the grip to a new size, as a mouse would.
    function obj:DragTo(width, height)
      self.target:SetSize(math.max(width, self.minWidth or 0), math.max(height, self.minHeight or 0))
      if self.resizeStoppedCallback then
        h:protectedCall(self.resizeStoppedCallback, "resize stopped", self.target)
      end
    end
  end)
  template("MinimalScrollBar", "Frame")

  template("SettingsCheckboxTemplate", "CheckButton")

  template("ColorSwatchTemplate", "Frame", function(obj)
    obj.Color = obj:CreateTexture(nil, "BACKGROUND")
    obj.SwatchBg = obj:CreateTexture(nil, "BACKGROUND")
  end)

  env.MinimalSliderWithSteppersMixin = {
    Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 },
    Event = { OnValueChanged = "OnValueChanged" },
  }
  template("MinimalSliderWithSteppersTemplate", "Frame", function(obj)
    AddCallbacks(obj)
    obj.Slider = env.CreateFrame("Slider", nil, obj)
    function obj:Init(value, minValue, maxValue, steps, formatters)
      self.minValue, self.maxValue, self.steps, self.formatters = minValue, maxValue, steps, formatters
      self:SetValue(value)
    end
    function obj:SetValue(value)
      self.value = value
      local format = self.formatters and self.formatters[env.MinimalSliderWithSteppersMixin.Label.Right]
      if format then
        self.label = format(value)
      end
      self:TriggerEvent("OnValueChanged", value)
    end
    function obj:GetValue()
      return self.value
    end
    function obj:SetEnabled(enabled)
      self.enabled = enabled
    end
  end)

  -- A dropdown that runs the menu generator against a recording menu.
  local function MakeDropdown(obj)
    AddCallbacks(obj)
    obj.entries = {}
    local function Root()
      local root = {}
      function root:CreateRadio(text, isSelected, setSelected, value)
        obj.entries[#obj.entries + 1] = { kind = "radio", text = text, isSelected = isSelected, setSelected = setSelected, value = value }
      end
      function root:CreateCheckbox(text, isSelected, setSelected, value)
        obj.entries[#obj.entries + 1] = { kind = "checkbox", text = text, isSelected = isSelected, setSelected = setSelected, value = value }
      end
      function root:CreateButton(text, fn)
        obj.entries[#obj.entries + 1] = { kind = "button", text = text, fn = fn }
      end
      return root
    end
    function obj:SetupMenu(generator)
      self.generator = generator
      self:GenerateMenu()
    end
    function obj:GenerateMenu()
      self.entries = {}
      if self.generator then
        h:protectedCall(self.generator, "dropdown generator", self, Root())
      end
      if self.selectionText then
        self.text = self.selectionText({})
      end
    end
    function obj:SetSelectionText(fn)
      self.selectionText = fn
    end
    -- Test helper: pick the nth entry as a click would.
    function obj:PickEntry(index)
      local entry = self.entries[index]
      if entry and entry.setSelected then
        h:protectedCall(entry.setSelected, "dropdown pick", entry.value)
        self:GenerateMenu()
      end
    end
  end

  template("WowStyle2DropdownTemplate", "DropdownButton", MakeDropdown)
  template("WowStyle1DropdownTemplate", "DropdownButton", MakeDropdown)
  template("SettingsDropdownWithButtonsTemplate", "Frame", function(obj)
    obj.Dropdown = env.CreateFrame("Frame", nil, obj)
    MakeDropdown(obj.Dropdown)
    obj.DecrementButton = env.CreateFrame("Button", nil, obj)
    obj.IncrementButton = env.CreateFrame("Button", nil, obj)
    function obj:SetEnabled(enabled)
      self.enabled = enabled
    end
  end)

  env.ScrollUtil = env.ScrollUtil or {}
  env.ScrollUtil.InitScrollFrameWithScrollBar = function(scrollFrame, scrollBar)
    scrollFrame.scrollBar = scrollBar
  end

  env.TextureKitConstants = env.TextureKitConstants or { UseAtlasSize = true, IgnoreAtlasSize = false }
  env.UISpecialFrames = env.UISpecialFrames or {}
  for _, name in ipairs({ "CLOSE", "CANCEL", "DELETE", "RESET", "OKAY", "ACCEPT" }) do
    env[name] = env[name] or name:sub(1, 1) .. name:sub(2):lower()
  end
  for _, key in ipairs({ "IG_MAINMENU_OPEN", "IG_MAINMENU_CLOSE", "IG_MAINMENU_OPTION_CHECKBOX_ON",
    "IG_MAINMENU_OPTION_CHECKBOX_OFF", "IG_CREATURE_AGGRO_SELECT", "IG_CHARACTER_NPC_SELECT",
    "IG_CREATURE_NEUTRAL_SELECT", "INTERFACE_SOUND_LOST_TARGET_UNIT", "IG_PVP_UPDATE" }) do
    env.SOUNDKIT[key] = env.SOUNDKIT[key] or (#key * 7)
  end

  ---------------------------------------------------------------------------
  -- C_EncodingUtil: a round-trippable stand-in (Lua source instead of CBOR,
  -- no compression, real base64).
  ---------------------------------------------------------------------------
  local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local function encode64(data)
    return ((data:gsub(".", function(x)
      local r, b = "", x:byte()
      for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
      return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
      if #x < 6 then return "" end
      local c = 0
      for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
      return B64:sub(c + 1, c + 1)
    end) .. ({ "", "==", "=" })[#data % 3 + 1])
  end
  local function decode64(data)
    data = data:gsub("[^" .. B64 .. "=]", "")
    return (data:gsub(".", function(x)
      if x == "=" then return "" end
      local r, f = "", (B64:find(x, 1, true) - 1)
      for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0") end
      return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
      if #x ~= 8 then return "" end
      local c = 0
      for i = 1, 8 do c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0) end
      return string.char(c)
    end))
  end
  local function serialize(value)
    local kind = type(value)
    if kind == "table" then
      local parts = {}
      for k, v in pairs(value) do
        parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(v)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    elseif kind == "string" then
      return string.format("%q", value)
    end
    return tostring(value)
  end
  env.C_EncodingUtil = {
    SerializeCBOR = function(value) return serialize(value) end,
    DeserializeCBOR = function(text)
      local fn = loadstring("return " .. text)
      if not fn then error("DeserializeCBOR: bad input", 2) end
      setfenv(fn, {})
      return fn()
    end,
    CompressString = function(text) return text end,
    DecompressString = function(text) return text end,
    EncodeBase64 = function(text) return encode64(text) end,
    DecodeBase64 = function(text) return decode64(text) end,
  }
  env.Enum.CompressionMethod = env.Enum.CompressionMethod or { Deflate = 0, Zlib = 1, Gzip = 2 }
end

return U
