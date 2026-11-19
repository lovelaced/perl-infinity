-- Profile and position dialogs, using the game's standard popups.
local _, ns = ...

local Dialogs = {}
ns.ProfileDialogs = Dialogs

local Profiles = ns.Profiles
local L = ns.L

local function Popup(key, definition)
	definition.timeout = 0
	definition.whileDead = true
	definition.hideOnEscape = true
	definition.preferredIndex = 3
	StaticPopupDialogs[key] = definition
end

-- Profile names stay short enough to read in a dropdown.
local NAME_LETTERS = 48

-- The game shares its popup frames, and a popup that limits its edit box
-- (adding a friend allows 77 letters) leaves the limit for whichever popup
-- comes next. So every popup here sets its own: a name length, or 0 for no
-- limit on export strings, which run to hundreds of letters.
local function TextPopup(key, maxLetters, definition)
	definition.hasEditBox = true
	definition.maxLetters = maxLetters
	Popup(key, definition)
end

local function EditBox(dialog)
	return dialog.EditBox or dialog.editBox
end

-- Enter does what the first button does.
local function AcceptOnEnter(editBox)
	StaticPopup_OnClick(editBox:GetParent(), 1)
end

local KEEP_OPEN = true

-- A name or an import that doesn't work keeps its popup open, so you can
-- fix what you typed instead of starting over.
TextPopup("PERLINFINITY_PROFILE_NEW", NAME_LETTERS, {
	text = L.DIALOG_NEW_PROFILE,
	button1 = L.DIALOG_CREATE,
	button2 = CANCEL,
	OnAccept = function(dialog)
		local name = strtrim(EditBox(dialog):GetText())
		if name == "" then
			return KEEP_OPEN
		end
		if not Profiles:Create(name, Profiles:Active()) then
			ns.Print(L.MSG_PROFILE_EXISTS)
			return KEEP_OPEN
		end
		Profiles:Use(name)
	end,
	EditBoxOnEnterPressed = AcceptOnEnter,
})

TextPopup("PERLINFINITY_PROFILE_RENAME", NAME_LETTERS, {
	text = L.DIALOG_RENAME_PROFILE,
	button1 = L.DIALOG_SAVE,
	button2 = CANCEL,
	OnShow = function(dialog)
		EditBox(dialog):SetText(Profiles:Active())
		EditBox(dialog):HighlightText()
	end,
	OnAccept = function(dialog)
		local name = strtrim(EditBox(dialog):GetText())
		if name == "" then
			return KEEP_OPEN
		end
		if name == Profiles:Active() then
			return
		end
		if not Profiles:Rename(Profiles:Active(), name) then
			ns.Print(L.MSG_PROFILE_EXISTS)
			return KEEP_OPEN
		end
		ns.Config:Rebuild()
	end,
	EditBoxOnEnterPressed = AcceptOnEnter,
})

Popup("PERLINFINITY_PROFILE_DELETE", {
	text = L.DIALOG_DELETE_PROFILE,
	button1 = DELETE,
	button2 = CANCEL,
	OnAccept = function()
		Profiles:Delete(Profiles:Active())
	end,
})

Popup("PERLINFINITY_PROFILE_RESET", {
	text = L.DIALOG_RESET_PROFILE,
	button1 = RESET,
	button2 = CANCEL,
	OnAccept = function()
		Profiles:Reset(Profiles:Active())
	end,
})

TextPopup("PERLINFINITY_PROFILE_EXPORT", 0, {
	text = L.DIALOG_EXPORT,
	button1 = CLOSE,
	editBoxWidth = 360,
	OnShow = function(dialog)
		local box = EditBox(dialog)
		box:SetText(Profiles:Export(Profiles:Active(), false))
		box:HighlightText()
		box:SetFocus()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
})

TextPopup("PERLINFINITY_PROFILE_IMPORT", 0, {
	text = L.DIALOG_IMPORT,
	button1 = L.DIALOG_IMPORT_BUTTON,
	button2 = CANCEL,
	editBoxWidth = 360,
	OnAccept = function(dialog)
		local payload, problem = Profiles:Decode(EditBox(dialog):GetText())
		if not payload then
			ns.Print(problem == "newer" and L.MSG_IMPORT_NEWER or L.MSG_IMPORT_BAD)
			return KEEP_OPEN
		end
		local name = L.IMPORTED_PROFILE
		local index = 1
		while Profiles:Exists(name) do
			index = index + 1
			name = L.IMPORTED_PROFILE .. " " .. index
		end
		Profiles:Import(name, payload, false)
		Profiles:Use(name)
		ns.Print(L.MSG_IMPORTED:format(name))
	end,
	EditBoxOnEnterPressed = AcceptOnEnter,
})

Popup("PERLINFINITY_POSITIONS_RESET", {
	text = L.DIALOG_RESET_POSITIONS,
	button1 = RESET,
	button2 = CANCEL,
	OnAccept = function()
		ns.Movers:ResetAll()
	end,
})

Popup("PERLINFINITY_PROFILE_COPY", {
	text = L.DIALOG_COPY_PROFILE,
	button1 = L.DIALOG_COPY,
	button2 = CANCEL,
	OnAccept = function(_, source)
		Profiles:Copy(source, Profiles:Active())
	end,
})

local function Show(key, ...)
	if InCombatLockdown() then
		ns.Print(L.MSG_NOT_IN_COMBAT)
		return
	end
	StaticPopup_Show(key, ...)
end

function Dialogs:New()
	Show("PERLINFINITY_PROFILE_NEW")
end

function Dialogs:Copy(source)
	if InCombatLockdown() then
		ns.Print(L.MSG_NOT_IN_COMBAT)
		return
	end
	StaticPopup_Show("PERLINFINITY_PROFILE_COPY", source, Profiles:Active(), source)
end

function Dialogs:Rename()
	Show("PERLINFINITY_PROFILE_RENAME")
end

function Dialogs:Delete()
	if #Profiles:List() <= 1 then
		ns.Print(L.MSG_LAST_PROFILE)
		return
	end
	Show("PERLINFINITY_PROFILE_DELETE", Profiles:Active())
end

function Dialogs:Reset()
	Show("PERLINFINITY_PROFILE_RESET", Profiles:Active())
end

function Dialogs:Export()
	Show("PERLINFINITY_PROFILE_EXPORT")
end

function Dialogs:Import()
	Show("PERLINFINITY_PROFILE_IMPORT")
end

function Dialogs:ResetPositions()
	Show("PERLINFINITY_POSITIONS_RESET")
end
