-- Every word Perl Infinity shows, in one place. Labels and tooltips for settings
-- are keyed by the setting's path (or a shared key such as "frame.scale").
-- To translate, copy this file, change the strings, and load it after this
-- one for your locale.
local _, ns = ...

local L = {}
ns.L = L

-- Missing keys show the key itself rather than breaking anything.
setmetatable(L, {
	__index = function(_, key)
		return key
	end,
})

L.WINDOW_TITLE = "Perl Infinity"
L.MSG_UNSUPPORTED = "This version of Perl Infinity is made for WoW: Forever and won't run on this game version."
L.MSG_WELCOME = "Perl Infinity is ready. Type /perlinfinity to change settings, or move your frames in Edit Mode."
L.MSG_CONFLICT = "%s is also turned on, so you may see two sets of frames. You can turn one off in the AddOns list."
L.MSG_UNKNOWN_COMMAND = "I don't know that one. Type /perlinfinity help to see what I can do."
L.MSG_EDITMODE_COMBAT = "Edit Mode can't open during combat. Try again after the fight."
L.MSG_EDITMODE_UNAVAILABLE = "Edit Mode isn't available right now."
L.MSG_NOT_IN_COMBAT = "That has to wait until you're out of combat."
L.MSG_PROFILES = "Profiles: %s. This character uses %s."
L.MSG_PROFILE_USED = "Now using the %s profile."
L.MSG_PROFILE_MISSING = "There's no profile called %s."
L.MSG_PROFILE_EXISTS = "There's already a profile with that name."
L.MSG_LAST_PROFILE = "You need at least one profile."
L.MSG_IMPORT_BAD = "That doesn't look like a Perl Infinity profile. Check that you copied all of it."
L.MSG_IMPORT_NEWER = "This profile is from a newer version of Perl Infinity. Update Perl Infinity, then try again."
L.MSG_IMPORTED = "Added the profile %s."
L.MSG_LOG = "Perl Infinity has recorded %d problems this session. They're saved for bug reports when you log out."
L.MSG_LOG_CLEARED = "Cleared Perl Infinity's problem log."
L.MSG_TAINTWATCH_ON = "Taint watch is on, and stays on until you turn it off. Type /reload to catch anything that happens during login."
L.MSG_TAINTWATCH_OFF = "Taint watch is off."
L.MSG_TAINTWATCH_RUNNING = "Taint watch is on. Type /perlinfinity taintwatch to turn it off."
L.MSG_TAINTWATCH_FOUND = "Taint watch: %s was tainted by %s. Your mouse was over %s."
L.MSG_TAINTWATCH_NOTHING = "nothing"
L.MSG_TAINTWATCH_BLOCKED = "Taint watch: the game blocked %s. That's the bug, and it's been saved."
L.MSG_BUFFS_COMBAT = "Buff checks work out of combat. Try again after the fight."
L.MSG_BUFF_MISSING = "Missing %s: %s"
L.MSG_BUFFS_ALL_GOOD = "Everyone has their class buffs."
L.MSG_LAYOUT_NOT_RAID = "Raid layouts work in a raid."
L.MSG_LAYOUT_NOT_LEADER = "You need to be the raid leader or an assistant to move people."
L.MSG_LAYOUT_SAVED = "Saved the raid layout %s."
L.MSG_LAYOUT_DELETED = "Deleted the raid layout %s."
L.MSG_LAYOUT_MISSING = "Pick a saved raid layout first."
L.MSG_LAYOUT_DONE = "Everyone is in place."
L.MSG_LAYOUT_STOPPED = "Stopped moving people. Some may not be in place yet."

L.HELP_HEADER = "Commands:"
L.HELP_LINES = {
	{ "/perlinfinity", "Opens Perl Infinity's options. /pinf is a shortcut for every command here." },
	{ "/perlinfinity move", "Opens Edit Mode so you can move your frames." },
	{ "/perlinfinity player, pet, target, tot, focus, party, raid, tools, profiles", "Opens that page." },
	{ "/perlinfinity profile [name]", "Switches to a profile. With no name, lists your profiles." },
	{ "/perlinfinity tanks", "Shows or hides the tank targets window." },
	{ "/perlinfinity mana", "Shows or hides the healer mana window." },
	{ "/perlinfinity layouts save [name], load [name], stop", "Saves your raid groups, puts everyone back, or stops." },
	{ "/perlinfinity buffs", "Lists who in your group is missing a class buff." },
	{ "/perlinfinity names", "Opens a list of your raid's names you can copy." },
	{ "/perlinfinity reset positions", "Puts every frame back where it started." },
	{ "/perlinfinity selftest", "Checks Perl Infinity against your game and saves a report for bug reports." },
}

L.COMPARTMENT_LEFT = "Click to open options."
L.COMPARTMENT_RIGHT = "Right-click to move frames in Edit Mode."

L.BINDING_OPTIONS = "Open Perl Infinity options"
L.BINDING_EDITMODE = "Move frames in Edit Mode"
L.BINDING_RANGE = "Turn range fading on or off"
L.BINDING_RAID = "Show or hide raid frames"
L.BINDING_RAIDPETS = "Show or hide raid pets"
L.BINDING_RAIDICONS = "Switch raid frame icons"
L.BINDING_TANKS = "Show or hide tank targets"
L.BINDING_HEALERS = "Show or hide healer mana"

L.MSG_RELOAD_TO_RETURN = "The game's %s will come back after you reload. Type /reload when you're ready."
L.LIST_AND = " and "
-- Blizzard's own UI pieces Perl Infinity hides, as named in MSG_RELOAD_TO_RETURN.
L.GamePieces = {
	player = "player frame",
	playerCast = "cast bar",
	pet = "pet frame",
	petCast = "pet cast bar",
	target = "target frame",
	targettarget = "target of target frame",
	focus = "focus frame",
	party = "party frames",
	raid = "raid frames",
	buffs = "buffs",
	debuffs = "debuffs",
}

