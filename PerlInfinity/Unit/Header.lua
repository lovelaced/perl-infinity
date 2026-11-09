-- Secure group headers for party, raid and the raid tool windows. The game's
-- header decides which unit each child button shows and lays the children
-- out; we give it our button template and attributes.
--
-- Children are created by the header (sometimes in combat). Their visuals are
-- ours and not secure, so building them in combat is fine; only aura
-- containers have to wait, and the Auras element handles that itself.
local _, ns = ...

local Header = {}
ns.Header = Header

local Combat = ns.Combat

-- Runs inside the game's secure environment for every new child, so it can
-- size buttons even when they're created in combat.
local INITIAL_CONFIG = [[
	local header = self:GetParent()
	self:SetWidth(header:GetAttribute("child-width") or 80)
	self:SetHeight(header:GetAttribute("child-height") or 40)
]]

-- kind: frame spec key ("party", "raid"); spec: from Frames/Registry.
function Header.Create(name, parent, kind, spec, pets)
	local template = pets and "SecureGroupPetHeaderTemplate" or "SecureGroupHeaderTemplate"
	local header = CreateFrame("Frame", name, parent, template)
	header.perlInfinityKind = kind
	header.perlInfinitySpec = spec
	header.children = {}
	header:SetAttribute("template", "PerlInfinityUnitButtonTemplate")
	header:SetAttribute("initialConfigFunction", INITIAL_CONFIG)
	return header
end

-- Every attribute change makes the game's header lay out all its buttons
-- again. So attributes that already have their value are skipped, and the
-- rest are set with "_ignore" on (Blizzard's own batching switch) except the
-- last, which triggers a single layout for the lot.
local function SetAttributes(header, attributes)
	local changed = {}
	for key, value in pairs(attributes) do
		if header:GetAttribute(key) ~= value then
			changed[#changed + 1] = key
		end
	end
	if #changed == 0 then
		return
	end
	local last = table.remove(changed)
	local ignore = header:GetAttribute("_ignore")
	header:SetAttribute("_ignore", "attributeChanges")
	for _, key in ipairs(changed) do
		header:SetAttribute(key, attributes[key])
	end
	-- The game's header only adds anchors to the buttons it shows and never
	-- clears the old ones, so a new direction or sort would leave each button
	-- pinned two ways. Clearing them first lets the layout below start clean;
	-- buttons of a hidden header are anchored again when it shows.
	for _, child in ipairs(header.children) do
		child:ClearAllPoints()
	end
	header:SetAttribute("_ignore", ignore)
	header:SetAttribute(last, attributes[last])
end

-- Applies a table of header attributes, out of combat.
function Header.Apply(header, attributes)
	Combat:Run(Combat:Key(header, "attributes"), SetAttributes, header, attributes)
end

-- Sizes every child (and children made later) to the layout's size.
function Header.SetChildSize(header, width, height)
	Combat:Run(Combat:Key(header, "childSize"), function()
		if header:GetAttribute("child-width") == width and header:GetAttribute("child-height") == height then
			return
		end
		for _, child in ipairs(header.children) do
			child:SetSize(width, height)
		end
		SetAttributes(header, { ["child-width"] = width, ["child-height"] = height })
	end)
end

-- Makes the header build `count` buttons now, out of combat, so a raid
-- forming mid-fight doesn't have to create forty frames at once. It briefly
-- shows the header with a negative starting index, which makes it create
-- buttons for units that don't exist yet.
local function MakeButtons(header, count)
	local wasShown = header:IsShown()
	local solo, player = header:GetAttribute("showSolo"), header:GetAttribute("showPlayer")
	header:SetAttribute("showSolo", true)
	header:SetAttribute("showPlayer", true)
	header:SetAttribute("startingIndex", -(count - 1))
	header:Show()
	header:SetAttribute("startingIndex", 1)
	header:SetAttribute("showSolo", solo)
	header:SetAttribute("showPlayer", player)
	if not wasShown then
		header:Hide()
	end
end

function Header.Precreate(header, count)
	Combat:Run(Combat:Key(header, "precreate"), function()
		-- The buttons flash into view while they're made; they count as
		-- hidden so they don't set themselves up for nothing. The flag is
		-- cleared even if something goes wrong, or no frame would ever set
		-- itself up again.
		Header.precreating = true
		ns.Call(MakeButtons, header, count)
		Header.precreating = false
	end)
end

-- Called from the button template's OnLoad (see Templates.xml).
function Header.OnChildLoad(button)
	local header = button:GetParent()
	local spec = header.perlInfinitySpec
	if not spec then
		return
	end
	header.children[#header.children + 1] = button
	button.header = header
	ns.Call(ns.Frames.BuildChild, ns.Frames, button, header.perlInfinityKind, spec)
end

function Header.OnChildAttributeChanged(button, name, value)
	if name == "unit" and button.SetUnit then
		button:SetUnit(value)
	end
end
