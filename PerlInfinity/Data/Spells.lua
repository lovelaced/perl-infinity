-- Spell IDs Perl Infinity needs. Names are looked up when used, never at load, so a
-- spell missing from Forever's data can't break the file. The self-test checks
-- that each of these exists in the client.
local _, ns = ...

local Spells = {}
ns.Spells = Spells

-- Automatic range checking: one helpful and one harmful spell per class. The
-- first spell the player knows is used. Classes without a helpful spell fall
-- back to the game's 40 yard group check for friends.
Spells.range = {
	PRIEST = { friend = { 2050, 2061 }, enemy = { 585, 589 } }, -- Lesser Heal, Flash Heal; Smite, Shadow Word: Pain
	DRUID = { friend = { 5185, 774 }, enemy = { 5176, 8921 } }, -- Healing Touch, Rejuvenation; Wrath, Moonfire
	SHAMAN = { friend = { 331, 8004 }, enemy = { 403, 8042 } }, -- Healing Wave, Lesser Healing Wave; Lightning Bolt, Earth Shock
	PALADIN = { friend = { 635, 19750 }, enemy = { 20271, 853 } }, -- Holy Light, Flash of Light; Judgement, Hammer of Justice
	MAGE = { friend = { 1459 }, enemy = { 133, 116 } }, -- Arcane Intellect; Fireball, Frostbolt
	WARLOCK = { friend = { 5697 }, enemy = { 686, 172 } }, -- Unending Breath; Shadow Bolt, Corruption
	HUNTER = { enemy = { 3044, 75 } }, -- Arcane Shot, Auto Shot
	ROGUE = { enemy = { 1752, 2764 } }, -- Sinister Strike, Throw
	WARRIOR = { enemy = { 78, 100 } }, -- Heroic Strike, Charge
}

-- Your heals over time, every rank, for the blue glow and HoT bars.
Spells.hots = {
	-- Renew
	139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315,
	-- Rejuvenation
	774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299,
	-- Regrowth
	8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858,
}

-- Your absorb shields, every rank, for the purple glow.
Spells.shields = {
	-- Power Word: Shield
	17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901,
}

-- Group buffs checked by the buff check and the "who's missing this buff"
-- tooltip. Each family matches by name, so every rank counts, and the group
-- version counts as having the single one.
Spells.buffFamilies = {
	{ class = "PRIEST", spells = { 1243, 21562 } }, -- Power Word: Fortitude, Prayer of Fortitude
	{ class = "PRIEST", spells = { 14752, 27681 } }, -- Divine Spirit, Prayer of Spirit
	{ class = "PRIEST", spells = { 976, 27683 } }, -- Shadow Protection, Prayer of Shadow Protection
	{ class = "MAGE", spells = { 1459, 23028 } }, -- Arcane Intellect, Arcane Brilliance
	{ class = "DRUID", spells = { 1126, 21849 } }, -- Mark of the Wild, Gift of the Wild
}

Spells.innervate = 29166

-- Turns a list of IDs into a set the aura container accepts.
function Spells.Set(list)
	local set = {}
	for i = 1, #list do
		set[list[i]] = true
	end
	return set
end

-- The first spell in `list` the player knows, as a name for range checks.
function Spells.FirstKnown(list)
	if not list then
		return nil
	end
	for i = 1, #list do
		local id = list[i]
		if C_SpellBook.IsSpellKnown(id) then
			return C_Spell.GetSpellName(id)
		end
	end
	return nil
end

-- Every spell ID above, for the self-test's existence check.
function Spells.All()
	local all = {}
	for _, pair in pairs(Spells.range) do
		for _, list in pairs(pair) do
			for i = 1, #list do
				all[#all + 1] = list[i]
			end
		end
	end
	for _, list in ipairs({ Spells.hots, Spells.shields }) do
		for i = 1, #list do
			all[#all + 1] = list[i]
		end
	end
	for _, family in ipairs(Spells.buffFamilies) do
		for i = 1, #family.spells do
			all[#all + 1] = family.spells[i]
		end
	end
	all[#all + 1] = Spells.innervate
	return all
end