L.LAUNCHER_HEADER = "Perl Infinity"
L.LAUNCHER_TEXT = "Classic X-Perl style unit frames."
L.LAUNCHER_OPTIONS_LABEL = "Options"
L.LAUNCHER_OPTIONS_BUTTON = "Open Perl Infinity options"
L.LAUNCHER_OPTIONS_TIP = "Change how your frames look and what they show, with a live preview."
L.LAUNCHER_MOVE_LABEL = "Frame positions"
L.LAUNCHER_MOVE_BUTTON = "Move frames in Edit Mode"
L.LAUNCHER_MOVE_TIP = "Move and resize your frames in Edit Mode, the game's layout editor."

---------------------------------------------------------------------------
-- Options window
---------------------------------------------------------------------------

L.SEARCH = "Search"
L.SEARCH_NONE = "No settings match that."
L.BUTTON_DEFAULTS = "Defaults"
L.BUTTON_EDIT_MODE = "Move frames in Edit Mode"
L.BUTTON_HIDE_PREVIEW = "Hide preview"
L.BUTTON_SHOW_PREVIEW = "Show preview"
L.DEFAULTS_QUESTION = "Put the %s settings back to how they started? Your frame positions won't move."
L.DEFAULTS_THESE = "These settings"
L.DEFAULTS_ALL = "All settings"
L.PREVIEW_CAPTION = "Sample frames. Move and size them in Edit Mode."
L.PREVIEW_NONE = "Profiles hold your settings. Your frame positions belong to your Edit Mode layout."
L.PREVIEW_TOOLS = "The tank and healer windows appear in raids. Move them in Edit Mode."
L.SECONDS_SHORT = "%d sec"
L.MULTI_ALL = "All"
L.MULTI_NONE = "None"
L.MULTI_SOME = "%d of %d"

L.PageGroups = {
	general = "General",
	frames = "Your frames",
	groups = "Groups",
	profiles = "Profiles",
}

L.Pages = {
	general = "General",
	appearance = "Appearance",
	player = "Player",
	pet = "Pet",
	target = "Target",
	small = "Target of target",
	focus = "Focus",
	party = "Party",
	raid = "Raid",
	tools = "Raid tools",
	profiles = "Profiles",
}

L.HEADER_START = "Getting started"
L.HEADER_MOUSE = "Mouse and tooltips"
L.HEADER_RANGE = "Range"
L.HEADER_HIGHLIGHTS = "Highlights"
L.HEADER_AURAS = "Buffs and debuffs"
L.HEADER_CAST = "Cast bar"
L.HEADER_STATUS = "Status"
L.HEADER_COMBAT = "Combat"
L.HEADER_ALERTS = "Alerts"
L.HEADER_FRAMES = "Frames"
L.HEADER_BARS = "Bars"
L.HEADER_HEALTH_COLOR = "Health color"
L.HEADER_POWER_COLORS = "Power colors"
L.HEADER_NAMES = "Names"
L.HEADER_PORTRAITS = "Portraits and icons"
L.HEADER_SIZE = "Size"
L.HEADER_LAYOUT = "Layout"
L.HEADER_SMALL_FRAMES = "Frames"
L.HEADER_SHARED = "Shared by all four"
L.HEADER_PARTY_TARGETS = "Party targets"
L.HEADER_PARTY_PETS = "Party pets"
L.HEADER_ARRANGE = "Arrange"
L.HEADER_RAID_ICONS = "Buffs and debuffs"
L.HEADER_RAID_PETS = "Raid pets"
L.HEADER_TANKS = "Tank targets"
L.HEADER_HEALERS = "Healer mana"
L.HEADER_LAYOUTS = "Raid layouts"
L.HEADER_CHECKS = "Checks"
L.HEADER_PROFILE = "Profile"
L.HEADER_NEW_CHARACTERS = "New characters"
L.HEADER_SHARE = "Share"
L.HEADER_POSITIONS = "Frame positions"

L.TEXT_START = "Change what your frames show here, and move them in Edit Mode, the game's layout editor. The preview on the right updates as you go."
L.TEXT_BINDINGS = "You can set key bindings for Perl Infinity in the game's Key Bindings menu."
L.TEXT_TANKS = "A window for healers and raid leaders that shows each tank, what they're fighting, and who that enemy is attacking."
L.TEXT_LAYOUTS = "Save who is in which raid group, and put everyone back in place later."
L.TEXT_POSITIONS = "Positions belong to your Edit Mode layout, not your profile, so switching profiles never moves your frames."

L.Buttons = {
	editMode = "Open Edit Mode",
	layoutSave = "Save current groups",
	layoutLoad = "Load layout",
	layoutDelete = "Delete layout",
	buffCheck = "Check buffs now",
	raidNames = "Open raid names",
	profileNew = "New",
	profileRename = "Rename",
	profileDelete = "Delete",
	profileReset = "Reset",
	profileExport = "Export",
	profileImport = "Import",
	positionsReset = "Reset positions",
}

