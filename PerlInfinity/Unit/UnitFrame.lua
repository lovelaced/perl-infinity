-- Behaviour shared by every unit frame, secure or preview.
--
-- A frame registers its elements' events only while it's shown. An event
-- marks the interested elements dirty and queues the frame; the Scheduler
-- then calls Flush once per rendered frame, which updates only the dirty
-- elements. Event payloads are ignored because they may be secret.
local _, ns = ...

local UnitFrame = {}
ns.UnitFrameMixin = UnitFrame

local Scheduler, Poller, Log, Events = ns.Scheduler, ns.Poller, ns.Log, ns.Events
local Call = ns.Call
local wipe, ipairs = wipe, ipairs

-- "targettarget", "party2target", "pettarget" and friends have no unit
-- events, so they're polled instead.
local function IsCompound(unit)
	return unit ~= "target" and unit:sub(-6) == "target"
end

function UnitFrame:InitUnitFrame(kind, spec, preview)
	self.kind = kind
	self.spec = spec
	self.preview = preview
	self.elements = {}
	self.dirty = {}
	self.eventMap = {}
	self.unitEvents = {}
	self.refreshEvents = {}
	self.created = {}
	self.queued = false
end

function UnitFrame:Conf()
	return self.spec.conf(self)
end

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

local function AddEvent(self, event, index, isUnitEvent, eventUnit)
	if not Events:IsValid(event) then
		Log:Note("unknown-event", event)
		return
	end
	local list = self.eventMap[event]
	if not list then
		list = {}
		self.eventMap[event] = list
	end
	list[#list + 1] = index
	if isUnitEvent then
		-- An element can listen for another unit's events, such as combo
		-- points on the target frame listening to the player's power. Each
		-- event can follow the frame's unit, one other unit, or both.
		local units = self.unitEvents[event]
		if not units then
			units = {}
			self.unitEvents[event] = units
		end
		if eventUnit then
			units.other = eventUnit
		else
			units.own = true
		end
	end
end

-- Works out which elements are on, builds or hides them, applies settings,
-- and rebuilds the event map. Safe in combat: it only touches our own
-- non-secure widgets.
--
-- A frame nobody can see (no focus yet, not in a party, raid frames while
-- solo) only works out its size, which Edit Mode and the group headers need.
-- Building and setting up its parts waits until it first shows, so hidden
-- frames cost nothing at login or when settings change.
function UnitFrame:Configure()
	local conf = self:Conf()
	if self.ApplyLayout then
		self:ApplyLayout(conf)
	end
	if self:Deferred() then
		self.stale = true
		return
	end
	self.stale = false

	local elements = self.elements
	wipe(elements)
	wipe(self.eventMap)
	wipe(self.unitEvents)
	wipe(self.dirty)

	for _, name in ipairs(self.spec.elements) do
		local element = ns.Elements[name]
		local enabled = element and (not element.Enabled or element.Enabled(self, conf))
		if enabled then
			if not self.created[name] then
				self.created[name] = true
				Log.current = self.kind .. "/" .. name
				element.Create(self)
			end
			if element.Configure then
				Log.current = self.kind .. "/" .. name
				element.Configure(self, conf)
			end
			local index = #elements + 1
			elements[index] = element
			self.dirty[index] = false
			local unitEvents, events = element.unitEvents, element.events
			if type(unitEvents) == "function" then
				unitEvents = unitEvents(self, conf)
			end
			if type(events) == "function" then
				events = events(self, conf)
			end
			for _, event in ipairs(unitEvents) do
				AddEvent(self, event, index, true, element.eventUnit)
			end
			for _, event in ipairs(events) do
				AddEvent(self, event, index, false)
			end
		elseif element and self.created[name] and element.Disable then
			element.Disable(self)
		end
	end
	Log.current = nil

	wipe(self.refreshEvents)
	for _, event in ipairs(self.spec.refreshEvents or {}) do
		if Events:IsValid(event) then
			self.refreshEvents[event] = true
		end
	end

	if not self.preview and self:IsShown() then
		self:RegisterElementEvents()
	end
	if self.preview then
		self:ShowPreview()
	else
		self:UpdateAll(true)
	end
end

-- True while the frame can't be seen, so setting it up can wait.
function UnitFrame:Deferred()
	return not self.preview and (ns.Header.precreating or not self:IsVisible())
end

function UnitFrame:RegisterElementEvents()
	self:UnregisterAllEvents()
	local unit = self.unit
	if not unit then
		return
	end
	local compound = IsCompound(unit)
	for event in pairs(self.eventMap) do
		local units = self.unitEvents[event]
		if units then
			local own = units.own and not compound and unit or nil
			if own and units.other then
				self:RegisterUnitEvent(event, own, units.other)
			elseif own or units.other then
				self:RegisterUnitEvent(event, own or units.other)
			end
		else
			self:RegisterEvent(event)
		end
	end
	for event in pairs(self.refreshEvents) do
		self:RegisterEvent(event)
	end
	if compound then
		-- The unit behind "party1target" changes when party1 changes target.
		local parent = unit:sub(1, -7)
		if not IsCompound(parent) then
			self:RegisterUnitEvent("UNIT_TARGET", parent)
		end
	end
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

-- Payloads are handed only to elements that ask for them (OnUnitEvent), and
-- those must treat them as possibly secret.
function UnitFrame:OnEvent(event, ...)
	if self.refreshEvents[event] or event == "UNIT_TARGET" then
		self:UpdateAll()
		return
	end
	local indices = self.eventMap[event]
	if indices then
		local dirty, elements = self.dirty, self.elements
		for i = 1, #indices do
			local index = indices[i]
			dirty[index] = true
			-- A few elements (cast bars) need to know which event happened.
			local hook = elements[index].OnUnitEvent
			if hook then
				hook(self, event, ...)
			end
		end
		Scheduler:Queue(self)
	end
end

function UnitFrame:UpdateAll(snap)
	local dirty = self.dirty
	for i = 1, #self.elements do
		dirty[i] = true
	end
	self.refreshAuras = true
	if snap then
		self.snap = true
	end
	Scheduler:Queue(self)
end

function UnitFrame:Flush()
	local unit = self.unit
	if not unit or self.preview then
		return
	end
	local elements, dirty = self.elements, self.dirty
	if self.refreshAuras then
		-- Aura containers follow the unit themselves, but need telling when
		-- the unit behind the token changes.
		self.refreshAuras = false
		if self.AuraContainers then
			Call(ns.AuraHost.Refresh, self, unit)
		end
	end
	for i = 1, #elements do
		if dirty[i] then
			dirty[i] = false
			local element = elements[i]
			Log.current = element.name
			Call(element.Update, self, unit)
		end
	end
	Log.current = nil
	if self.snap then
		self.snap = false
		if self.OnSnapped then
			self:OnSnapped()
		end
	end
end

-- Called by the Poller for units without events.
function UnitFrame:Poll()
	local elements, dirty = self.elements, self.dirty
	local full = self.pollAll
	-- Units like "targettarget" get no aura events either.
	self.refreshAuras = true
	for i = 1, #elements do
		if full or elements[i].poll then
			dirty[i] = true
		end
	end
	Scheduler:Queue(self)
end

function UnitFrame:SetUnit(unit)
	if unit == self.unit then
		return
	end
	self.unit = unit
	-- Party targets and pets ride along on their party member's frame.
	if self.subFrames then
		for _, sub in ipairs(self.subFrames) do
			sub:SetUnit(unit and sub.UnitFor(unit))
		end
	end
	self.pollAll = unit and IsCompound(unit) and IsCompound(unit:sub(1, -7))
	if not self.preview and self:IsShown() then
		self:OnShow()
	end
end

-- Elements that run their own light timers (range) start and stop them here.
local function NotifyShown(self, shown)
	local elements = self.elements
	for i = 1, #elements do
		local hook = elements[i].Shown
		if hook then
			Call(hook, self, shown)
		end
	end
end

function UnitFrame:OnShow()
	if self.preview or ns.Header.precreating then
		return
	end
	if self.stale then
		self:Configure()
	else
		self:RegisterElementEvents()
	end
	if self.unit and IsCompound(self.unit) then
		Poller:Add(self)
	end
	NotifyShown(self, true)
	self:UpdateAll(true)
	ns.Movers:FrameShown()
end

function UnitFrame:OnHide()
	if self.preview then
		return
	end
	self:UnregisterAllEvents()
	Poller:Remove(self)
	NotifyShown(self, false)
end

---------------------------------------------------------------------------
-- Previews (options window): elements show sample values instead.
---------------------------------------------------------------------------

function UnitFrame:ShowPreview()
	local sample = self.sample
	if not sample then
		return
	end
	for i = 1, #self.elements do
		local element = self.elements[i]
		if element.Preview then
			Log.current = "preview/" .. element.name
			Call(element.Preview, self, sample)
		end
	end
	Log.current = nil
end

function UnitFrame:SetSample(sample)
	self.sample = sample
	self:ShowPreview()
end

---------------------------------------------------------------------------
-- Mouse
---------------------------------------------------------------------------

local MODIFIERS = {
	shift = IsShiftKeyDown,
	alt = IsAltKeyDown,
	ctrl = IsControlKeyDown,
}

-- Applies a "when to show tooltips" setting: always, shift, alt, ctrl, never.
function ns.TooltipAllowed(mode, inCombatToo)
	if mode == "never" then
		return false
	end
	if not inCombatToo and InCombatLockdown() then
		return false
	end
	local check = MODIFIERS[mode]
	return not check or check()
end

function UnitFrame:OnEnter()
	if self.Highlight and ns.db.general.mouseoverHighlight then
		self.Highlight:Show()
	end
	if self.preview or not self.unit then
		return
	end
	local general = ns.db.general
	if ns.TooltipAllowed(general.unitTooltips, general.unitTooltipsInCombat) then
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetUnit(self.unit)
		GameTooltip:Show()
	end
	if self.OnHover then
		self:OnHover(true)
	end
end

function UnitFrame:OnLeave()
	if self.Highlight then
		self.Highlight:Hide()
	end
	if GameTooltip:IsOwned(self) then
		if ns.db.general.fadeTooltips then
			GameTooltip:FadeOut()
		else
			GameTooltip:Hide()
		end
	end
	if self.OnHover then
		self:OnHover(false)
	end
end
