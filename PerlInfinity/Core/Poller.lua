-- The one periodic job in Perl Infinity. Units like "targettarget" have no events of
-- their own, so frames showing them ask to be polled. A single shared ticker
-- runs only while at least one such frame is visible; each tick just marks
-- the frames dirty, and the Scheduler does the real work once per frame.
local _, ns = ...

local Poller = ns:NewModule("Poller")

local frames = {}
local count = 0
local ticker

local function Tick()
	for frame in pairs(frames) do
		frame:Poll()
	end
end

local function TickSafely()
	ns.Call(Tick)
end

function Poller:Add(frame)
	if frames[frame] then
		return
	end
	frames[frame] = true
	count = count + 1
	if not ticker then
		ticker = C_Timer.NewTicker(ns.db and ns.db.general.pollInterval or 0.2, TickSafely)
	end
end

function Poller:Remove(frame)
	if not frames[frame] then
		return
	end
	frames[frame] = nil
	count = count - 1
	if count == 0 and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

function Poller:IsRunning()
	return ticker ~= nil
end