-- Settings: { label, tooltip }
L.Options = {
	editMode = { "Frame positions", "Move and resize your frames in Edit Mode. Click any box labeled Perl Infinity to change it. You can also right-click Perl Infinity in the AddOns menu on your minimap." },

	["general.mouseoverHighlight"] = { "Highlight on mouseover", "Puts a soft gold glow over the frame under your mouse." },
	["general.unitTooltips"] = { "Unit tooltips", "When to show the game's tooltip for the player or creature under your mouse." },
	["general.unitTooltipsInCombat"] = { "Show them in combat", "Turn this off to keep unit tooltips out of your way during fights." },
	["general.auraTooltips"] = { "Buff tooltips", "Whether pointing at a buff or debuff icon shows its details." },
	["general.auraTooltipsInCombat"] = { "Show them in combat", "Turn this off to keep buff tooltips out of your way during fights." },
	["general.fadeTooltips"] = { "Fade tooltips out", "Tooltips fade away when your mouse leaves a frame, instead of closing right away." },

	["range.enabled"] = { "Fade when out of range", "Makes frames see-through when someone is too far away for your spells." },
	["range.mode"] = { "Range check", "How Perl Infinity decides who is out of range." },
	["range.alpha"] = { "Faded opacity", "How faint out-of-range frames get. Lower numbers are fainter." },
	["range.part"] = { "What fades", "Which part of a frame fades when it's out of range." },
	["range.icon"] = { "Show out-of-range icon", "Adds a small reaching-hand icon to target and party frames when they're out of range." },

	["highlight.debuffs"] = { "Debuff highlight", "Colors party and raid frames when someone has a debuff: blue for magic, purple for a curse, brown for disease, and green for poison." },
	["highlight.debuffStyle"] = { "Highlight style", "Where the debuff color shows." },
	["highlight.hots"] = { "My heals over time", "Party and raid frames glow blue while one of your heals over time, like Renew or Rejuvenation, is on them. The glow pulses as it runs out." },
	["highlight.hotBars"] = { "Heal over time bars", "Adds a thin bar along the health bar for each of your heals over time on that player, showing how long it has left. The game doesn't tell addons how much a heal over time will restore, so the bar shows time, not amount." },
	["highlight.shields"] = { "My shields", "Party and raid frames glow purple while your Power Word: Shield is on them." },
	["highlight.healing"] = { "Glow when being healed", "Party and raid frames glow green while a heal is on its way to them." },
	["highlight.aggro"] = { "Aggro", "Party and raid frames get a red outline when an enemy is attacking that player." },
	["highlight.target"] = { "My target", "Puts a gold outline on the party or raid frame of whoever you're targeting." },

	["auras.bigOwn"] = { "Show mine bigger", "Buffs and debuffs that you or your pet cast show up larger and first in line, so they're easy to find." },
	["auras.markStealable"] = { "Mark buffs I can remove", "Enemy buffs you can take off with spells like Purge or Dispel Magic get spinning arrows and show up first." },
	["auras.spirals"] = { "Timer swirls", "The clock-style sweep across an icon that shows how much time is left." },
	["auras.countdown"] = { "Countdown numbers", "Shows the seconds left on each icon." },
	["auras.countdownStart"] = { "Start counting at", "Numbers show up once a buff or debuff has this many seconds left." },

	["castBars.time"] = { "Cast time", "Shows how many seconds are left on a cast." },

	["general.readyCheck"] = { "Show ready checks", "During a ready check, each frame shows a check mark, a question mark, or an X." },
	["general.afk"] = { "Show AFK", "Shows AFK on the frames of players who are away." },
	["general.feignDeath"] = { "Show feign death", "Shows Feign instead of Dead when a hunter is only pretending." },
	["general.targetSounds"] = { "Target sounds", "Plays the classic click when you pick or clear a target or focus." },
	["general.combatFlash"] = { "Flash when hit or healed", "Frame borders flash red when someone takes damage and green when they're healed." },
	["general.hitIndicators"] = { "Combat text on portraits", "Shows damage and healing numbers over portraits, the way the game's own player frame does." },
	["alerts.lowHealth"] = { "Low health warning", "The edges of your screen pulse red when your health is low, and flash when you lose control of your character." },
	["alerts.lowHealthPercent"] = { "Warn below", "How low your health has to drop before the warning starts." },
	["alerts.aggroWarning"] = { "Aggro warning", "When you're in a group, AGGRO appears in the middle of your screen if an enemy turns on you or your pet. Move it in Edit Mode." },

	["look.frameAlpha"] = { "Frame opacity", "How see-through every Perl Infinity frame is, text and all." },
	["look.textAlpha"] = { "Text opacity", "Fades only the text, on top of the frame opacity." },
	["look.background"] = { "Background color", "The color inside each box." },
	["look.backgroundAlpha"] = { "Background opacity", "How much of the world shows through each box." },
	["look.border"] = { "Border color", "The color of the tooltip-style edge around each box." },
	["look.shading"] = { "Background shading", "A soft fade across each box that gives it a little depth." },
	["look.shadingStart"] = { "Shading start", "The color where the shading begins." },
	["look.shadingEnd"] = { "Shading end", "The color the shading fades into." },
	["look.texture"] = { "Bar texture", "The pattern on health and power bars. These are the original X-Perl textures, plus any shared by other addons." },
	["look.texturedBackground"] = { "Textured bar backgrounds", "Draws a dim copy of the bar texture behind each bar. Turn it off for a plain dark background." },
	["look.thickHealth"] = { "Thick health bar", "Gives the health bar most of the room, with bigger text. Turn it off for two even, thinner bars." },
	["look.smoothBars"] = { "Smooth bar changes", "Bars glide to their new value instead of jumping." },
	["look.invertBars"] = { "Inverted bars", "Bars fill up as health is lost instead of emptying. Some healers find this easier to read. Incoming heals and shields aren't drawn while this is on." },
	["look.incomingHeals"] = { "Show incoming heals", "Heals that are on their way show as a lighter piece at the end of the health bar." },
	["look.incomingHealsColor"] = { "Incoming heal color", "The color of heals on their way." },
	["look.absorbs"] = { "Show absorb shields", "Shields that soak up damage, like Power Word: Shield, show at the end of the health bar." },
	["look.absorbsColor"] = { "Shield color", "The color of shields on the health bar." },
	["look.healthColor"] = { "Health bar color", "How health bars are colored." },
	["look.classBrightness"] = { "Class color brightness", "Turn this down if class colors feel too bright on the bars." },
	["look.healthFull"] = { "Full health", "The bar color at full health." },
	["look.healthLow"] = { "Low health", "The bar color when health is nearly gone." },
	["look.mana"] = { "Mana", "The color of mana bars." },
	["look.rage"] = { "Rage", "The color of rage bars." },
	["look.energy"] = { "Energy", "The color of energy bars." },
	["look.focus"] = { "Focus", "The color of focus, the power hunter pets use." },
	["look.classNames"] = { "Class-colored names", "Players' names show in their class color." },
	["look.hostile"] = { "Hostile", "Name color for creatures that will attack you." },
	["look.unfriendly"] = { "Unfriendly", "Name color for creatures and NPCs that are unfriendly toward you." },
	["look.neutral"] = { "Neutral", "Name color for creatures that leave you alone unless you attack them." },
	["look.friendly"] = { "Friendly", "Name color for friendly NPCs." },
	["look.tapped"] = { "Tapped", "Name color for creatures someone else hit first, so you won't get loot or experience from them." },
	["look.noReaction"] = { "No reaction", "Used when the game doesn't say how a creature feels about you." },
	["look.portraitStyle"] = { "Portrait style", "How portraits are drawn." },
	["look.level"] = { "Level", "Shows each unit's level, colored by how tough they are for you." },
	["look.classIcon"] = { "Class icon", "Shows a small class icon next to players." },
	["look.pvpIcon"] = { "PvP flag", "Shows a flag when someone is flagged for PvP. Your own frame also shows the time left on yours." },
	["look.roleIcons"] = { "Role icons", "Shows tank, healer, or damage icons on party and raid frames, based on the roles set in your group." },
	["look.raidMarker"] = { "Raid marker style", "Where raid markers, like the skull or the star, show." },

	["frame.scale"] = { "Frame size", "How big the frame is. You can also change this in Edit Mode." },
	["frame.width"] = { "Frame width", "Adds room to the name and bars so long names and big numbers fit." },
	["frame.portrait"] = { "Show portrait", "Shows a portrait beside the name." },
	["frame.barText"] = { "Bar text", "The numbers on the health and power bars." },
	["frame.percent"] = { "Percent column", "Shows health and mana as a percentage in a column beside the bars. Rage and energy show their actual amount." },
	["frame.castBar"] = { "Show cast bar", "Shows spell casts in the name box." },
	["frame.power"] = { "Power bar", "Shows mana, rage, or energy under the health bar." },
	["frame.elite"] = { "Elite style", "How elite, rare, and boss enemies are marked. Unless this is set to None, rares always get a label and a pulsing blue glow so you don't walk past one." },
	["frame.creatureType"] = { "Creature type", "Shows what kind of creature it is, like Beast or Undead, under the portrait." },
	["frame.threat"] = { "Threat", "Shows your own threat on this unit, so you can tell how close you are to pulling its attention." },
	["frame.debuffHighlight"] = { "Debuff highlight", "Colors the frame by debuff type, like magic or poison, using the style picked on the General page." },
	["frame.direction"] = { "Direction", "Which way the list grows." },
	["frame.spacing"] = { "Spacing", "The gap between frames." },

	["auras.buffs"] = { "Show buffs", "Shows buff icons near the frame." },
	["auras.buffFilter"] = { "Which buffs", "Which buffs to show." },
	["auras.debuffs"] = { "Show debuffs", "Shows debuff icons near the frame." },
	["auras.debuffFilter"] = { "Which debuffs", "Which debuffs to show." },
	["auras.onTop"] = { "Buffs on top", "Puts the icons above the frame instead of below it." },
	["auras.buffSize"] = { "Buff size", "How big buff icons are." },
	["auras.debuffSize"] = { "Debuff size", "How big debuff icons are." },
	["auras.rows"] = { "Rows", "How many rows of icons can show. Extra icons stay hidden." },

	["player.enabled"] = { "Show player frame", "Use the Perl Infinity player frame. If you turn it off, the game's own player frame comes back after you reload your interface." },
	["player.tallPortrait"] = { "Tall portrait", "Stretches the portrait down beside your experience and reputation bars." },
	["player.groupNumber"] = { "Group number", "In a raid, shows which group you're in." },
	["player.restAnimation"] = { "Resting animation", "While you're resting in an inn or a city, sleepy Zzz float above your portrait and your frame glows gold. Turn this off to show the game's still rest icon instead." },
	["player.xpBar"] = { "Experience bar", "Shows your experience toward the next level, with rested experience in a lighter shade." },
	["player.xpRemaining"] = { "Count down to next level", "Shows the experience you still need instead of what you've earned." },
	["player.repBar"] = { "Reputation bar", "Shows the faction you're watching in your reputation panel." },
	["player.druidMana"] = { "Mana bar in forms", "Keeps your mana in view on a thin bar while you're in bear or cat form." },
	["player.totems"] = { "Totems", "Shows your active totems under your frame, with a timer on each. Right-click one to dismiss it." },
	["player.castLatency"] = { "Show latency", "Shades the end of your cast bar to show your connection delay, so you can start your next cast a little early." },
	["player.keepBlizzardCastBar"] = { "Keep the game's cast bar", "Shows the game's own cast bar as well." },
	["player.keepBlizzardBuffs"] = { "Keep the game's buffs", "Shows the game's own buff icons, normally at the top right of your screen, including weapon enchants like poisons." },
	["player.keepBlizzardDebuffs"] = { "Keep the game's debuffs", "Shows the game's own debuff icons, normally at the top right of your screen." },
	["player.auras.buffs"] = { "Show buffs on this frame", "Shows your buffs next to your frame. Right-click one to cancel it." },
	["player.auras.debuffs"] = { "Show debuffs on this frame", "Shows your debuffs next to your frame." },
	["player.auras.weaponEnchants"] = { "Show weapon enchants on this frame", "Shows temporary weapon enchants like poisons and sharpening stones next to your frame. Right-click one to cancel it." },

	["pet.enabled"] = { "Show pet frame", "Use the Perl Infinity pet frame. If you turn it off, the game's own pet frame comes back after you reload your interface." },
	["pet.name"] = { "Show name", "Shows your pet's name above its bars." },
	["pet.xpBar"] = { "Experience bar", "Shows your pet's experience toward its next level." },
	["pet.happiness"] = { "Happiness", "Shows how your pet feels. Happy pets do more damage. Point at the icon for details." },
	["pet.happinessFlash"] = { "Flash when unhappy", "Makes the icon flash when your pet is unhappy." },

	["target.enabled"] = { "Show target frame", "Use the Perl Infinity target frame. If you turn it off, the game's own target frame comes back after you reload your interface." },
	["target.combo"] = { "Combo points", "How your combo points show on the target frame. Pick any mix." },
	["target.comboPosition"] = { "Dot position", "Which side of the portrait the combo point dots sit on." },

	["focus.enabled"] = { "Show focus frame", "Use the Perl Infinity focus frame. To set a focus, target someone and type /focus. If you turn this off, the game's own focus frame comes back after you reload your interface." },

	["small.targettarget.enabled"] = { "Target of target", "Shows who your target is targeting." },
	["small.targettargettarget.enabled"] = { "Target of target of target", "Shows who your target's target is targeting." },
	["small.focustarget.enabled"] = { "Focus target", "Shows who your focus is targeting." },
	["small.pettarget.enabled"] = { "Pet target", "Shows what your pet is attacking." },
	["small.width"] = { "Frame width", "Adds room to the name and bars on all four frames." },

	["party.enabled"] = { "Show party frames", "Use Perl Infinity party frames. If you turn them off, the game's own party frames come back after you reload your interface." },
	["party.showPlayer"] = { "Include me", "Adds your own frame to the party list." },
	["party.inRaid"] = { "In a raid", "What party frames do when you join a raid." },
	["party.fitIcons"] = { "Make room for icons", "Spaces party members so their buff and debuff icons fit between them. Turn this off to use the spacing above exactly, even if icons cover the next member." },
	["party.mirror"] = { "Mirror layout", "Flips each frame left to right, for when your party sits on the right side of the screen." },
	["party.names"] = { "Show names", "Shows each member's name above their bars." },
	["party.targets"] = { "Party targets", "Shows a small frame with each member's target. They sit beside the party until you drag them somewhere else in Edit Mode." },
	["party.targetWidth"] = { "Width", "How wide the party target frames are." },
	["party.pets"] = { "Party pets", "Shows a small frame for each member's pet. They sit beside the party until you drag them somewhere else in Edit Mode." },
	["party.petScale"] = { "Size", "How big the party pet frames are." },

	["raid.enabled"] = { "Show raid frames", "Use Perl Infinity raid frames. The game's raid frames stay hidden while this is on. If you turn it off, they come back after you reload your interface." },
	["raid.inParty"] = { "Use in parties", "Shows raid frames in a 5-player group too." },
	["raid.hideInBattlegrounds"] = { "Hide in battlegrounds", "Hides raid frames while you're in a battleground." },
	["raid.sortBy"] = { "Sort players by", "How players are split into columns." },
	["raid.alphabetical"] = { "Alphabetical order", "Within each column, lists players by name." },
	["raid.groupGap"] = { "Gap between groups", "The gap between columns." },
	["raid.titles"] = { "Group titles", "Shows a label, like Group 1, above each column. Your own group's label is highlighted." },
	["raid.groups"] = { "Show groups", "Pick which raid groups to show. Handy for hiding a group that's sitting out." },
	["raid.classes"] = { "Show classes", "Pick which classes to show." },
	["raid.healthText"] = { "Health text", "The text on each health bar." },
	["raid.mana"] = { "Show mana bars", "Adds a thin power bar under each health bar." },
	["raid.manaPercent"] = { "Mana percent", "Shows mana as a percentage on the power bar." },
	["raid.icons"] = { "Icons", "Small buff or debuff icons on each raid frame." },
	["raid.iconsFilter"] = { "Only what I can cast or dispel", "Buffs: only ones you can cast. Debuffs: only ones your class can remove." },
	["raid.iconPosition"] = { "Icon position", "Where the icons sit on each raid frame." },
	["raid.bossDebuff"] = { "Boss debuff in the middle", "Shows the most important boss debuff as an icon in the middle of the frame. The game decides which debuffs count; Forever doesn't let addons pick specific debuffs on friendly players." },
	["raid.bossDebuffAlpha"] = { "Boss icon opacity", "How see-through the boss icon is, so you can still read the health bar under it." },
	["raid.pets"] = { "Show raid pets", "Adds a column of hunter and warlock pets." },
	["raid.petsAttached"] = { "Attach to raid frames", "Keeps the pet column right next to your raid frames. Turn it off to move pets on their own in Edit Mode." },

	["tanks.enabled"] = { "Tank targets window", "Shows the window in raids when there are tanks to list. Click any name in it to target that unit." },
	["tanks.source"] = { "Who counts as a tank", "Which players the window lists." },
	["tanks.max"] = { "Number of tanks", "The most tanks the window lists." },
	["tanks.showTargetTarget"] = { "Show who the enemy targets", "Adds a third column with who each tank's enemy is attacking, so you can catch it turning on a healer." },
	["tanks.numbers"] = { "Number the tanks", "Puts a number next to each tank." },
	["tanks.growUp"] = { "Grow upward", "New rows appear above instead of below." },
	["tanks.healthText"] = { "Health text", "The text on each health bar in the window." },
	["tanks.width"] = { "Width", "How wide each name is." },
	["tanks.height"] = { "Height", "How tall each row is." },
	["tanks.alpha"] = { "Opacity", "How see-through the window is." },

	["healers.enabled"] = { "Healer mana window", "Lists your raid's healers with their mana and what they're casting. If you're a druid, right-click a name to cast Innervate on them." },
	["healers.classes"] = { "Classes", "Which classes to list." },
	["healers.targets"] = { "Show their targets", "Adds a column with each healer's target." },
	["healers.growUp"] = { "Grow upward", "New rows appear above instead of below." },
	["healers.width"] = { "Width", "How wide each mana bar is." },
	["healers.height"] = { "Height", "How tall each row is." },
	["healers.alpha"] = { "Opacity", "How see-through the window is." },

	["tools.layout"] = { "Saved layout", "Pick a layout to load or delete." },
	layoutSave = { "Save current groups", "Saves who is in which group right now, under a name you choose." },
	layoutLoad = { "Load layout", "Moves raid members into the groups saved in the layout you picked. You need to be the raid leader or an assistant, and it can't run during combat. Anyone who isn't in the raid is swapped for someone of the same class." },
	layoutDelete = { "Delete layout", "Deletes the layout you picked." },
	buffCheck = { "Buff check", "Lists who in your group is missing a class buff, like Power Word: Fortitude or Mark of the Wild, in your chat window. Only you see it. Works out of combat." },
	["tools.buffHelper"] = { "Show who's missing a buff", "When you point at a group member's buff, its tooltip lists who in your group doesn't have it. Hold Alt to see who does. Works out of combat." },
	["tools.buffHelperSort"] = { "Sort names by", "The order of names in that list." },
	["tools.buffHelperVisibleOnly"] = { "Only groups I can see", "Leaves out raid groups you've hidden on the Raid page." },
	raidNames = { "Raid names", "Opens a list of your raid's names that you can copy, handy for attendance or loot sheets." },

	["profiles.active"] = { "Active profile", "The set of settings this character uses. Each character remembers its own choice." },
	["profiles.copyFrom"] = { "Copy settings from", "Replaces this profile's settings with a copy of another profile's." },
	profileNew = { "New profile", "Makes a new profile, starting from your current settings." },
	profileRename = { "Rename profile", "Gives this profile a new name." },
	profileDelete = { "Delete profile", "Deletes this profile. Characters that used it switch to another one." },
	profileReset = { "Reset profile", "Puts every setting in this profile back to its default. Frame positions don't move." },
	["profiles.newCharacters"] = { "New characters use", "The profile a character starts with the first time you log in with Perl Infinity." },
	profileExport = { "Export profile", "Turns this profile into a line of text you can share. Anyone with Perl Infinity can import it." },
	profileImport = { "Import profile", "Adds a profile from text someone shared with you." },
	positionsReset = { "Reset frame positions", "Moves every Perl Infinity frame back to its starting spot in your current Edit Mode layout." },
}

