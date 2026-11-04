-- Works out how to move raid members back into a saved layout. Pure: it
-- takes the current roster and the saved layout and returns the next move,
-- so it can be tested without the game.
--
-- roster: array of { index = raidIndex, name, class, group }
-- saved:  map of name -> { group, class }
-- Returns { kind = "move", index, group } or { kind = "swap", index, other }
-- or nil when everyone is where they belong (or nothing more can be done).
local _, ns = ...

local RosterPlan = {}
ns.RosterPlan = RosterPlan

local GROUP_SIZE = 5

-- Where each member should go: their saved group, or for people who weren't
-- in the saved layout, the group of a missing saved member of their class.
function RosterPlan.Targets(roster, saved)
	local targets = {}
	local present = {}
	for _, member in ipairs(roster) do
		present[member.name] = true
	end
	local openSlots = {} -- class -> list of groups freed by absent members
	for name, entry in pairs(saved) do
		if not present[name] then
			openSlots[entry.class] = openSlots[entry.class] or {}
			table.insert(openSlots[entry.class], entry.group)
		end
	end
	for _, member in ipairs(roster) do
		local entry = saved[member.name]
		if entry then
			targets[member.name] = entry.group
		else
			local slots = openSlots[member.class]
			if slots and #slots > 0 then
				targets[member.name] = table.remove(slots, 1)
			end
		end
	end
	return targets
end

function RosterPlan.Next(roster, saved)
	local targets = RosterPlan.Targets(roster, saved)
	local counts = {}
	for _, member in ipairs(roster) do
		counts[member.group] = (counts[member.group] or 0) + 1
	end
	for _, member in ipairs(roster) do
		local wanted = targets[member.name]
		if wanted and wanted ~= member.group then
			if (counts[wanted] or 0) < GROUP_SIZE then
				return { kind = "move", index = member.index, group = wanted }
			end
			-- The group is full: swap with someone there who doesn't belong.
			for _, other in ipairs(roster) do
				if other.group == wanted and targets[other.name] ~= wanted then
					return { kind = "swap", index = member.index, other = other.index }
				end
			end
		end
	end
	return nil
end
