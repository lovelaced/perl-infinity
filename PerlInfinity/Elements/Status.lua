-- The AFK tag next to a name, and the warning glow when someone is charmed or
-- mind controlled. Both can be secret inside instances, so they're shown with
-- alpha from a boolean rather than by branching.
local _, ns = ...

local Secret, Media = ns.Secret, ns.Media
local L = ns.L

local UnitIsAFK, UnitIsCharmed = UnitIsAFK, UnitIsCharmed

local Status = ns.Element("Status", {
	unitEvents = { "PLAYER_FLAGS_CHANGED", "UNIT_FLAGS" },
})

function Status.Create(frame)
	local afk = frame.NameBox:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	afk:SetPoint("RIGHT", frame.NameBox, "RIGHT", -6, 0)
	afk:SetText(L.STATUS_AFK)
	afk:SetAlpha(0)
	frame.AfkText = afk

	local charm = frame.Content:CreateTexture(nil, "OVERLAY")
	charm:SetTexture(Media.WHITE)
	charm:SetBlendMode("ADD")
	charm:SetVertexColor(1, 0, 0.6, 0.35)
	charm:SetPoint("TOPLEFT", frame.NameBox, "TOPLEFT", 3, -3)
	charm:SetPoint("BOTTOMRIGHT", frame.NameBox, "BOTTOMRIGHT", -3, 3)
	charm:SetAlpha(0)
	frame.CharmGlow = charm
end

function Status.Configure(frame)
	frame.showAfk = ns.db.general.afk
	frame.AfkText:SetAlpha(0)
end

function Status.Disable(frame)
	frame.AfkText:SetAlpha(0)
	frame.CharmGlow:SetAlpha(0)
end

function Status.Update(frame, unit)
	if frame.showAfk then
		Secret.ShowIf(frame.AfkText, UnitIsAFK(unit))
	end
	if frame.kind ~= "player" then
		Secret.ShowIf(frame.CharmGlow, UnitIsCharmed(unit))
	end
end

function Status.Preview(frame, sample)
	frame.AfkText:SetAlpha((sample.afk and frame.showAfk) and 1 or 0)
	frame.CharmGlow:SetAlpha(0)
end