-- Choices: value = label, or value = { label, tooltip }
L.Choices = {
	["general.unitTooltips"] = { always = "Always", shift = "Hold Shift", alt = "Hold Alt", ctrl = "Hold Ctrl", never = "Never" },
	["general.auraTooltips"] = { always = "Always", never = "Never" },
	["range.mode"] = {
		auto = { "Automatic", "Uses one of your own spells: a heal or buff for friends and an attack for enemies, so frames fade exactly when your spells can't reach." },
		yards40 = { "40 yards", "Uses the game's group range check, about 40 yards, for party and raid members." },
	},
	["range.part"] = { frame = "Whole frame", name = "Name box only", bars = "Bars only" },
	["highlight.debuffs"] = {
		off = "Off",
		dispellable = { "Ones I can dispel", "Only debuffs your class can remove, like with Cleanse, Remove Curse, or Cure Poison." },
		all = "All debuffs",
	},
	["highlight.debuffStyle"] = { border = "Border", background = "Background", both = "Both" },
	["auras.spirals"] = { off = "Off", mine = "Mine only", all = "All" },
	["auras.countdown"] = { off = "Off", mine = "Mine only", all = "All" },
	["castBars.time"] = { hidden = "Hidden", inside = "Inside the bar", outside = "Next to the bar" },
	["look.shading"] = { off = "Off", vertical = "Top to bottom", horizontal = "Left to right" },
	["look.healthColor"] = {
		gradient = { "Red to green", "The original Perl look. Full health is green and shifts through yellow to red as it drops." },
		class = { "Class color", "Players use their class color. Creatures still go from green to red." },
		custom = { "Custom", "Pick your own colors for full and low health." },
	},
	["look.portraitStyle"] = {
		["3d"] = { "3D model", "A moving 3D portrait. It switches to a picture when the game can't show the model." },
		["2d"] = { "Picture", "A still picture of the face." },
		class = { "Class icon", "Players show their class icon. Creatures show a picture." },
	},
	["look.raidMarker"] = { corner = "Small, in the corner", name = "Large, on the name" },
	["player.groupNumber"] = { hidden = "Hidden", above = "Above the frame", name = "Next to my name" },
	["frame.barText"] = {
		none = "None",
		current = { "Current", "The current amount, like 3,412." },
		currentMax = { "Current and max", "Current and full amounts, like 3,412 / 4,120." },
		missing = { "Missing health", "How much health is missing, like -708, so you know how much healing it takes. Blank at full health." },
		missingMax = { "Missing and max", "Missing and full health, like -708 / 4,120." },
	},
	["pet.happiness"] = { always = "Always", unhappy = "Only when unhappy", hidden = "Hidden" },
	["auras.buffFilter"] = {
		all = "All",
		mine = { "Mine", "Only buffs you or your pet cast." },
		castable = { "Ones I can cast", "Only buffs you could cast yourself, handy for spotting whether yours is there." },
	},
	["auras.debuffFilter"] = {
		all = "All",
		mine = { "Mine", "Only debuffs you or your pet cast." },
		dispellable = { "Ones I can dispel", "Only debuffs your class can remove." },
	},
	["frame.elite"] = {
		dragon = { "Dragon", "Wraps the portrait in a gold dragon for elites and bosses, or a silver one for rares, and colors the frame's edges to match." },
		text = { "Label", "A tag above the name says Elite, Rare, or Boss, and the frame's edges change color." },
		none = { "None", "No marker. Elite levels still get a plus sign, like 60+." },
	},
	["frame.threat"] = { off = "Off", gauge = "Gauge on portrait", bar = "Bar on name box" },
	["target.combo"] = { dots = "Dots", number = "Number", fill = "Fill the name box" },
	["target.comboPosition"] = { above = "Above", below = "Below", left = "Left", right = "Right" },
	["frame.debuffHighlight"] = { off = "Off", friendly = "Friendly targets", enemy = "Enemy targets", both = "Both" },
	["party.inRaid"] = {
		keep = { "Keep party frames", "Your own raid group stays on screen alongside your raid frames." },
		hide = { "Hide party frames", "Only your raid frames show." },
		smallRaid = { "Only in one-group raids", "If the whole raid fits in one group, party frames show. Bigger raids use raid frames only." },
	},
	["frame.direction"] = { down = "Down", up = "Up", right = "Right", left = "Left" },
	["raid.sortBy"] = {
		group = { "Group", "One column per raid group." },
		class = { "Class", "One column per class." },
		role = { "Role", "Tanks first, then healers, then damage, five to a column." },
	},
	["raid.healthText"] = { none = "None", percent = "Percent", current = "Current", missing = "Missing health" },
	["raid.icons"] = { none = "None", buffs = "Buffs", debuffs = "Debuffs" },
	["raid.iconPosition"] = { inside = "Inside the frame", right = "Outside, on the right", below = "Below" },
	["tanks.source"] = {
		mainTanks = { "Main tanks, then warriors", "Players set as main tank in your raid. If nobody is, every warrior is listed." },
		mainTanksOnly = { "Main tanks only", "Only players set as main tank in your raid." },
		role = { "Tank role", "Players who picked the tank role." },
	},
	["tanks.healthText"] = { percent = "Percent", missing = "Missing health", missingMax = "Missing and max" },
	["tools.buffHelperSort"] = { group = "Group", class = "Class", none = "Don't sort" },
}

