-- Coalesces updates. Events only mark things dirty and queue the frame; the
-- queue is flushed once per rendered frame by an OnUpdate that turns itself
-- off when there's nothing to do, so an idle UI costs nothing.
local _, ns = ...

local Scheduler = ns:NewModule("Scheduler")

local debugprofilestop = debugprofilestop
local queue, count = {}, 0
local driver = CreateFrame("Frame")
driver:Hide()

local stats = { flushes = 0, slowest = 0, overOne = 0, overFive = 0 }
Scheduler.stats = stats

local Call = ns.Call

local function Flush(self)
	self:Hide()
	local started = debugprofilestop()
	local index = 1
	-- Frames queued while flushing are handled in this same pass.
	while index <= count do
		local target = queue[index]
		queue[index] = nil
		target.queued = false
		Call(target.Flush, target)
		index = index + 1
	end
	count = 0
	local elapsed = debugprofilestop() - started
	stats.flushes = stats.flushes + 1
	if elapsed > stats.slowest then
		stats.slowest = elapsed
	end
	if elapsed > 1 then
		stats.overOne = stats.overOne + 1
		if elapsed > 5 then
			stats.overFive = stats.overFive + 1
		end
	end
end
driver:SetScript("OnUpdate", Flush)

-- Anything with a Flush method and a `queued` field can be queued.
function Scheduler:Queue(target)
	if target.queued then
		return
	end
	target.queued = true
	count = count + 1
	queue[count] = target
	driver:Show()
end

-- Like Queue, but at most once per `interval` seconds. The first call runs
-- on the next frame; calls during the interval fold into one more run when
-- it ends, so the last change always lands. Used for work that follows
-- settings, so dragging a slider doesn't rebuild frames sixty times a second.
function Scheduler:QueueThrottled(target, interval)
	if target.throttled then
		target.throttledAgain = true
		return
	end
	target.throttled = true
	self:Queue(target)
	C_Timer.After(interval, function()
		target.throttled = false
		if target.throttledAgain then
			target.throttledAgain = false
			Scheduler:QueueThrottled(target, interval)
		end
	end)
end

function Scheduler:IsIdle()
	return not driver:IsShown()
end
