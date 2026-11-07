-- Art and fonts. The bar textures are the original X-Perl set; any textures
-- other addons share through LibSharedMedia show up in the list too.
local _, ns = ...

local Media = {}
ns.Media = Media

local L = ns.L
local PATH = "Interface\\AddOns\\PerlInfinity\\Media\\"
Media.PATH = PATH

Media.BAR_TEXTURES = {
	{ key = "perl", label = L.TEXTURE_PERL, path = PATH .. "XPerl_StatusBar" },
	{ key = "banto", label = L.TEXTURE_BANTO, path = PATH .. "XPerl_StatusBar2" },
	{ key = "smooth", label = L.TEXTURE_SMOOTH, path = PATH .. "XPerl_StatusBar3" },
	{ key = "flat", label = L.TEXTURE_FLAT, path = PATH .. "XPerl_StatusBar4" },
	{ key = "vines", label = L.TEXTURE_VINES, path = PATH .. "XPerl_StatusBar5" },
	{ key = "stone", label = L.TEXTURE_STONE, path = PATH .. "XPerl_StatusBar6" },
	{ key = "lightning", label = L.TEXTURE_LIGHTNING, path = PATH .. "XPerl_StatusBar7" },
	{ key = "metal", label = L.TEXTURE_METAL, path = PATH .. "XPerl_StatusBar8" },
	{ key = "segmented", label = L.TEXTURE_SEGMENTED, path = PATH .. "XPerl_StatusBar9" },
	{ key = "segmentedWide", label = L.TEXTURE_SEGMENTED_WIDE, path = PATH .. "XPerl_StatusBar10" },
}

local byKey = {}
for _, texture in ipairs(Media.BAR_TEXTURES) do
	byKey[texture.key] = texture.path
end

local function SharedMedia()
	return LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
end

-- Every bar texture to offer, ours first, then shared ones by name.
function Media.BarTextureChoices()
	local choices = {}
	for _, texture in ipairs(Media.BAR_TEXTURES) do
		choices[#choices + 1] = texture
	end
	local LSM = SharedMedia()
	if LSM then
		for _, name in ipairs(LSM:List("statusbar")) do
			choices[#choices + 1] = { key = "lsm:" .. name, label = name, path = LSM:Fetch("statusbar", name) }
		end
	end
	return choices
end

function Media.BarTexture(key)
	key = key or ns.db.look.texture
	local path = byKey[key]
	if path then
		return path
	end
	local LSM = SharedMedia()
	local name = key:match("^lsm:(.+)$")
	if LSM and name then
		return LSM:Fetch("statusbar", name, true) or byKey.perl
	end
	return byKey.perl
end

Media.BAR_BACKGROUND = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
Media.WHITE = "Interface\\Buttons\\WHITE8X8"
Media.TOOLTIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
Media.FRAME_BACK = PATH .. "XPerl_FrameBack"
Media.THIN_EDGE = PATH .. "XPerl_ThinEdge"
Media.DEBUFF_EDGE = PATH .. "XPerl_Curse"
Media.HIGHLIGHT = PATH .. "XPerl_Highlight"
Media.GRADIENT = "Interface\\ChatFrame\\ChatFrameBackground"
Media.SPARK = PATH .. "XPerl_ArcaneBarSpark"
Media.FLASH = PATH .. "XPerl_ArcaneBarFlash"
Media.ELITE = PATH .. "XPerl_Elite"
Media.RARE = PATH .. "XPerl_Rare"
Media.RANGE_HAND = PATH .. "XPerl_30Yard"
Media.EYE = PATH .. "XPerl_EyeBall"
Media.STEAL = PATH .. "StealMe"
Media.GAUGE = PATH .. "GaugeCircle"
Media.GAUGE_NEEDLE = PATH .. "GaugeBarNeedle"
Media.ROLE = {
	TANK = PATH .. "XPerl_RoleTank",
	HEALER = PATH .. "XPerl_RoleHealer",
	DAMAGER = PATH .. "XPerl_RoleDamage",
}
Media.RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
Media.DEBUFF_BORDER = "Interface\\Buttons\\UI-Debuff-Overlays"

-- The tooltip-edged dark box that every X-Perl frame is made of.
Media.BOX_BACKDROP = {
	bgFile = Media.FRAME_BACK,
	edgeFile = Media.TOOLTIP_BORDER,
	tile = true,
	tileSize = 32,
	edgeSize = 16,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Raid frames use a thinner edge so forty of them stay readable.
Media.THIN_BACKDROP = {
	bgFile = Media.FRAME_BACK,
	edgeFile = Media.THIN_EDGE,
	tile = true,
	tileSize = 32,
	edgeSize = 10,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- X-Perl's thick bracket edge on its own, for the glow around rare enemies
-- and around your frame while you're resting.
Media.GLOW_BACKDROP = {
	edgeFile = Media.DEBUFF_EDGE,
	edgeSize = 16,
}
