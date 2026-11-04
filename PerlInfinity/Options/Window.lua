-- The Perl Infinity options window. It's built from the same frame template as the
-- game's Settings panel, so it looks like part of the game:
--
--   [search]                                                    [x]
--   nav list    settings for the page          live preview
--               (scrolls)                       of the frames
--   [Defaults]     [Hide preview] [Move frames in Edit Mode]  [Close]
--
-- It opens at a comfortable size for the screen and can be resized from the
-- corner grip. The size and whether the preview shows are remembered for the
-- account. It's created the first time it opens and costs nothing until then.
local _, ns = ...

local Options = ns:NewModule("Options")
local Widgets, Config = ns.OptionWidgets, ns.Config
local L = ns.L

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 1240, 800
local MIN_HEIGHT = 560
local NAV_WIDTH = 190
local LIST_LEFT = NAV_WIDTH + 30 -- where the settings list starts
local SCROLLBAR = 30 -- room right of the list for its scroll bar
local MARGIN = 14
-- The list takes about this much; the preview gets the rest, within limits.
local LIST_COMFORT = 620
local PREVIEW_MIN, PREVIEW_MAX = 260, 480

local window
local current -- key of the page shown
local rowsByPage = {}

---------------------------------------------------------------------------
-- Navigation
---------------------------------------------------------------------------

local function NavButton(parent, page)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(NAV_WIDTH - 10, 20)
	local texture = button:CreateTexture(nil, "BACKGROUND")
	texture:SetPoint("CENTER")
	button.Texture = texture
	local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("LEFT", 26, 1)
	label:SetJustifyH("LEFT")
	label:SetText(L.Pages[page.key])
	button.Label = label
	button.page = page
	button:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Options:ShowPage(page.key)
	end)
	button:SetScript("OnEnter", function(self)
		if current ~= self.page.key then
			self.Texture:SetAtlas("Options_List_Hover", TextureKitConstants.UseAtlasSize)
			self.Texture:Show()
		end
	end)
	button:SetScript("OnLeave", function(self)
		if current ~= self.page.key then
			self.Texture:Hide()
		end
	end)
	return button
end

local function NavHeader(parent, text)
	local header = CreateFrame("Frame", nil, parent)
	header:SetSize(NAV_WIDTH - 10, 30)
	local background = header:CreateTexture(nil, "ARTWORK")
	background:SetAtlas("Options_CategoryHeader_1", TextureKitConstants.UseAtlasSize)
	background:SetPoint("TOPLEFT")
	local label = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
	label:SetPoint("LEFT", 20, -1)
	label:SetText(text)
	return header
end

local function BuildNav(frame)
	local nav = CreateFrame("Frame", nil, frame)
	nav:SetPoint("TOPLEFT", 18, -64)
	nav:SetPoint("BOTTOMLEFT", 18, 40)
	nav:SetWidth(NAV_WIDTH)
	frame.Nav = nav
	frame.NavButtons = {}

	local y = 0
	local lastGroup
	for _, page in ipairs(ns.OptionPages.list) do
		if page.group ~= lastGroup then
			local header = NavHeader(nav, L.PageGroups[page.group])
			header:SetPoint("TOPLEFT", 0, y)
			y = y - 32
			lastGroup = page.group
		end
		local button = NavButton(nav, page)
		button:SetPoint("TOPLEFT", 0, y)
		y = y - 21
		frame.NavButtons[page.key] = button
	end
end

