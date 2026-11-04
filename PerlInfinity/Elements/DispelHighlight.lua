-- Tints a frame's border and background by debuff type: blue for magic,
-- purple for curses, brown for disease, green for poison.
--
-- Debuff types are secret in combat, so the frame never reads them. Instead
-- an aura "slot" in the frame's container picks the debuff, and the game
-- colors two textures we hand it (a border and a wash) by its type.
local _, ns = ...

local AuraHost, Media = ns.AuraHost, ns.Media

local DispelHighlight = ns.Element("DispelHighlight", {})

-- Which units this frame should tint, from settings.
local function Mode(frame, conf)
	if frame.spec.group then
		return ns.db.highlight.debuffs
	end
	if conf.debuffHighlight and conf.debuffHighlight ~= "off" then
		return "all"
	end
	return "off"
end

function DispelHighlight.Enabled(frame, conf)
	return not frame.preview and Mode(frame, conf) ~= "off"
end

local function InitSlot(button, frame)
	-- The slot covers the whole frame; it must never take clicks or tooltips
	-- from the unit button underneath.
	button:EnableMouse(false)
	button:SetMouseMotionEnabled(false)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", frame.NameBox, "TOPLEFT", -2, 2)
	button:SetPoint("BOTTOMRIGHT", frame.StatsBox, "BOTTOMRIGHT", 2, -2)

	-- A 3 pixel outline made of four lines, each colored by the game.
	local edges = {}
	for i, points in ipairs({
		{ "TOPLEFT", "TOPRIGHT", 0, -3 },
		{ "BOTTOMLEFT", "BOTTOMRIGHT", 0, 3 },
		{ "TOPLEFT", "BOTTOMLEFT", 3, 0 },
		{ "TOPRIGHT", "BOTTOMRIGHT", -3, 0 },
	}) do
		local edge = button:CreateTexture(nil, "OVERLAY")
		edge:SetTexture(Media.WHITE)
		edge:SetPoint(points[1])
		edge:SetPoint(points[2])
		if points[3] ~= 0 then
			edge:SetWidth(math.abs(points[3]))
		else
			edge:SetHeight(math.abs(points[4]))
		end
		edges[i] = edge
	end
	button.Edges = edges

	local wash = button:CreateTexture(nil, "BACKGROUND")
	wash:SetTexture(Media.WHITE)
	wash:SetPoint("TOPLEFT", 5, -5)
	wash:SetPoint("BOTTOMRIGHT", -5, 5)
	wash:SetBlendMode("ADD")
	button.Wash = wash

	DispelHighlight.Register(button, frame.dispelStyle or "both")
end

-- Color maps: full color for the outline, a faint wash for the background,
-- and clear for whichever part the style turns off. Hidden parts stay
-- registered with a clear map, since the game owns their visibility.
local maps = {}
local function ColorMap(kind)
	if not maps[kind] then
		local map = {}
		for name, color in pairs(AuraHost.DispelColors()) do
			local alpha = kind == "wash" and 0.3 or (kind == "clear" and 0 or 1)
			map[name] = CreateColor(color.r, color.g, color.b, alpha)
		end
		maps[kind] = map
	end
	return maps[kind]
end

function DispelHighlight.Register(button, style)
	local preserve = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
	local function Bind(texture, map)
		if texture.registered then
			button:RemoveDispelTypeTexture(texture)
		end
		button:AddDispelTypeTexture(texture, { style = preserve, showWhenHarmful = true, customDispelColorMap = map })
		texture.registered = true
	end
	local edgeMap = style ~= "background" and ColorMap("edge") or ColorMap("clear")
	for _, edge in ipairs(button.Edges) do
		Bind(edge, edgeMap)
	end
	Bind(button.Wash, style ~= "border" and ColorMap("wash") or ColorMap("clear"))
	button.style = style
end

function DispelHighlight.Create(frame)
	frame.dispelInit = function(button)
		InitSlot(button, frame)
	end
end

local CANDIDATES = { includeDispelTypes = { Magic = true, Curse = true, Disease = true, Poison = true } }

function DispelHighlight.Configure(frame, conf)
	local container = AuraHost.Get(frame)
	if not container then
		return
	end
	local mode = Mode(frame, conf)
	local filter = mode == "dispellable" and "HARMFUL|RAID" or "HARMFUL"
	frame.dispelStyle = ns.db.highlight.debuffStyle
	if AuraHost.EnsureSlot(container, "dispel", filter, frame.dispelInit, CANDIDATES) then
		container:SetAuraSlotFilterString("dispel", filter)
		container:SetAuraSlotEnabled("dispel", true)
		ns.Combat:RunAuraSafe(frame.dispelInit, DispelHighlight.Restyle, frame)
	end
end

function DispelHighlight.Restyle(frame)
	local container = AuraHost.Get(frame)
	local button = container and container.slots.dispel and container:GetAuraSlotFrame("dispel")
	if button and button.Edges and button.style ~= frame.dispelStyle then
		DispelHighlight.Register(button, frame.dispelStyle)
	end
end

function DispelHighlight.Disable(frame)
	local container = frame.AuraContainers and frame.AuraContainers.icons
	if container and container.slots.dispel then
		container:SetAuraSlotEnabled("dispel", false)
	end
end

-- Target and focus only tint for friends, enemies, or both.
function DispelHighlight.Update(frame, unit)
	local container = frame.AuraContainers and frame.AuraContainers.icons
	if not container or not container.slots.dispel or frame.spec.group then
		return
	end
	local who = frame:Conf().debuffHighlight
	local friendly = UnitCanAssist("player", unit)
	local on = who == "both" or (who == "friendly" and friendly) or (who == "enemy" and not friendly)
	container:SetAuraSlotEnabled("dispel", on and true or false)
end
