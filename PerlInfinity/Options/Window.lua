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
--
-- While Edit Mode is open, the window docks at the side of the screen as a
-- slim panel, so you can change how frames look while you move them:
--
--   [search] [page v]
--   settings for the page
--   [Defaults]  [Show preview]  [Close]
--
-- A dropdown picks the page in place of the list, and the frames on screen
-- (real ones, or Edit Mode's samples) stand in for the preview. Clicking a
-- frame in Edit Mode turns to its page. Leaving Edit Mode brings the full
-- window back, or closes the panel if Edit Mode opened it.
local _, ns = ...

local Options = ns:NewModule("Options")
local Widgets, Config = ns.OptionWidgets, ns.Config
local L = ns.L

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 1240, 800
local MIN_HEIGHT = 560
local NAV_WIDTH = 190
local LIST_LEFT = NAV_WIDTH + 30 -- where the settings list starts
local LIST_TOP = -38
local SCROLLBAR = 30 -- room right of the list for its scroll bar
local MARGIN = 14
-- The list takes about this much; the preview gets the rest, within limits.
local LIST_COMFORT = 620
local PREVIEW_MIN, PREVIEW_MAX = 260, 480

-- Docked beside Edit Mode: the list starts at the left edge, under the
-- search box and page dropdown, and the panel sits at the right of the
-- screen between the minimap and the action bars until you move it.
local DOCK_LIST_LEFT = 24
local DOCK_LIST_TOP = -68
local DOCK_MIN_HEIGHT = 420
local DOCK_EDGE = 16
local DOCK_TOP, DOCK_BOTTOM = 190, 150

local window
local current -- key of the page shown
local rowsByPage = {}
local openedForEditMode = false -- closes again when Edit Mode does

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

-- The docked panel's stand-in for the page list.
local function BuildPagePicker(frame)
	local picker = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
	picker:SetPoint("LEFT", frame.Search, "RIGHT", 12, 0)
	picker:SetWidth(240)
	picker:SetDefaultText(L.SEARCH_RESULTS)
	local function IsCurrent(key)
		return current == key
	end
	local function Pick(key)
		frame.Search:SetText("")
		Options:ShowPage(key)
	end
	picker:SetupMenu(function(_, root)
		local lastGroup
		for _, page in ipairs(ns.OptionPages.list) do
			if page.group ~= lastGroup then
				root:CreateTitle(L.PageGroups[page.group])
				lastGroup = page.group
			end
			root:CreateRadio(L.Pages[page.key], IsCurrent, Pick, page.key)
		end
	end)
	picker:Hide()
	frame.PagePicker = picker
end

local function HighlightNav()
	window.PagePicker:GenerateMenu()
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

local function Docked()
	return window ~= nil and window.docked == true
end

-- Docked, the preview starts hidden, since the frames on screen show every
-- change. The full window and the docked panel each remember their choice.
local function PreviewShown()
	if Docked() then
		return State().dockedPreview == true
	end
	return not State().previewHidden
end

local function MinWidth(showPreview)
	local width = (Docked() and DOCK_LIST_LEFT or LIST_LEFT) + Widgets.MIN_WIDTH + SCROLLBAR + MARGIN
	if showPreview then
		width = width + PREVIEW_MIN
	end
	return width
end

local function MinHeight()
	return Docked() and DOCK_MIN_HEIGHT or MIN_HEIGHT
end

-- Hands the window's width to the list and the preview, then refits the
-- rows to the list.
local function Relayout()
	local showPreview = PreviewShown()
	local listLeft = Docked() and DOCK_LIST_LEFT or LIST_LEFT
	local room = window:GetWidth() - listLeft - SCROLLBAR - MARGIN
	local previewWidth = 0
	if showPreview then
		previewWidth = ns.Util.Clamp(room - LIST_COMFORT, PREVIEW_MIN, PREVIEW_MAX)
	end
	window.Preview:SetWidth(math.max(previewWidth, 1))
	window.Preview:SetShown(showPreview)
	window.Scroll:SetPoint("TOPLEFT", listLeft, Docked() and DOCK_LIST_TOP or LIST_TOP)
	window.Scroll:SetPoint("BOTTOMRIGHT", -(MARGIN + previewWidth + SCROLLBAR), 44)
	window.List:SetWidth(math.max(room - previewWidth, Widgets.MIN_WIDTH))
	window.PreviewToggle:SetText(showPreview and L.BUTTON_HIDE_PREVIEW or L.BUTTON_SHOW_PREVIEW)
	-- The window can't be dragged narrower than its contents need.
	local maxWidth, maxHeight = UIParent:GetWidth(), UIParent:GetHeight()
	local minWidth, minHeight = math.min(MinWidth(showPreview), maxWidth), math.min(MinHeight(), maxHeight)
	window:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
	window.Grip:SetMinWidth(minWidth)
	if window.Grip.SetMinHeight then
		window.Grip:SetMinHeight(minHeight)
	end
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

-- Where the docked panel goes: where you last left it, or the right edge of
-- the screen. Kept by its top left corner, so the grip resizes it the way
-- you'd expect.
local function PlaceDocked()
	local saved = State().docked or {}
	local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
	local minWidth = MinWidth(PreviewShown())
	local width = math.min(math.max(saved.width or minWidth, minWidth), screenWidth - 40)
	local height = math.min(math.max(saved.height or (screenHeight - DOCK_TOP - DOCK_BOTTOM), DOCK_MIN_HEIGHT), screenHeight - 40)
	window:SetSize(width, height)
	window:ClearAllPoints()
	if saved.x and saved.y then
		window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", saved.x, saved.y)
	else
		window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", screenWidth - width - DOCK_EDGE, -math.min(DOCK_TOP, screenHeight - height - 20))
	end
end

local function SaveDocked()
	local left, top = window:GetLeft(), window:GetTop()
	if not left or not top then
		return
	end
	local state = State()
	state.docked = {
		x = math.floor(left + 0.5),
		y = math.floor(top - UIParent:GetHeight() + 0.5),
		width = math.floor(window:GetWidth() + 0.5),
		height = math.floor(window:GetHeight() + 0.5),
	}
end

-- Switches between the full window and the docked panel.
local function Dock(on)
	on = on and true or false
	if Docked() == on then
		return
	end
	if on then
		-- Remember where the full window was, to put it back there.
		local point, _, relativePoint, x, y = window:GetPoint(1)
		window.fullPoint = point and { point, relativePoint, x, y } or nil
		window.docked = true
		PlaceDocked()
	else
		window.docked = false
		window:ClearAllPoints()
		local full = window.fullPoint
		if full then
			window:SetPoint(full[1], UIParent, full[2], full[3], full[4])
		else
			window:SetPoint("CENTER")
		end
		FitToScreen()
	end
	window.Nav:SetShown(not on)
	window.PagePicker:SetShown(on)
	window.EditModeButton:SetShown(not on)
	window.PreviewToggle:ClearAllPoints()
	window.PreviewToggle:SetPoint("RIGHT", on and window.CloseButton or window.EditModeButton, "LEFT", -8, 0)
	Relayout()
	ns.OptionPreview:Refresh()
end

local function TogglePreview()
	local state = State()
	if Docked() then
		state.dockedPreview = not state.dockedPreview or nil
	else
		state.previewHidden = not state.previewHidden or nil
	end
	-- Showing the preview again may need a wider window.
	local minWidth = MinWidth(PreviewShown())
	if window:GetWidth() < minWidth then
		window:SetWidth(math.min(minWidth, UIParent:GetWidth() - 40))
	end
	Relayout()
	if Docked() then
		SaveDocked()
	end
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
	StaticPopup_Show("PERLINFINITY_DEFAULTS", L.DEFAULTS_QUESTION:format(L.Pages[page.key]), nil, page)
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
		if frame.docked then
			SaveDocked()
		end
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
	BuildPagePicker(frame)

	-- The settings list scrolls in the middle.
	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", LIST_LEFT, LIST_TOP)
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
	frame.CloseButton = close

	-- The window stays open and docks beside Edit Mode.
	local editMode = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	editMode:SetSize(210, 22)
	editMode:SetPoint("RIGHT", close, "LEFT", -8, 0)
	editMode:SetText(L.BUTTON_EDIT_MODE)
	editMode:SetScript("OnClick", function()
		ns.Movers:OpenEditMode()
	end)
	frame.EditModeButton = editMode

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
		if frame.docked then
			SaveDocked()
		else
			local state = State()
			state.width, state.height = frame:GetWidth(), frame:GetHeight()
		end
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

	-- Empty frames on screen show samples while the window is open.
	frame:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
		ns.Movers:RefreshSamples()
	end)
	frame:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
		ns.OptionPreview:Show(nil)
		-- Closed while docked: the next time it opens outside Edit Mode, it's
		-- the full window again.
		openedForEditMode = false
		Dock(false)
		ns.Movers:RefreshSamples()
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

