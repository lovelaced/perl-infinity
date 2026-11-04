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
