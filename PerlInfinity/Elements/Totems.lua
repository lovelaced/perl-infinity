-- A shaman's active totems under the player frame, with a timer swirl on
-- each. Right-click a totem to dismiss it. (Blizzard's totem timers live
-- inside its player frame, which Perl Infinity replaces.)
--
-- Totem details are secret in combat, so the timer comes from the game's
-- duration object and the icon's visibility from alpha.
local _, ns = ...

local Combat, Secret = ns.Combat, ns.Secret

local GetTotemInfo, GetTotemDuration = GetTotemInfo, GetTotemDuration

local Totems = ns.Element("Totems", {
	events = { "PLAYER_TOTEM_UPDATE", "PLAYER_ENTERING_WORLD" },
})

local SLOTS = 4
local SIZE = 22

function Totems.Enabled(frame, conf)
	if frame.kind ~= "player" or not conf.totems then
		return false
	end
	local _, class = UnitClass("player")
	return class == "SHAMAN"
end

local function BuildButtons(frame)
	local row = CreateFrame("Frame", nil, frame.Content)
	row:SetSize(SLOTS * (SIZE + 2), SIZE)
	frame.TotemRow = row
	frame.TotemButtons = {}
	for slot = 1, SLOTS do
		local button = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
		button:SetSize(SIZE, SIZE)
		button:SetPoint("LEFT", (slot - 1) * (SIZE + 2), 0)
		button:RegisterForClicks("RightButtonUp")
		button:SetAttribute("type2", "destroytotem")
		button:SetAttribute("totem-slot", slot)

		local visual = CreateFrame("Frame", nil, button)
		visual:SetAllPoints()
		visual:SetAlpha(0)
		local icon = visual:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		local cooldown = CreateFrame("Cooldown", nil, visual, "CooldownFrameTemplate")
		cooldown:SetAllPoints()
		cooldown:SetReverse(true)
		cooldown:SetDrawEdge(false)
		visual.Icon, visual.Cooldown = icon, cooldown
		button.Visual = visual
		frame.TotemButtons[slot] = button
	end
end

-- Secure buttons can't be set up in combat; if needed, wait and then
-- reconfigure the frame so the row gets placed.
function Totems.Create(frame)
	if InCombatLockdown() then
		Combat:Run(Combat:Key(frame, "totems"), function()
			BuildButtons(frame)
			frame:Configure()
		end)
	else
		BuildButtons(frame)
	end
end

function Totems.Configure(frame)
	local row = frame.TotemRow
	if not row then
		return
	end
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", frame.StatsBox, "BOTTOMLEFT", 4, -2)
	row:Show()
end

function Totems.Disable(frame)
	if frame.TotemRow then
		frame.TotemRow:Hide()
	end
end

function Totems.Update(frame)
	if not frame.TotemButtons then
		return
	end
	for slot, button in ipairs(frame.TotemButtons) do
		local visual = button.Visual
		local haveTotem, _, _, _, icon = GetTotemInfo(slot)
		Secret.ShowIf(visual, haveTotem)
		visual.Icon:SetTexture(icon)
		local duration = GetTotemDuration(slot)
		if duration then
			visual.Cooldown:SetCooldownFromDurationObject(duration)
		end
	end
end
