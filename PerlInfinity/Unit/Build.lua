-- Builds the visible parts of a unit frame: the X-Perl boxes, the bars, and
-- the text, on top of a root frame that's either a secure unit button (the
-- real thing) or a plain frame (options window preview). Elements add their
-- own widgets to these parts.
local _, ns = ...

local Build = {}
ns.Build = Build

local Box, Bars, Layout, Combat = ns.Box, ns.Bars, ns.Layout, ns.Combat
local UnitFrame = ns.UnitFrameMixin

local HIGHLIGHT_R, HIGHLIGHT_G, HIGHLIGHT_B = 0.86, 0.82, 0.41

local function Place(region, parent, rect)
	region:ClearAllPoints()
	region:SetPoint("TOPLEFT", parent, "TOPLEFT", rect.x, rect.y)
	region:SetSize(rect.w, rect.h)
end

local function MakeText(parent, template, justify)
	local text = parent:CreateFontString(nil, "OVERLAY", template)
	text:SetWordWrap(false)
	if justify then
		text:SetJustifyH(justify)
	end
	return text
end

-- Attaches the frame structure to `root`. `spec` comes from Frames/Registry.
function Build.Attach(root, kind, spec, preview)
	Mixin(root, UnitFrame)
	root:InitUnitFrame(kind, spec, preview)

	local content = CreateFrame("Frame", nil, root)
	content:SetAllPoints()
	root.Content = content

	local thin = spec.layout == "Raid"
	root.NameBox = Box.Create(content, thin)
	root.StatsBox = Box.Create(content, thin)
	-- The level and portrait boxes sit in front of the elite dragon. They're
	-- raised now, before elements add the 3D portrait, so it lands above its box.
	if spec.layout ~= "Raid" then
		root.LevelBox = Box.Create(content)
		Box.Raise(root.LevelBox, content, Box.LEVEL.FRONT)
		root.LevelText = MakeText(root.LevelBox, "GameFontNormalSmall", "CENTER")
		root.LevelText:SetPoint("CENTER", 0, 1)
	end
	if spec.layout == "PortraitLeft" or spec.layout == "PortraitRight" then
		root.PortraitBox = Box.Create(content)
		Box.Raise(root.PortraitBox, content, Box.LEVEL.FRONT)
	end

	-- Raid markers, leader crowns, PvP badges and the other small icons live
	-- here, in front of every box. Content's own textures draw behind its
	-- boxes, which is where these used to be.
	local overlay = CreateFrame("Frame", nil, content)
	overlay:SetAllPoints()
	Box.Raise(overlay, content, Box.LEVEL.OVERLAY)
	root.Overlay = overlay

	root.Health = Bars.Create(root.StatsBox, true)
	root.Power = Bars.Create(root.StatsBox, true)
	root.HealthPercent = MakeText(root.StatsBox, "GameFontNormalSmall", "CENTER")
	root.PowerPercent = MakeText(root.StatsBox, "GameFontNormalSmall", "CENTER")

	root.NameText = MakeText(root.NameBox, thin and "GameFontNormalSmall" or "GameFontNormal", "LEFT")
	root.NameText:SetPoint("LEFT", thin and 4 or 7, 0)
	root.NameText:SetPoint("RIGHT", thin and -4 or -7, 0)

	-- On target and focus the elite dragon reaches over the right end of the
	-- name and the percent column, so their text is drawn in front of it.
	if spec.eliteMarker then
		root.NameText:SetParent(Box.TextLayer(root.NameBox, content))
		local statsText = Box.TextLayer(root.StatsBox, content)
		root.HealthPercent:SetParent(statsText)
		root.PowerPercent:SetParent(statsText)
	end

	-- Soft gold glow while the mouse is over the frame.
	local highlight = content:CreateTexture(nil, "OVERLAY")
	highlight:SetTexture(ns.Media.WHITE)
	highlight:SetBlendMode("ADD")
	highlight:SetVertexColor(HIGHLIGHT_R, HIGHLIGHT_G, HIGHLIGHT_B, 0.15)
	highlight:SetPoint("TOPLEFT", root.NameBox, "TOPLEFT", 3, -3)
	highlight:SetPoint("BOTTOMRIGHT", root.StatsBox, "BOTTOMRIGHT", -3, 3)
	highlight:Hide()
	root.Highlight = highlight

	root.ApplyLayout = Build.ApplyLayout
	return root
