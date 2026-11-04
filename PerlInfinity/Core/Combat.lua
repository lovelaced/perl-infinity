-- Changes to secure frames (size, position, attributes) are blocked during
-- combat. Combat:Run does the change now when it can, or remembers it and
-- runs it when combat ends. A later change with the same key replaces an
-- earlier one, so ten slider ticks in combat become one change afterwards.
--
-- Aura buttons have a second rule: they can't be restyled while auras are
-- secret, which can be true outside combat too (PvP). RunAuraSafe waits for
-- both conditions.
local _, ns = ...

local Combat = ns:NewModule("Combat")

local InCombatLockdown = InCombatLockdown
local queues = {
	protected = { order = {}, jobs = {} },
	aura = { order = {}, jobs = {} },
}

local function Enqueue(queue, key, fn, ...)
	if not queue.jobs[key] then
		queue.order[#queue.order + 1] = key
	end
	queue.jobs[key] = { fn = fn, n = select("#", ...), ... }
end

local function Drain(queue)
	local order, jobs = queue.order, queue.jobs
	queue.order, queue.jobs = {}, {}
	for i = 1, #order do
		local job = jobs[order[i]]
		ns.Call(job.fn, unpack(job, 1, job.n))
	end
end

local function AurasSecret()
	return C_Secrets.ShouldAurasBeSecret()
end

-- A stable key for "this job on this frame", so different jobs on the same
-- frame don't replace each other.
local keys = setmetatable({}, { __mode = "k" })
function Combat:Key(owner, name)
	local byName = keys[owner]
	if not byName then
		byName = {}
		keys[owner] = byName
	end
	local key = byName[name]
	if not key then
		key = {}
		byName[name] = key
	end
	return key
end

function Combat:Run(key, fn, ...)
	if InCombatLockdown() then
		Enqueue(queues.protected, key, fn, ...)
		return false
	end
	ns.Call(fn, ...)
	return true
end

function Combat:RunAuraSafe(key, fn, ...)
	if InCombatLockdown() or AurasSecret() then
		Enqueue(queues.aura, key, fn, ...)
		return false
	end
	ns.Call(fn, ...)
	return true
end

function Combat:HasPending()
	return #queues.protected.order > 0
end

function Combat:HasAuraPending()
	return #queues.aura.order > 0
end

function Combat:Init()
	ns.Events:On("PLAYER_REGEN_ENABLED", self, function()
		Drain(queues.protected)
		if not AurasSecret() then
			Drain(queues.aura)
		end
	end)
	ns.Events:On("ADDON_RESTRICTION_STATE_CHANGED", self, function()
		if not InCombatLockdown() and not AurasSecret() and #queues.aura.order > 0 then
			-- Restriction state is read as false during this event's dispatch,
			-- so check again on the next frame.
			C_Timer.After(0, function()
				if not InCombatLockdown() and not AurasSecret() then
					Drain(queues.aura)
				end
			end)
		end
	end)
end
