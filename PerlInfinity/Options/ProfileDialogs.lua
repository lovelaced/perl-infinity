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

local function EditBox(dialog)
	return dialog.EditBox or dialog.editBox
end

Popup("PERLINFINITY_PROFILE_NEW", {
	text = L.DIALOG_NEW_PROFILE,
	button1 = L.DIALOG_CREATE,
	button2 = CANCEL,
	hasEditBox = true,
	OnAccept = function(dialog)
		local name = strtrim(EditBox(dialog):GetText())
		if Profiles:Create(name, Profiles:Active()) then
			Profiles:Use(name)
		else
			ns.Print(L.MSG_PROFILE_EXISTS)
		end
	end,
	EditBoxOnEnterPressed = function(editBox)
		local dialog = editBox:GetParent()
		StaticPopup_OnClick(dialog, 1)
	end,
})

Popup("PERLINFINITY_PROFILE_RENAME", {
	text = L.DIALOG_RENAME_PROFILE,
	button1 = L.DIALOG_SAVE,
	button2 = CANCEL,
	hasEditBox = true,
	OnShow = function(dialog)
		EditBox(dialog):SetText(Profiles:Active())
		EditBox(dialog):HighlightText()
	end,
	OnAccept = function(dialog)
		local name = strtrim(EditBox(dialog):GetText())
		if not Profiles:Rename(Profiles:Active(), name) then
			ns.Print(L.MSG_PROFILE_EXISTS)
		end
		ns.Config:Rebuild()
	end,
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

Popup("PERLINFINITY_PROFILE_EXPORT", {
	text = L.DIALOG_EXPORT,
	button1 = CLOSE,
	hasEditBox = true,
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

Popup("PERLINFINITY_PROFILE_IMPORT", {
	text = L.DIALOG_IMPORT,
	button1 = L.DIALOG_IMPORT_BUTTON,
	button2 = CANCEL,
	hasEditBox = true,
	editBoxWidth = 360,
	OnAccept = function(dialog)
		local payload, problem = Profiles:Decode(EditBox(dialog):GetText())
		if not payload then
			ns.Print(problem == "newer" and L.MSG_IMPORT_NEWER or L.MSG_IMPORT_BAD)
			return
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
	local dialog = StaticPopup_Show("PERLINFINITY_PROFILE_COPY", source, Profiles:Active())
	if dialog then
		dialog.data = source
	end
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