end

-- Positions everything from the layout rectangles. Our own widgets move
-- right away; the secure root's size waits for the end of combat.
function Build.ApplyLayout(self, conf)
	local spec = self.spec
	local layoutName = spec.layoutName and spec.layoutName(conf) or spec.layout
	local rects = Layout[layoutName](spec.layoutOptions(self, conf))
	self.rects = rects
	local content = self.Content

	Place(self.NameBox, content, rects.name)
	Place(self.StatsBox, content, rects.statsBox)
	if self.LevelBox then
		if rects.level then
			Place(self.LevelBox, content, rects.level)
			self.LevelBox:Show()
		else
			self.LevelBox:Hide()
		end
	end
	if self.PortraitBox then
		if rects.portrait then
			Place(self.PortraitBox, content, rects.portrait)
			self.PortraitBox:Show()
		else
			self.PortraitBox:Hide()
		end
	end

	local stats = rects.stats
	Place(self.Health, self.StatsBox, stats.health)
	Place(self.Power, self.StatsBox, stats.power)
	self.Power:SetShown(stats.power.h > 0)

	self.HealthPercent:ClearAllPoints()
	self.PowerPercent:ClearAllPoints()
	if spec.layout == "Raid" then
		self.HealthPercent:SetPoint("CENTER", self.Health)
		self.PowerPercent:Hide()
	else
		self.HealthPercent:SetPoint("LEFT", self.Health, "RIGHT", 0, 0)
		self.HealthPercent:SetWidth(stats.percent.w)
		self.PowerPercent:SetPoint("LEFT", self.Power, "RIGHT", 0, 0)
		self.PowerPercent:SetWidth(stats.percent.w)
	end

	-- The whole frame fades by the frame opacity; text fades further by
	-- its own. Range fading works on the boxes inside, so they multiply.
	self:SetAlpha(ns.db.look.frameAlpha)
	local textAlpha = ns.db.look.textAlpha
	self.NameText:SetAlpha(textAlpha)
	self.NameText:SetJustifyH(ns.db.look.centerNames and "CENTER" or "LEFT")
	self.Health.Text:SetAlpha(textAlpha)
	self.Power.Text:SetAlpha(textAlpha)

	local width, height = rects.width, rects.height
	if self.preview then
		self:SetSize(width, height)
	else
		Combat:Run(Combat:Key(self, "size"), self.SetSize, self, width, height)
	end
	if self.OnLayout then
		self:OnLayout(rects)
	end
end

-- Extra thin bars below the power bar (XP, reputation, druid mana) share
-- these slots; elements claim one with Build.ExtraBar.
function Build.ExtraBar(frame, name, index)
	-- Bars are kept by name ("xp", "rep", "druidMana"), not by slot, so one
	-- turned off is hidden, and the others move up without taking on another
	-- bar's leftovers (the rested overlay, druid mana's fade).
	frame.ExtraBars = frame.ExtraBars or {}
	local bar = frame.ExtraBars[name]
	local rect = index and frame.rects and frame.rects.stats.extras[index]
	if not rect then
		if bar then
			bar:Hide()
		end
		return nil
	end
	if not bar then
		bar = Bars.Create(frame.StatsBox, false)
		bar.Text:SetFontObject("GameFontHighlightSmall")
		frame.ExtraBars[name] = bar
	end
	Place(bar, frame.StatsBox, rect)
	bar:Show()
	return bar
end
