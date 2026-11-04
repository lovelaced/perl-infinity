-- Rows for the options window, built from the same templates Blizzard's own
-- Settings panel uses (minimal checkbox, slider with steppers, dropdown with
-- steppers, color swatch, panel buttons) and laid out the same way: label on
-- the left, control from the middle, a faint highlight under the mouse, and
-- a tooltip that explains the setting. Unlike the Settings panel, the label
-- always gets room for its text: the controls move right to make space, and
-- a label that still doesn't fit wraps onto a second line.
--
-- Each row wraps one option from Options/Pages.lua. Rows read and write
-- settings through Config, so the window, Edit Mode popups and frames agree.
local _, ns = ...

local Widgets = {}
ns.OptionWidgets = Widgets

local Config = ns.Config
local L = ns.L

local ROW_HEIGHT = 26
local HEADER_HEIGHT = 45
local LABEL_X = 37
local LABEL_MIN_WIDTH = 200
-- Where controls start: the middle of the row less 80, as in the Settings
-- panel, but never closer to the label than this.
local CONTROL_MIN_X = LABEL_X + LABEL_MIN_WIDTH + 12
-- The widest control (dropdown with steppers) ends this far past CONTROL_MIN_X.
local CONTROL_SPAN = 320
Widgets.ROW_HEIGHT = ROW_HEIGHT
Widgets.MIN_WIDTH = CONTROL_MIN_X + CONTROL_SPAN

---------------------------------------------------------------------------
-- Copy lookup: every label and tooltip lives in Locale/enUS.lua.
---------------------------------------------------------------------------

function Widgets.Copy(option)
	local copy = L.Options[option.key or option.path] or {}
	return copy[1] or option.key or option.path, copy[2]
end

function Widgets.ChoiceCopy(option, value)
	local choices = L.Choices[option.key or option.path] or {}
	local entry = choices[value]
	if type(entry) == "table" then
		return entry[1], entry[2]
	end
	return entry or tostring(value), nil
end

-- A dropdown's choices: a list, or a function that builds one (bar textures
-- pick up other addons' media, profiles change as you add them).
function Widgets.Choices(option)
	local choices = option.choices
	if type(choices) == "function" then
		choices = choices()
	end
	return choices or {}
end

-- Most rows edit a setting by path; a few (profiles) bring their own get/set.
local function Get(option)
	if option.get then
		return option.get()
	end
	return Config:Get(option.path)
end

local function Set(option, value)
	if option.set then
		option.set(value)
	else
		Config:Set(option.path, value)
	end
end

---------------------------------------------------------------------------
-- Base row
---------------------------------------------------------------------------

local function ShowTooltip(row)
	local label, tooltip = Widgets.Copy(row.option)
	GameTooltip:SetOwner(row, "ANCHOR_NONE")
	GameTooltip:SetPoint("LEFT", row, "RIGHT", -60, 0)
	GameTooltip_SetTitle(GameTooltip, label)
	if tooltip then
		GameTooltip_AddNormalLine(GameTooltip, tooltip, true)
	end
	if row.option.type == "dropdown" then
		for _, value in ipairs(Widgets.Choices(row.option)) do
			local choiceLabel, choiceTip
			if type(value) ~= "table" then
				choiceLabel, choiceTip = Widgets.ChoiceCopy(row.option, value)
			end
			if choiceTip then
				GameTooltip_AddBlankLineToTooltip(GameTooltip)
				GameTooltip_AddHighlightLine(GameTooltip, choiceLabel)
				GameTooltip_AddNormalLine(GameTooltip, choiceTip, true)
			end
		end
	end
	if not row.enabled and row.option.disabledReason then
		GameTooltip_AddBlankLineToTooltip(GameTooltip)
		GameTooltip_AddErrorLine(GameTooltip, L[row.option.disabledReason] or row.option.disabledReason, true)
	end
	GameTooltip:Show()
end

local function OnEnter(row)
	row.Hover:Show()
	ShowTooltip(row)
end

local function OnLeave(row)
	row.Hover:Hide()
	GameTooltip:Hide()
end

local function CreateRow(parent, option, height)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(height or ROW_HEIGHT)
	row.option = option
	row.enabled = true

	local hover = row:CreateTexture(nil, "BACKGROUND")
	hover:SetColorTexture(1, 1, 1, 0.1)
	hover:SetPoint("TOPLEFT", 10, 0)
	hover:SetPoint("BOTTOMRIGHT", -5, 0)
	hover:Hide()
	row.Hover = hover

	local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetJustifyH("LEFT")
	text:SetWordWrap(true)
	text:SetMaxLines(2)
	text:SetPoint("LEFT", LABEL_X, 0)
	text:SetText((Widgets.Copy(option)))
	row.Text = text

	row:EnableMouse(true)
	row:SetScript("OnEnter", OnEnter)
	row:SetScript("OnLeave", OnLeave)
	return row