-- Opens the window, optionally on a page ("player", "raid"...). In Edit Mode
-- it opens docked.
function Options:Open(key)
	if not window then
		Build()
	elseif not window.docked then
		-- The screen or UI scale may have changed since last time.
		FitToScreen()
	end
	if ns.Movers.editing then
		if not window:IsShown() then
			openedForEditMode = true
		end
		Dock(true)
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

function Options:IsDocked()
	return Docked()
end

---------------------------------------------------------------------------
-- Beside Edit Mode
---------------------------------------------------------------------------

-- Whether entering Edit Mode opens the panel by itself (account-wide).
function Options:OpensWithEditMode()
	return State().withEditMode ~= false
end

-- Saved only when off, so the account default stays on.
function Options:SetOpensWithEditMode(on)
	if on then
		State().withEditMode = nil
	else
		State().withEditMode = false
	end
end

function Options:EditModeEntered()
	if window and window:IsShown() then
		Dock(true)
	elseif self:OpensWithEditMode() then
		self:Open()
	end
end

-- A panel Edit Mode opened closes with it; a window you had open before
-- goes back to its full size.
function Options:EditModeExited()
	if not window or not window:IsShown() then
		return
	end
	if openedForEditMode then
		window:Hide()
	else
		Dock(false)
	end
	openedForEditMode = false
end

-- You clicked a frame in Edit Mode: show its settings.
function Options:FollowFrame(key)
	if window and window:IsShown() and window.docked then
		window.Search:SetText("")
		self:ShowPage(ns.QuickSettings.PageFor(key))
	end
end