-- Extra words people might search for.
L.Tags = {
	["range.enabled"] = "range finder distance 40 yards",
	["highlight.debuffs"] = "dispel cure decurse cleanse magic curse poison disease",
	["highlight.hots"] = "hot renew rejuvenation regrowth",
	["highlight.hotBars"] = "hot prediction hot bars timer",
	["highlight.healing"] = "being healed incoming heals",
	["highlight.aggro"] = "threat tanking",
	["auras.markStealable"] = "purge stealable spellsteal",
	["player.auras.weaponEnchants"] = "poison oil sharpening stone rockbiter flametongue temporary enchant",
	["party.fitIcons"] = "gap overlap spacing buffs debuffs auras",
	["player.restAnimation"] = "rest rested resting inn city zzz sleep glow",
	["frame.elite"] = "elite rare rare elite boss dragon silver gold glow",
	["player.keepBlizzardBuffs"] = "hide blizzard default buff frame auras",
	["player.keepBlizzardDebuffs"] = "hide blizzard default debuff frame auras",
	["auras.spirals"] = "cooldown swipe",
	["auras.countdown"] = "timer duration omnicc",
	["look.texture"] = "statusbar sharedmedia",
	["look.incomingHeals"] = "heal prediction healcomm",
	["look.healthColor"] = "gradient class colors",
	["frame.scale"] = "scale size",
	["frame.barText"] = "values healer mode deficit",
	["frame.threat"] = "aggro threat meter",
	["raid.sortBy"] = "sort by class role group",
	["tanks.enabled"] = "main tank mt assist",
	["healers.enabled"] = "casting monitor mana innervate",
}

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

