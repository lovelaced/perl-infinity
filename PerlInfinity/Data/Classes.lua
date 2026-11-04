-- The nine classes in Forever. GetNumClasses() reports 9 but the class IDs
-- aren't contiguous (Druid is 11), so the list is spelled out here.
local _, ns = ...

ns.Classes = {
	order = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "SHAMAN", "PALADIN" },

	-- Classes that use mana, for "mana only" displays.
	usesMana = {
		HUNTER = true, MAGE = true, WARLOCK = true, PRIEST = true,
		DRUID = true, SHAMAN = true, PALADIN = true,
	},

	-- Healers listed by the healer mana window, in bit order of the setting.
	healerChoices = { "PRIEST", "DRUID", "SHAMAN", "PALADIN", "MAGE", "WARLOCK", "HUNTER" },
}

-- Localized class name, falling back to the token.
function ns.Classes.Name(token)
	return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
end

-- Texture coordinates for the class icon atlas used by X-Perl.
function ns.Classes.IconCoords(token)
	return CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
end

ns.Classes.ICON_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