local function HighlightNav()
	for key, button in pairs(window.NavButtons) do
		if key == current then
			button.Label:SetFontObject("GameFontHighlight")
			button.Texture:SetAtlas("Options_List_Active", TextureKitConstants.UseAtlasSize)
			button.Texture:Show()
		else
			button.Label:SetFontObject("GameFontNormal")
			button.Texture:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function PageRows(page)
	local rows = rowsByPage[page.key]
	if not rows then
		rows = {}
		for _, option in ipairs(page.rows) do
			option.page = page
			local row = Widgets.Create(window.List, option)
			row:Hide()
			rows[#rows + 1] = row
		end
		rowsByPage[page.key] = rows
	end
	return rows
end

local function IsShownRow(row)
	local option = row.option
	return not option.shownIf or option.shownIf()
end

local function IsEnabledRow(row)
	local option = row.option
	if option.enabledIf then
		return option.enabledIf() and true or false
	end
	if option.parent then
		local value = Config:Get(option.parent)
		if option.parentValue ~= nil then
			return value == option.parentValue
		end
		if option.parentNot ~= nil then
			return value ~= option.parentNot
		end
		return value and true or false
	end
	return true
end

-- Stacks the given rows top to bottom and refreshes their values.
local function Stack(rows)
	local list = window.List
	local width = list:GetWidth()
	for _, child in ipairs({ list:GetChildren() }) do
		child:Hide()
	end
	local y = 0
	for _, row in ipairs(rows) do
		if IsShownRow(row) then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
			row:SetPoint("RIGHT", list, "RIGHT")
			Widgets.Layout(row, width)
			if row.Refresh then
				row.Refresh()
			end
			if not row.isHeader and row.option.type ~= "text" then
				Widgets.SetEnabled(row, IsEnabledRow(row))
			end
			row:Show()
			y = y + row:GetHeight()
		end
	end
	list:SetHeight(math.max(y, 1))
	window.shownRows = rows
end

local function RefreshShown()
	if window and window:IsShown() and window.shownRows then
		Stack(window.shownRows)
	end
end

---------------------------------------------------------------------------
-- Size and preview
---------------------------------------------------------------------------

-- Account-wide window state, kept outside profiles like frame positions.
local function State()
	local global = Config:DB().global
	global.optionsWindow = global.optionsWindow or {}
	return global.optionsWindow
end

local function MinWidth(showPreview)
	local width = LIST_LEFT + Widgets.MIN_WIDTH + SCROLLBAR + MARGIN
	if showPreview then
		width = width + PREVIEW_MIN
	end
	return width
end

-- Hands the window's width to the list and the preview, then refits the
-- rows to the list.
local function Relayout()
	local showPreview = not State().previewHidden
	local room = window:GetWidth() - LIST_LEFT - SCROLLBAR - MARGIN
	local previewWidth = 0
	if showPreview then
		previewWidth = ns.Util.Clamp(room - LIST_COMFORT, PREVIEW_MIN, PREVIEW_MAX)
	end
	window.Preview:SetWidth(math.max(previewWidth, 1))
	window.Preview:SetShown(showPreview)
	window.Scroll:SetPoint("BOTTOMRIGHT", -(MARGIN + previewWidth + SCROLLBAR), 44)
	window.List:SetWidth(math.max(room - previewWidth, Widgets.MIN_WIDTH))
	window.PreviewToggle:SetText(showPreview and L.BUTTON_HIDE_PREVIEW or L.BUTTON_SHOW_PREVIEW)
	-- The window can't be dragged narrower than its contents need.
	local maxWidth, maxHeight = UIParent:GetWidth(), UIParent:GetHeight()
	window:SetResizeBounds(math.min(MinWidth(showPreview), maxWidth), math.min(MIN_HEIGHT, maxHeight), maxWidth, maxHeight)
	window.Grip:SetMinWidth(math.min(MinWidth(showPreview), maxWidth))
	RefreshShown()
end

-- Opening size: what was saved, or the default, never bigger than the screen
-- and never smaller than the contents need.
local function FitToScreen()
	local state = State()
	local maxWidth, maxHeight = UIParent:GetWidth() - 40, UIParent:GetHeight() - 40
	local minWidth = MinWidth(not state.previewHidden)
	local width = math.min(math.max(state.width or DEFAULT_WIDTH, minWidth), maxWidth)
	local height = math.min(math.max(state.height or DEFAULT_HEIGHT, MIN_HEIGHT), maxHeight)
	window:SetSize(width, height)
end

local function TogglePreview()
	local state = State()
	state.previewHidden = not state.previewHidden or nil
	-- Showing the preview again may need a wider window.
	local minWidth = MinWidth(not state.previewHidden)
	if window:GetWidth() < minWidth then
		window:SetWidth(math.min(minWidth, UIParent:GetWidth() - 40))
	end
	Relayout()
	ns.OptionPreview:Refresh()
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------

local function Matches(option, needle)
	local label, tooltip = Widgets.Copy(option)
	local haystack = ((label or "") .. " " .. (tooltip or "") .. " " .. (L.Tags[option.key or option.path] or "")):lower()
	return haystack:find(needle, 1, true) ~= nil
end

local function Search(text)
	local needle = strtrim(text or ""):lower()
	if needle == "" then
		Options:ShowPage(current or "general")
		return
	end
	local results = {}
	for _, page in ipairs(ns.OptionPages.list) do
		local pageRows = PageRows(page)
		local found = {}
		for _, row in ipairs(pageRows) do
			if not row.isHeader and row.option.type ~= "text" and Matches(row.option, needle) then
				found[#found + 1] = row
			end
		end
		if #found > 0 then
			local header = window.searchHeaders[page.key]
			if not header then
				header = Widgets.Create(window.List, { type = "header", key = "Pages." .. page.key })
				header.Text:SetText(L.Pages[page.key])
				window.searchHeaders[page.key] = header
			end
			results[#results + 1] = header
			for _, row in ipairs(found) do
				results[#results + 1] = row
			end
		end
	end
	if #results == 0 then
		window.NoResults:Show()
	else
		window.NoResults:Hide()
	end
	current = nil
	HighlightNav()
	ns.OptionPreview:Show(nil)
	Stack(results)
end

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------

StaticPopupDialogs.PERLINFINITY_DEFAULTS = {
	text = "%s",
	button1 = L.DEFAULTS_THESE,
	button2 = CANCEL,
	button3 = L.DEFAULTS_ALL,
	OnAccept = function(_, page)
		for _, section in ipairs(page.sections or {}) do
			Config:Reset(section)
		end
	end,
	OnAlt = function()
		Config:Reset("")
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

local function AskDefaults()
	local page = ns.OptionPages.byKey[current]
	if not page or not page.sections then
		return
	end
	local dialog = StaticPopup_Show("PERLINFINITY_DEFAULTS", L.DEFAULTS_QUESTION:format(L.Pages[page.key]))
	if dialog then
		dialog.data = page
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function Build()
	local frame = CreateFrame("Frame", "PerlInfinityOptionsFrame", UIParent, "SettingsFrameTemplate")
	frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()
	frame.NineSlice.Text:SetText(L.WINDOW_TITLE)
	tinsert(UISpecialFrames, frame:GetName())

	-- Drag by the title bar.
	local drag = CreateFrame("Frame", nil, frame)
	drag:SetPoint("TOPLEFT", 0, 0)
	drag:SetPoint("TOPRIGHT", -30, 0)
	drag:SetHeight(22)
	drag:EnableMouse(true)
	drag:RegisterForDrag("LeftButton")
	drag:SetScript("OnDragStart", function()
		frame:StartMoving()
	end)
	drag:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
	end)

	local search = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	search:SetSize(NAV_WIDTH - 10, 20)
	search:SetPoint("TOPLEFT", 24, -34)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function(self, userInput)
		if userInput then
			Search(self:GetText())
		end
	end)
	search.Instructions:SetText(L.SEARCH)
	frame.Search = search

	BuildNav(frame)

	-- The settings list scrolls in the middle.
	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", LIST_LEFT, -38)
	scroll:SetPoint("BOTTOMRIGHT", -(MARGIN + PREVIEW_MIN + SCROLLBAR), 44)
	local bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
	ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
	local list = CreateFrame("Frame", nil, scroll)
	list:SetSize(Widgets.MIN_WIDTH, 1)
	scroll:SetScrollChild(list)
	frame.Scroll, frame.List = scroll, list
	frame.searchHeaders = {}

	local noResults = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	noResults:SetPoint("TOP", scroll, "TOP", 0, -40)
	noResults:SetText(L.SEARCH_NONE)
	noResults:Hide()
	frame.NoResults = noResults

	-- Live preview on the right.
	local preview = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
	preview:SetPoint("TOPRIGHT", -MARGIN, -34)
	preview:SetPoint("BOTTOMRIGHT", -MARGIN, 44)
	preview:SetWidth(PREVIEW_MIN)
	frame.Preview = preview
	ns.OptionPreview:Attach(preview)

	local defaults = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	defaults:SetSize(110, 22)
	defaults:SetPoint("BOTTOMLEFT", 16, 14)
	defaults:SetText(L.BUTTON_DEFAULTS)
	defaults:SetScript("OnClick", AskDefaults)
	frame.Defaults = defaults

	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(96, 22)
	close:SetPoint("BOTTOMRIGHT", -26, 14)
	close:SetText(CLOSE)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local editMode = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	editMode:SetSize(210, 22)
	editMode:SetPoint("RIGHT", close, "LEFT", -8, 0)
	editMode:SetText(L.BUTTON_EDIT_MODE)
	editMode:SetScript("OnClick", function()
		frame:Hide()
		ns.Movers:OpenEditMode()
	end)

	local previewToggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	previewToggle:SetSize(130, 22)
	previewToggle:SetPoint("RIGHT", editMode, "LEFT", -8, 0)
	previewToggle:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		TogglePreview()
	end)
	frame.PreviewToggle = previewToggle

	-- The same corner grip the chat windows use.
	local grip = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:Init(frame, MinWidth(true), MIN_HEIGHT)
	grip.resizeStoppedCallback = function()
		local state = State()
		state.width, state.height = frame:GetWidth(), frame:GetHeight()
		ns.OptionPreview:Refresh()
	end
	frame.Grip = grip
	-- Rows follow the window while it's dragged; the preview catches up when
	-- the drag ends, since redrawing its frames every step isn't worth it.
	frame:HookScript("OnSizeChanged", function()
		if window then
			Relayout()
		end
	end)

	frame:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
	end)
	frame:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
		ns.OptionPreview:Show(nil)
	end)

	-- Keep rows and previews in step with changes made anywhere.
	local flusher = { queued = false }
	function flusher:Flush()
		RefreshShown()
		ns.OptionPreview:Refresh()
	end
	Config:Subscribe("", frame, function()
		if frame:IsShown() then
			ns.Scheduler:QueueThrottled(flusher, 0.1)
		end
	end)

	window = frame
	FitToScreen()
	Relayout()
	return frame
end

function Options:ShowPage(key)
	local page = ns.OptionPages.byKey[key] or ns.OptionPages.list[1]
	current = page.key
	window.NoResults:Hide()
	HighlightNav()
	Stack(PageRows(page))
	window.Scroll:SetVerticalScroll(0)
	window.Defaults:SetEnabled(page.sections ~= nil)
	ns.OptionPreview:Show(page.preview)
end

-- Opens the window, optionally on a page ("player", "raid"...).
function Options:Open(key)
	if not window then
		Build()
	else
		-- The screen or UI scale may have changed since last time.
		FitToScreen()
	end
	window.Search:SetText("")
	window:Show()
	self:ShowPage(key or current or "general")
end

function Options:Toggle(key)
	if window and window:IsShown() and (not key or key == current) then
		window:Hide()
	else
		self:Open(key)
	end
end

function Options:IsShown()
	return window ~= nil and window:IsShown()
end