end

-- Remembers a row's control and its offset from the control column. The
-- offsets match where Blizzard's Settings panel puts each kind of control.
local function SetControl(row, control, dx, dy)
	row.Control = control
	row.controlX, row.controlY = dx or 0, dy or 0
end

-- Fits a row to the list's width: controls start at the middle less 80 (or
-- further right if the label needs it), the label fills the space before
-- them, and the row grows if the label wraps.
function Widgets.Layout(row, width)
	if not row.Control then
		return
	end
	local x = math.max(width / 2 - 80, CONTROL_MIN_X)
	row.Control:ClearAllPoints()
	row.Control:SetPoint("LEFT", row, "LEFT", x + row.controlX, row.controlY)
	row.Text:SetWidth(x - 8 - LABEL_X)
	row:SetHeight(math.max(ROW_HEIGHT, row.Text:GetStringHeight() + 12))
end

-- Gray out a row whose parent setting is off, like the Settings panel does.
function Widgets.SetEnabled(row, enabled)
	row.enabled = enabled
	local color = enabled and NORMAL_FONT_COLOR or GRAY_FONT_COLOR
	row.Text:SetTextColor(color:GetRGB())
	if row.Control then
		if row.Control.SetEnabled then
			row.Control:SetEnabled(enabled)
		end
		if row.Control.DesaturateHierarchy then
			row.Control:DesaturateHierarchy(enabled and 0 or 1)
		end
	end
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local builders = {}

function builders.header(parent, option)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(HEADER_HEIGHT)
	row.option = option
	local title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetJustifyH("LEFT")
	title:SetPoint("TOPLEFT", 7, -16)
	title:SetText(L[option.key] or option.key)
	row.Text = title
	row.isHeader = true
	return row
end

function builders.text(parent, option)
	local row = CreateFrame("Frame", nil, parent)
	local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetJustifyH("LEFT")
	text:SetPoint("TOPLEFT", LABEL_X, -4)
	text:SetPoint("RIGHT", -20, 0)
	text:SetText(L[option.key] or option.key)
	row.Text = text
	row.option = option
	row.Refresh = function()
		row:SetHeight(math.max(text:GetStringHeight() + 10, ROW_HEIGHT))
	end
	return row
end

function builders.checkbox(parent, option)
	local row = CreateRow(parent, option)
	local box = CreateFrame("CheckButton", nil, row, "SettingsCheckboxTemplate")
	SetControl(row, box, 0, 0)
	box:SetScript("OnClick", function(self)
		Set(option, self:GetChecked() and true or false)
		PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	end)
	box:SetScript("OnEnter", function()
		OnEnter(row)
	end)
	box:SetScript("OnLeave", function()
		OnLeave(row)
	end)
	-- Clicking the label toggles too, like Blizzard's rows.
	row:SetScript("OnMouseUp", function()
		if box:IsEnabled() then
			box:Click()
		end
	end)
	row.Refresh = function()
		box:SetChecked(Get(option) and true or false)
	end
	return row
end

local function SliderFormatter(option)
	if option.format == "percent" then
		return function(value)
			return ("%d%%"):format(math.floor(value * 100 + 0.5))
		end
	elseif option.format == "seconds" then
		return function(value)
			return L.SECONDS_SHORT:format(value)
		end
	elseif option.format == "percentWhole" then
		return function(value)
			return ("%d%%"):format(value)
		end
	elseif option.format == "plus" then
		return function(value)
			return ("+%d"):format(value)
		end
	end
	return function(value)
		return ("%d"):format(value)
	end
end

function builders.slider(parent, option)
	local row = CreateRow(parent, option)
	local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	slider:SetWidth(250)
	SetControl(row, slider, 0, 3)
	local step = math.max(option.step or 1, 0.01)
	local steps = math.floor((option.max - option.min) / step + 0.5) -- lint: allow L10 (step >= 0.01)
	local formatters = { [MinimalSliderWithSteppersMixin.Label.Right] = SliderFormatter(option) }
	slider:Init(Config:Get(option.path), option.min, option.max, steps, formatters)
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		if row.refreshing then
			return
		end
		-- Snap to the step so stored values stay tidy.
		value = option.min + math.floor((value - option.min) / step + 0.5) * step -- lint: allow L10 (step >= 0.01)
		if Config:Get(option.path) ~= value then
			Config:Set(option.path, value)
		end
	end, row)
	slider.Slider:HookScript("OnEnter", function()
		OnEnter(row)
	end)
	slider.Slider:HookScript("OnLeave", function()
		OnLeave(row)
	end)
	row.Refresh = function()
		row.refreshing = true
		slider:SetValue(Config:Get(option.path))
		row.refreshing = false
	end
	return row