L.STATUS_DEAD = "Dead"
L.STATUS_GHOST = "Ghost"
L.STATUS_OFFLINE = "Offline"
L.STATUS_FEIGN = "Feign"
L.STATUS_AFK = "AFK"
L.CLASS_BOSS = "Boss"
L.CLASS_ELITE = "Elite"
L.CLASS_RARE_ELITE = "Rare elite"
L.CLASS_RARE = "Rare"
L.CAST_INTERRUPTED = "Interrupted"
L.CAST_FAILED = "Failed"
L.GROUP_N = "Group %d"
L.NAME_WITH_GROUP = "%s (%d)"
L.PVP_TIMER = "PvP %d:%02d"
L.XP_TO_GO = "%s to go"
L.NO_FACTION = "No faction watched"
L.PET_DAMAGE = "Damage: %d%%"
L.AGGRO = "AGGRO"
L.PET_AGGRO = "PET AGGRO"
L.TANKS_TITLE = "Tanks"
L.HEALERS_TITLE = "Healers"
L.TIP_MISSING_BUFF = "Missing it:"
L.TIP_HAVE_BUFF = "Have it:"

L.TEXTURE_PERL = "Perl"
L.TEXTURE_BANTO = "BantoBar"
L.TEXTURE_SMOOTH = "Smooth"
L.TEXTURE_FLAT = "Flat"
L.TEXTURE_VINES = "Vines"
L.TEXTURE_STONE = "Stone"
L.TEXTURE_LIGHTNING = "Lightning"
L.TEXTURE_METAL = "Brushed metal"
L.TEXTURE_SEGMENTED = "Segmented"
L.TEXTURE_SEGMENTED_WIDE = "Segmented wide"

