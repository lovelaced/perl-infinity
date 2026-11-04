-- One shared event frame for everything that isn't a unit frame: roster
-- changes, combat state, Edit Mode, raid tools. Unit frames register their
-- own unit events (see Unit/UnitFrame.lua) so the game filters by unit for us.
--
--   Events:On(event, owner, fn)   fn(owner, event, ...)
--   Events:Off(event, owner)
local _, ns = ...

local Events = ns:NewModule("Events")

local frame = CreateFrame("Frame")
local listeners = {} -- event -> array of { owner, fn }
local valid = {}

-- The combat log is closed to addons on Forever; even registering for it is
-- a forbidden action, so these never reach the client.
local BANNED = {
	COMBAT_LOG_EVENT_UNFILTERED = true,
	COMBAT_LOG_EVENT = true,
}

function Events:IsValid(event)
	local known = valid[event]
	if known == nil then
		known = C_EventUtils.IsEventValid(event) and true or false
		valid[event] = known
	end
	return known
end

function Events:On(event, owner, fn)
	if BANNED[event] then
		ns.Log:Note("banned-event", event)
		return false
	end
	if not self:IsValid(event) then
		ns.Log:Note("unknown-event", event)
		return false
	end
	local list = listeners[event]
	if not list then
		list = {}
		listeners[event] = list
		frame:RegisterEvent(event)
	end
	for i = 1, #list do
		if list[i].owner == owner then
			list[i].fn = fn
			return true
		end
	end
	-- Copy on write, so a dispatch already in progress isn't disturbed.
	local copy = { unpack(list) }
	copy[#copy + 1] = { owner = owner, fn = fn }
	listeners[event] = copy
	return true
end

function Events:Off(event, owner)
	local list = listeners[event]
	if not list then
		return
	end
	local copy = {}
	for i = 1, #list do
		if list[i].owner ~= owner then
			copy[#copy + 1] = list[i]
		end
	end
	if #copy == 0 then
		listeners[event] = nil
		frame:UnregisterEvent(event)
	else
		listeners[event] = copy
	end
end

local Call = ns.Call
frame:SetScript("OnEvent", function(_, event, ...)
	local list = listeners[event]
	if not list then
		return
	end
	for i = 1, #list do
		local listener = list[i]
		Call(listener.fn, listener.owner, event, ...)
	end
end)
