-- The X-Perl box: a dark tiled panel inside the classic tooltip edge, with a
-- soft gradient on top. Every unit frame is a few of these butted together
-- (name, portrait, level, stats), which is the look Perl has had since 2005.
--
-- Boxes never take the mouse, so clicks fall through to the secure button
-- underneath.
local _, ns = ...

local Box = ns:NewModule("Box")
local Media, Colors = ns.Media, ns.Colors

local boxes = setmetatable({}, { __mode = "k" })

-- How far above a unit frame's Content each layer sits. Boxes are 1 above
-- it, with their bars and text at 2 and the 3D portrait just above its box.
-- The elite dragon goes over the name and stats boxes but under the
-- portrait and level boxes, so it wraps the portrait the way X-Perl drew
-- it. Outlines and other holders use 5 to 10, and Overlay holds the small
-- icons (raid marker, leader crown, PvP badge) in front of all of it.
-- Levels above a frame's Content. Aura icons and the debuff outline sit in
-- front of the dragon and the type, level and portrait boxes, so a long row
-- of icons never slides under them.
Box.LEVEL = { DRAGON = 3, FRONT = 4, AURAS = 5, OVERLAY = 12 }

function Box.Raise(frame, content, layer)
	frame:SetFrameLevel(content:GetFrameLevel() + layer)
end

-- A holder for text that must stay readable in front of the elite dragon.
-- It's a child of `parent` (a box or the cast bar), so it still fades and
-- hides with it, but it's drawn at the front.
function Box.TextLayer(parent, content)
	local layer = CreateFrame("Frame", nil, parent)
	layer:SetAllPoints()
	Box.Raise(layer, content, Box.LEVEL.FRONT)
	return layer
end

-- How far a glow reaches past the region it surrounds. The bright line sits
-- 1 to 4 pixels inside the edge texture, so this puts it just outside the
-- boxes' own edges.
local GLOW_OUTSET = 5

function Box.ApplyLook(box)
	local look = ns.db.look
	local background = Colors.Hex(look.background)
	box:SetBackdropColor(background.r, background.g, background.b, look.backgroundAlpha)
	local border = box.borderOverride or Colors.Hex(look.border)
	box:SetBackdropBorderColor(border.r, border.g, border.b, 1)

	local shade = box.Shade
	if look.shading == "off" then
		shade:Hide()
	else
		shade:Show()
		local orientation = look.shading == "horizontal" and "HORIZONTAL" or "VERTICAL"
		shade:SetGradient(orientation, Colors.Hex(look.shadingEnd), Colors.Hex(look.shadingStart))
	end
end

-- Creates a box. `thin` uses the slimmer raid edge.
function Box.Create(parent, thin)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	local backdrop = thin and Media.THIN_BACKDROP or Media.BOX_BACKDROP
	box:SetBackdrop(backdrop)
	box.thin = thin

	local inset = backdrop.insets.left
	local shade = box:CreateTexture(nil, "BORDER")
	shade:SetTexture(Media.GRADIENT)
	shade:SetBlendMode("ADD")
	shade:SetPoint("TOPLEFT", inset, -inset)
	shade:SetPoint("BOTTOMRIGHT", -inset, inset)
	box.Shade = shade

	boxes[box] = true
	Box.ApplyLook(box)
	return box
end

-- Tints the border (debuff highlight, combat flash). Pass nil to restore.
function Box.SetBorderColor(box, color)
	box.borderOverride = color
	local border = color or Colors.Hex(ns.db.look.border)
	box:SetBackdropBorderColor(border.r, border.g, border.b, 1)
end

function Box:Init()
	ns.Config:Subscribe("look", self, function()
		for box in pairs(boxes) do
			Box.ApplyLook(box)
		end
	end)
end

local function StartGlow(glow, color, seconds)
	glow:SetBackdropBorderColor(color.r, color.g, color.b, 1)
	glow.Fade:SetDuration(seconds)
	glow:SetAlpha(1)
	if not glow.Pulse:IsPlaying() then
		glow.Pulse:Play()
	end
end

local function StopGlow(glow)
	glow.Pulse:Stop()
	glow:SetAlpha(0)
end

-- A colored rim just outside `anchor`, drawn with X-Perl's thick bracket
-- edge behind the boxes. glow:Start(color, seconds) makes it breathe, and
-- glow:Stop() hides it. The game runs the animation, so a glowing frame
-- costs no Lua time while it pulses.
function Box.Glow(content, anchor)
	local glow = CreateFrame("Frame", nil, content, "BackdropTemplate")
	glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -GLOW_OUTSET, GLOW_OUTSET)
	glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", GLOW_OUTSET, -GLOW_OUTSET)
	glow:SetFrameLevel(content:GetFrameLevel())
	glow:SetBackdrop(Media.GLOW_BACKDROP)
	glow:SetAlpha(0)
	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.2)
	fade:SetSmoothing("IN_OUT")
	glow.Pulse, glow.Fade = pulse, fade
	glow.Start, glow.Stop = StartGlow, StopGlow
	return glow
end

-- A thin colored outline around a region, in its own frame so the whole
-- thing can be shown with SetAlphaFromBoolean when the condition is secret.
function Box.Outline(parent, anchor, thickness, layer)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetPoint("TOPLEFT", anchor or parent, "TOPLEFT", 0, 0)
	holder:SetPoint("BOTTOMRIGHT", anchor or parent, "BOTTOMRIGHT", 0, 0)
	holder:SetFrameLevel(parent:GetFrameLevel() + (layer or 5))
	holder.edges = {}
	local sides = {
		{ "TOPLEFT", "TOPRIGHT", false },
		{ "BOTTOMLEFT", "BOTTOMRIGHT", false },
		{ "TOPLEFT", "BOTTOMLEFT", true },
		{ "TOPRIGHT", "BOTTOMRIGHT", true },
	}
	for i, side in ipairs(sides) do
		local edge = holder:CreateTexture(nil, "OVERLAY")
		edge:SetTexture(ns.Media.WHITE)
		edge:SetPoint(side[1])
		edge:SetPoint(side[2])
		if side[3] then
			edge:SetWidth(thickness)
		else
			edge:SetHeight(thickness)
		end
		holder.edges[i] = edge
	end
	function holder:SetColor(r, g, b, a)
		for _, edge in ipairs(self.edges) do
			edge:SetVertexColor(r, g, b, a or 1)
		end
	end
	return holder
end