L.DIRECTION_DOWN = "Down"
L.DIRECTION_UP = "Up"
L.DIRECTION_RIGHT = "Right"
L.DIRECTION_LEFT = "Left"
L.SORT_GROUP = "Group"
L.SORT_CLASS = "Class"
L.SORT_ROLE = "Role"

-- Edit Mode names and popup rows, matching Blizzard's own wording.
L.EM_PLAYER = "Player (Perl Infinity)"
L.EM_PET = "Pet (Perl Infinity)"
L.EM_PET_TARGET = "Pet target (Perl Infinity)"
L.EM_TARGET = "Target (Perl Infinity)"
L.EM_TOT = "Target of target (Perl Infinity)"
L.EM_TOTOT = "Target of target of target (Perl Infinity)"
L.EM_FOCUS = "Focus (Perl Infinity)"
L.EM_FOCUS_TARGET = "Focus target (Perl Infinity)"
L.EM_PARTY = "Party (Perl Infinity)"
L.EM_PARTY_TARGETS = "Party targets (Perl Infinity)"
L.EM_PARTY_PETS = "Party pets (Perl Infinity)"
L.EM_RAID = "Raid (Perl Infinity)"
L.EM_RAID_PETS = "Raid pets (Perl Infinity)"
L.EM_TANKS = "Tank targets (Perl Infinity)"
L.EM_HEALERS = "Healer mana (Perl Infinity)"
L.EM_LAYOUTS = "Raid layouts (Perl Infinity)"
L.EM_AGGRO = "Aggro warning (Perl Infinity)"
L.EM_FRAME_SIZE = "Frame size"
L.EM_FRAME_WIDTH = "Frame width"
L.EM_SHOW_PORTRAIT = "Show portrait"
L.EM_BUFFS_ON_TOP = "Buffs on top"
L.EM_DIRECTION = "Direction"
L.EM_SPACING = "Spacing"
L.EM_FIT_ICONS = "Make room for icons"
L.EM_MIRROR = "Mirror layout"
L.EM_SORT_BY = "Sort players by"
L.EM_ROWS = "Number of tanks"
L.EM_GROW_UP = "Grow upward"
L.EM_SHOW_TARGETS = "Show their targets"
L.EM_MORE_OPTIONS = "More options"