end

function builders.dropdown(parent, option)
	local row = CreateRow(parent, option)
	local control = CreateFrame("Frame", nil, row, "SettingsDropdownWithButtonsTemplate")
	SetControl(row, control, 32, 3)
	control.Dropdown:SetWidth(220)
	local function IsSelected(value)
		return Get(option) == value
	end
	local function SetSelected(value)
		Set(option, value)
	end
	control.Dropdown:SetupMenu(function(_, root)
		for _, value in ipairs(Widgets.Choices(option)) do
			local label
			if type(value) == "table" then
				label, value = value.label, value.value
			else
				label = Widgets.ChoiceCopy(option, value)
			end
			root:CreateRadio(label, IsSelected, SetSelected, value)
		end
	end)
	control.Dropdown:HookScript("OnEnter", function()
		OnEnter(row)
	end)
	control.Dropdown:HookScript("OnLeave", function()
		OnLeave(row)
	end)
	row.Refresh = function()
		control.Dropdown:GenerateMenu()
	end
	return row
end

-- A dropdown of checkboxes, stored as a bit mask (bit 1 = first choice).
function builders.multi(parent, option)
	local row = CreateRow(parent, option)
	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle2DropdownTemplate")
	SetControl(row, dropdown, 50, 3)
	dropdown:SetWidth(220)
	local Util = ns.Util
	local function IsSelected(index)
		return Util.HasBit(Config:Get(option.path), index)
	end
	local function Toggle(index)
		Config:Set(option.path, Util.SetBit(Config:Get(option.path), index, not IsSelected(index)))
	end
	dropdown:SetupMenu(function(_, root)
		for index, value in ipairs(Widgets.Choices(option)) do
			local label = type(value) == "table" and value.label or Widgets.ChoiceCopy(option, value)
			root:CreateCheckbox(label, IsSelected, Toggle, index)
		end
	end)
	dropdown:SetSelectionText(function()
		local choices = Widgets.Choices(option)
		local count = 0
		for index in ipairs(choices) do
			if IsSelected(index) then
				count = count + 1
			end
		end
		if count == #choices then
			return L.MULTI_ALL
		elseif count == 0 then
			return L.MULTI_NONE
		end
		return L.MULTI_SOME:format(count, #choices)
	end)
	row.Refresh = function()
		dropdown:GenerateMenu()
	end
	return row
end

function builders.color(parent, option)
	local row = CreateRow(parent, option)
	local swatch = CreateFrame("Button", nil, row, "ColorSwatchTemplate")
	SetControl(row, swatch, 7, 0)
	local function Current()
		return CreateColorFromHexString(Config:Get(option.path))
	end
	swatch:SetScript("OnClick", function()
		local color = Current()
		local previous = Config:Get(option.path)
		ColorPickerFrame:SetupColorPickerAndShow({
			r = color.r, g = color.g, b = color.b,
			swatchFunc = function()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				Config:Set(option.path, CreateColor(r, g, b, 1):GenerateHexColor())
			end,
			cancelFunc = function()
				Config:Set(option.path, previous)
			end,
		})
	end)
	swatch:SetScript("OnEnter", function()
		OnEnter(row)
	end)
	swatch:SetScript("OnLeave", function()
		OnLeave(row)
	end)
	row.Refresh = function()
		local color = Current()
		swatch.Color:SetVertexColor(color.r, color.g, color.b)
	end
	return row
end

function builders.button(parent, option)
	local row = CreateRow(parent, option)
	local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	button:SetSize(200, 26)
	SetControl(row, button, 0, 0)
	button:SetText(L.Buttons[option.key] or option.key)
	button:SetScript("OnClick", function()
		ns.Call(option.onClick)
	end)
	button:SetScript("OnEnter", function()
		OnEnter(row)
	end)
	button:SetScript("OnLeave", function()
		OnLeave(row)
	end)
	return row
end

function Widgets.Create(parent, option)
	local build = builders[option.type]
	local row = build(parent, option)
	return row
end
