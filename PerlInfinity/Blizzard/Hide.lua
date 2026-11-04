-- Hides Blizzard's own frames, only for the Perl Infinity frames you have turned
-- on. It uses the game's role sets to block a frame (oUF's approach on
-- Forever) and stops its events so it costs nothing. If that's ever refused,
-- the frame is tucked under a hidden parent instead. Protected frames can't
-- be touched in combat, so this waits for combat to end if needed.
--
-- Turning a Perl Infinity frame on hides Blizzard's right away. Turning it off
-- brings Blizzard's back only after a reload, and chat says so.
local _, ns = ...

local Hide = ns:NewModule("BlizzardHide")
local Combat = ns.Combat
local L = ns.L

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local function Block(frame, ...)
	if not frame or frame.perlInfinityBlocked then
		return
	end
	frame.perlInfinityBlocked = true
	frame:UnregisterAllEvents()
	for i = 1, select("#", ...) do
		local child = frame[select(i, ...)]
		if child and child.UnregisterAllEvents then
			child:UnregisterAllEvents()
		end
	end
	local blocked = false
	if frame.SetRolesets then
		blocked = pcall(frame.SetRolesets, frame, "alwaysBlocked")
		if blocked and frame.IsRolesetFiltered then
			blocked = frame:IsRolesetFiltered() and true or false
		end
	end
	if not blocked then
		ns.Log:Note("blizzard-hide-fallback", frame:GetName())
		frame:Hide()
		frame:SetParent(hiddenParent)
	end
end

local function HideCastBar(frame)
	if frame and not frame.perlInfinityBlocked then
		frame.perlInfinityBlocked = true
		frame:UnregisterAllEvents()
		frame:Hide()
	end
end

local function HideParty()
	Block(PartyFrame)
	if PartyFrame and PartyFrame.PartyMemberFramePool then
		for member in PartyFrame.PartyMemberFramePool:EnumerateActive() do
			Block(member, "healthbar", "manabar", "HealthBar", "ManaBar")
		end
	end
	for i = 1, 5 do
		Block(_G["CompactPartyFrameMember" .. i])
	end
	Block(CompactPartyFrame)
end

local function HideRaid()
	Block(CompactRaidFrameManager)
	Block(CompactRaidFrameContainer)
end

-- Each piece of Blizzard's UI Perl Infinity can hide, and when it should be hidden.
local PIECES = {
	{
		key = "player",
		wanted = function(db) return db.player.enabled end,
		-- Blizzard's pet frame and totem timers live inside its player frame.
		hide = function() Block(PlayerFrame, "healthbar", "manabar") end,
	},
	{
		key = "playerCast",
		wanted = function(db) return db.player.enabled and db.player.castBar and not db.player.keepBlizzardCastBar end,
		hide = function() HideCastBar(PlayerCastingBarFrame) end,
	},
	{
		key = "pet",
		wanted = function(db) return db.pet.enabled end,
		hide = function() Block(PetFrame, "healthbar", "manabar") end,
	},
	{
		key = "petCast",
		wanted = function(db) return db.pet.enabled and db.pet.castBar end,
		hide = function() HideCastBar(PetCastingBarFrame) end,
	},
	{
		key = "target",
		wanted = function(db) return db.target.enabled end,
		hide = function() Block(TargetFrame, "healthbar", "manabar", "spellbar") end,
	},
	{
		key = "targettarget",
		wanted = function(db) return db.target.enabled or db.small.targettarget.enabled end,
		hide = function() Block(TargetFrame and TargetFrame.totFrame) end,
	},
	{
		key = "focus",
		wanted = function(db) return db.focus.enabled end,
		hide = function()
			Block(FocusFrame, "healthbar", "manabar", "spellbar")
			Block(FocusFrame and FocusFrame.totFrame)
		end,
	},
	{ key = "party", wanted = function(db) return db.party.enabled end, hide = HideParty },
	{ key = "raid", wanted = function(db) return db.raid.enabled end, hide = HideRaid },
}

local hidden = {} -- pieces hidden this session; only a reload brings them back
local announced = {} -- pieces we've already told you need a reload

-- Hides what your settings say should be hidden. Hiding works any time out
-- of combat; showing a piece again needs a reload, so when a change asks for
-- that, chat says so once and names what will come back.
local function Apply()
	local db = ns.db
	local returning = {}
	for _, piece in ipairs(PIECES) do
		local key = piece.key
		if piece.wanted(db) then
			announced[key] = nil
			if not hidden[key] then
				hidden[key] = true
				ns.Call(piece.hide)
			end
		elseif hidden[key] and not announced[key] then
			announced[key] = true
			returning[#returning + 1] = L.GamePieces[key]
		end
	end
	if #returning > 0 then
		local list = returning[1]
		if #returning > 1 then
			list = table.concat(returning, ", ", 1, #returning - 1) .. L.LIST_AND .. returning[#returning]
		end
		ns.Print(L.MSG_RELOAD_TO_RETURN, list)
	end
end

-- True while Blizzard's version of a piece is hidden ("target", "player"...).
function Hide:IsHidden(key)
	return hidden[key] == true
end

-- Hiding Blizzard's player frame also silences the PvP flag sound.
local function OnPvPFlag()
	if UnitIsPVP("player") then
		PlaySound(SOUNDKIT.IG_PVP_UPDATE)
	end
end

function Hide:Login()
	Combat:Run(Combat:Key(self, "apply"), Apply)
	ns.Events:On("PLAYER_PVP_FLAG_CHANGED", self, function()
		if hidden.player then
			OnPvPFlag()
		end
	end)
	-- Party member frames come from a pool and can appear later.
	ns.Events:On("GROUP_ROSTER_UPDATE", self, function()
		if hidden.party then
			Combat:Run(Combat:Key(self, "party"), HideParty)
		end
	end)
	-- Follow settings changes, once per batch (a profile switch changes many).
	local flusher = { queued = false }
	flusher.Flush = function()
		Combat:Run(Combat:Key(Hide, "apply"), Apply)
	end
	ns.Config:Subscribe("", self, function()
		ns.Scheduler:Queue(flusher)
	end)
end