---------------------------------------------------------------------------
-- Dialogs
---------------------------------------------------------------------------

L.DIALOG_NEW_PROFILE = "Name your new profile. It starts as a copy of your current settings."
L.DIALOG_CREATE = "Create"
L.DIALOG_SAVE = "Save"
L.DIALOG_COPY = "Copy"
L.DIALOG_RENAME_PROFILE = "Rename this profile."
L.DIALOG_DELETE_PROFILE = "Delete %s? Characters using it will switch to another profile."
L.DIALOG_RESET_PROFILE = "Put %s back to the default settings? Your frame positions won't move."
L.DIALOG_COPY_PROFILE = "Copy every setting from %s into %s? Its current settings will be replaced."
L.DIALOG_EXPORT = "Copy this text and share it. Anyone with Perl Infinity can import it. Press Ctrl+C to copy (Cmd+C on a Mac)."
L.DIALOG_IMPORT = "Paste a profile here."
L.DIALOG_IMPORT_BUTTON = "Import"
L.IMPORTED_PROFILE = "Imported"
L.DIALOG_RESET_POSITIONS = "Move every Perl Infinity frame back to where it started in this Edit Mode layout?"
L.DIALOG_SAVE_LAYOUT = "Name this raid layout."
L.DIALOG_RAID_NAMES = "Your group's names. Press Ctrl+C to copy (Cmd+C on a Mac)."

---------------------------------------------------------------------------
-- Self-test
---------------------------------------------------------------------------

L.SELFTEST_START = "Checking Perl Infinity against your game. This takes a few seconds; please stay out of combat."
L.SELFTEST_COMBAT = "The self-test runs out of combat. Try again after the fight."
L.SELFTEST_DONE = "Self-test finished: %d checks passed, %d failed, %d things missing, %d problems logged. Type /reload to save the report."

---------------------------------------------------------------------------
-- Samples for previews
---------------------------------------------------------------------------

L.SAMPLE_TARGET = "Hogger"
L.SAMPLE_CREATURE_TYPE = "Humanoid"
L.SAMPLE_FOCUS = "Rak'shiri"
L.SAMPLE_PET = "Wolf"
L.SAMPLE_PET_TARGET = "Kobold Miner"
L.SAMPLE_TOT = "Mirelle"
L.SAMPLE_TOTOT = "Hogger"
L.SAMPLE_FOCUS_TARGET = "Aldric"
L.SAMPLE_PARTY_1 = "Aldric"
L.SAMPLE_PARTY_2 = "Mirelle"
L.SAMPLE_PARTY_3 = "Thorne"
L.SAMPLE_PARTY_4 = "Kesha"
L.SAMPLE_RAID_1 = "Aldric"
L.SAMPLE_RAID_NAMES = { "Aldric", "Mirelle", "Bram", "Thorne", "Elowen", "Garrick", "Sable", "Torvan", "Kesha", "Dunmore" }
L.SAMPLE_CAST = "Hearthstone"
L.SAMPLE_ENEMY_CAST = "Fireball"
L.SAMPLE_FACTION = "Stormwind 2,400 / 6,000"
