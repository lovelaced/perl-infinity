-- Tints a frame's border and background by debuff type: blue for magic,
-- purple for curses, brown for disease, green for poison.
--
-- Debuff types are secret in combat, so the frame never reads them. Instead
-- an aura "slot" in the frame's container picks the debuff, and the game
-- colors two textures we hand it (a border and a wash) by its type.
local _, ns = ...

local AuraHost, Media = ns.AuraHost, ns.Media

local DispelHighlight = ns.Element("DispelHighlight", {})

-- How strongly the wash adds the debuff's color over the frame. It covers
-- the bars too, so it has to stay faint enough that a green poison wash
-- over a green health bar still shows where the bar ends.
--
-- The game colors and shows the outline and wash textures itself, and may
-- reset their alpha as it does, which would put the wash back at full
-- strength. So each part sits in its own holder frame, and the holder's
-- alpha sets how strong it is. The game never touches the holders.
local WASH_STRENGTH = 0.15

-- Which units this frame should tint, from settings. Your own frame has an
-- on/off switch; target and focus choose friends, enemies or both.
local function Mode(frame, conf)
	if frame.spec.group then
		return ns.db.highlight.debuffs
	end
	local who = conf.debuffHighlight
	if who == true or (type(who) == "string" and who ~= "off") then
		return "all"
	end
	return "off"
end

function DispelHighlight.Enabled(frame, conf)
	return not frame.preview and Mode(frame, conf) ~= "off"
end

-- Shows the outline, the wash or both. Hidden parts stay registered, since
-- the game owns their visibility; their holders are just fully transparent.
function DispelHighlight.ApplyStyle(button, style)
	button.EdgeLayer:SetAlpha(style ~= "background" and 1 or 0)
	button.WashLayer:SetAlpha(style ~= "border" and WASH_STRENGTH or 0)
	button.style = style
end

local function Layer(button)
	local layer = CreateFrame("Frame", nil, button)
	layer:SetAllPoints()
	return layer
end

local function InitSlot(button, frame)
	-- The slot covers the whole frame; it must never take clicks or tooltips
	-- from the unit button underneath.
	button:EnableMouse(false)
	button:SetMouseMotionEnabled(false)
	button:ClearAllPoints()
	button:SetPoint("TOPLEFT", frame.NameBox, "TOPLEFT", -2, 2)
	button:SetPoint("BOTTOMRIGHT", frame.StatsBox, "BOTTOMRIGHT", 2, -2)

	local washLayer = Layer(button)
	local edgeLayer = Layer(button)
	edgeLayer:SetFrameLevel(washLayer:GetFrameLevel() + 1)
	button.WashLayer, button.EdgeLayer = washLayer, edgeLayer

	-- A 3 pixel outline made of four lines, each colored by the game.
	local edges = {}
	for i, points in ipairs({
		{ "TOPLEFT", "TOPRIGHT", 0, -3 },
		{ "BOTTOMLEFT", "BOTTOMRIGHT", 0, 3 },
		{ "TOPLEFT", "BOTTOMLEFT", 3, 0 },
		{ "TOPRIGHT", "BOTTOMRIGHT", -3, 0 },
	}) do
		local edge = edgeLayer:CreateTexture(nil, "OVERLAY")
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

	local wash = washLayer:CreateTexture(nil, "BACKGROUND")
	wash:SetTexture(Media.WHITE)
	wash:SetPoint("TOPLEFT", 5, -5)
	wash:SetPoint("BOTTOMRIGHT", -5, 5)
	wash:SetBlendMode("ADD")
	button.Wash = wash

	DispelHighlight.ApplyStyle(button, frame.dispelStyle or "both")

	local options = {
		style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
		showWhenHarmful = true,
		customDispelColorMap = AuraHost.DispelColors(),
	}
	for _, edge in ipairs(edges) do
		button:AddDispelTypeTexture(edge, options)
	end
	button:AddDispelTypeTexture(wash, options)
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
		DispelHighlight.ApplyStyle(button, frame.dispelStyle)
	end
end

function DispelHighlight.Disable(frame)
	local container = frame.AuraContainers and frame.AuraContainers.icons
	if container and container.slots.dispel then
		container:SetAuraSlotEnabled("dispel", false)
	end
end

-- Target and focus only tint for friends, enemies, or both. Your own frame's
-- switch is just on or off, which Configure already handled.
function DispelHighlight.Update(frame, unit)
	local container = frame.AuraContainers and frame.AuraContainers.icons
	if not container or not container.slots.dispel or frame.spec.group then
		return
	end
	local who = frame:Conf().debuffHighlight
	if type(who) ~= "string" then
		return
	end
	local friendly = UnitCanAssist("player", unit)
	local on = who == "both" or (who == "friendly" and friendly) or (who == "enemy" and not friendly)
	container:SetAuraSlotEnabled("dispel", on and true or false)
end
