-- Where frame kinds are defined and created.
--
-- A frame kind (player, target, party...) is a spec table:
--   unit           unit token for single frames
--   layout         Layout function name: PortraitLeft, PortraitRight, Small, Raid
--   conf(frame)    returns the settings section for this frame
--   layoutOptions(frame, conf)  numbers for Layout
--   elements       element names, in update order
--   refreshEvents  events that mean "everything changed" (new target...)
--   group          true for party and raid buttons
--   hostile        true if the unit can be an enemy (target, focus and their
--                  targets); only these get "your debuffs" and "buffs you can
--                  remove" aura groups
--   movable        key for Edit Mode (single frames)
--   enabled()      is this frame turned on?
--   sample         sample data for the options window preview
local _, ns = ...

local Frames = ns:NewModule("Frames")

local Build, Combat = ns.Build, ns.Combat

local specs = {}
local order = {}
local instances = {}

Frames.specs = specs
Frames.instances = instances

function Frames:Define(kind, spec)
	spec.kind = kind
	specs[kind] = spec
	order[#order + 1] = kind
	return spec
end

function Frames:Get(kind)
	return instances[kind]
end

-- Creates a single secure unit frame (player, target...) inside its Edit Mode
-- mover. Group frames are made by their headers instead (see BuildChild).
function Frames:CreateSingle(kind)
	local spec = specs[kind]
	local mover = ns.Movers:Get(kind)
	local name = "PerlInfinity_" .. kind:gsub("^%l", string.upper)
	local button = CreateFrame("Button", name, mover, "SecureUnitButtonTemplate")
	button:SetPoint("TOPLEFT", mover, "TOPLEFT")
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("unit", spec.unit)
	button:SetAttribute("*type1", "target")
	button:SetAttribute("*type2", "togglemenu")
	ClickCastFrames = ClickCastFrames or {}
	ClickCastFrames[button] = true

	Build.Attach(button, kind, spec, false)
	if spec.Decorate then
		spec.Decorate(button)
	end
	button:SetScript("OnEvent", button.OnEvent)
	button:SetScript("OnShow", button.OnShow)
	button:SetScript("OnHide", button.OnHide)
	button:SetScript("OnEnter", button.OnEnter)
	button:SetScript("OnLeave", button.OnLeave)
	button:SetUnit(spec.unit)

	if spec.unit ~= "player" then
		RegisterUnitWatch(button)
	end
	instances[kind] = button
	button:Configure()
	ns.Movers:Fit(kind, button)
	return button
end

-- Called when a group header creates a button (see Unit/Header.lua).
function Frames:BuildChild(button, kind, spec)
	Build.Attach(button, kind, spec, false)
	if spec.Decorate then
		spec.Decorate(button)
	end
	ClickCastFrames = ClickCastFrames or {}
	ClickCastFrames[button] = true
	button:Configure()
end

-- Adds a secure button that follows its parent's unit with a suffix: a party
-- member's target or pet, a tank's target. Must run out of combat.
function Frames:AddSubFrame(parent, kind, suffix, unitFor)
	local sub = CreateFrame("Button", nil, parent, "SecureUnitButtonTemplate")
	sub:RegisterForClicks("AnyUp")
	sub:SetAttribute("useparent-unit", true)
	sub:SetAttribute("unitsuffix", suffix)
	sub:SetAttribute("*type1", "target")
	sub:SetAttribute("*type2", "togglemenu")
	ClickCastFrames = ClickCastFrames or {}
	ClickCastFrames[sub] = true

	Build.Attach(sub, kind, specs[kind], false)
	sub:SetScript("OnEvent", sub.OnEvent)
	sub:SetScript("OnShow", sub.OnShow)
	sub:SetScript("OnHide", sub.OnHide)
	sub:SetScript("OnEnter", sub.OnEnter)
	sub:SetScript("OnLeave", sub.OnLeave)
	sub.UnitFor = unitFor
	parent.subFrames = parent.subFrames or {}
	table.insert(parent.subFrames, sub)
	if parent.unit then
		sub:SetUnit(unitFor(parent.unit))
	end
	sub:Configure()
	RegisterUnitWatch(sub)
	return sub
end

-- Builds a preview frame (not secure) for the options window.
function Frames:CreatePreview(kind, parent)
	local spec = specs[kind]
	local frame = CreateFrame("Frame", nil, parent)
	Build.Attach(frame, kind, spec, true)
	if spec.Decorate then
		spec.Decorate(frame)
	end
	frame:EnableMouse(true)
	frame:SetScript("OnEnter", frame.OnEnter)
	frame:SetScript("OnLeave", frame.OnLeave)
	frame.sample = spec.sample and spec.sample() or nil
	frame:Configure()
	return frame
end

-- Turns a frame kind on or off. Turning one off hides it right away; the
-- game's own frame comes back after a reload.
function Frames:SetEnabled(kind, enabled)
	local spec = specs[kind]
	if spec.SetEnabled then
		return spec.SetEnabled(enabled)
	end
	if not spec.unit then
		return
	end
	local frame = instances[kind]
	if enabled and not frame then
		Combat:Run(Combat:Key(self, kind), self.CreateSingle, self, kind)
	elseif frame then
		Combat:Run(Combat:Key(self, kind), function()
			if enabled then
				if spec.unit ~= "player" then
					RegisterUnitWatch(frame)
				end
				frame:Show()
			else
				UnregisterUnitWatch(frame)
				frame:Hide()
			end
		end)
	end
	ns.Movers:SetEnabled(kind, enabled)
end

-- Reconfigures every frame of a kind (or all kinds) after a settings change.
function Frames:Reconfigure(kind)
	for k, spec in pairs(specs) do
		if not kind or k == kind then
			if spec.Reconfigure then
				spec.Reconfigure()
			elseif instances[k] then
				instances[k]:Configure()
				ns.Movers:Fit(k, instances[k])
			end
		end
	end
end

-- Settings sections each frame kind listens to.
-- Frames follow settings at most this often (seconds) while they change.
local SETTINGS_INTERVAL = 0.1

-- Turns frames on or off whose switch changed since we last looked. This
-- covers the options window, key bindings and profile switches alike.
local switches = {}
local function FollowSwitches()
	for _, kind in ipairs(order) do
		local spec = specs[kind]
		if spec.enabled then
			local enabled = spec.enabled() and true or false
			if switches[kind] ~= enabled then
				switches[kind] = enabled
				ns.Call(Frames.SetEnabled, Frames, kind, enabled)
			end
		end
	end
end

local function Watch()
	for _, kind in ipairs(order) do
		if specs[kind].enabled then
			switches[kind] = specs[kind].enabled() and true or false
		end
	end
	local pending = {}
	local flusher = { queued = false }
	function flusher:Flush()
		FollowSwitches()
		for kind in pairs(pending) do
			Frames:Reconfigure(kind ~= true and kind or nil)
		end
		wipe(pending)
	end
	ns.Config:Subscribe("", Frames, function(_, path)
		local section = path:match("^[^%.]+") or ""
		local kinds = Frames.sectionKinds[section]
		if kinds then
			for _, kind in ipairs(kinds) do
				pending[kind] = true
			end
		else
			pending[true] = true
		end
		ns.Scheduler:QueueThrottled(flusher, SETTINGS_INTERVAL)
	end)
end

-- Which frame kinds care about which settings section. Sections not listed
-- (look, general, highlight, range...) affect every frame.
Frames.sectionKinds = {
	player = { "player" },
	pet = { "pet" },
	target = { "target" },
	focus = { "focus" },
	small = { "targettarget", "targettargettarget", "focustarget", "pettarget" },
	party = { "party" },
	raid = { "raid", "raidpets" },
	tanks = { "tanks" },
	healers = { "healers" },
	tools = {},
}

-- Secure frames can't be set up in combat, so after a reload mid-fight they
-- appear as soon as combat ends.
function Frames:Login()
	Combat:Run(Combat:Key(self, "login"), function()
		for _, kind in ipairs(order) do
			local spec = specs[kind]
			-- Kinds without a switch of their own (party targets, tank
			-- columns) are built by their parent frames.
			if spec.Create then
				ns.Call(spec.Create)
			elseif spec.enabled and spec.unit and spec.enabled() then
				ns.Call(self.CreateSingle, self, kind)
			end
		end
		Watch()
		self.ready = true
	end)
end
