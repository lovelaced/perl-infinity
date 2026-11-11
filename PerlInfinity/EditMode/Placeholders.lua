-- Sample frames shown where a real frame has nothing to show yet (no target,
-- no focus, not in a party), so you can see its size, place it in Edit Mode,
-- and watch it change while the options window is open. They're the same
-- non-secure previews the options window uses, faded and click-through.
-- Movers decides when they're wanted (see EditMode/Movers.lua).
local _, ns = ...

local Placeholders = {}
ns.Placeholders = Placeholders

local samples = {}

-- Frames that show several samples, one per party member.
local MANY = { party = 4, partytarget = 4, partypet = 4 }

local SINGLE = {
	pet = true, pettarget = true, target = true, targettarget = true,
	targettargettarget = true, focus = true, focustarget = true,
}

local function RealShowing(key)
	local real = ns.Frames:Get(key)
	if real and real:IsShown() then
		return true
	end
	local spec = ns.Frames.specs[key]
	return spec.ShowingMembers ~= nil and spec.ShowingMembers() and true or false
end

local function Hide(list)
	if list and list.shown then
		for _, preview in ipairs(list) do
			preview:Hide()
		end
		list.shown = false
	end
end

-- Shows or hides `key`'s samples. A real frame on screen always wins. They're
-- set up again when they first appear and when `settingsChanged`.
function Placeholders:Set(key, mover, show, settingsChanged)
	if not SINGLE[key] and not MANY[key] then
		return
	end
	local list = samples[key]
	if not show or RealShowing(key) then
		Hide(list)
		return
	end
	if not list then
		list = {}
		for i = 1, MANY[key] or 1 do
			local preview = ns.Frames:CreatePreview(key, mover)
			preview:SetAlpha(0.6)
			preview:EnableMouse(false)
			list[i] = preview
		end
		samples[key] = list
	end
	if list.shown and not settingsChanged then
		return
	end
	local spec = ns.Frames.specs[key]
	for i, preview in ipairs(list) do
		preview:Configure()
		preview:ClearAllPoints()
		if spec.PlaceSample then
			spec.PlaceSample(preview, i, mover)
		else
			preview:SetPoint("TOPLEFT", mover, "TOPLEFT")
		end
		preview:Show()
	end
	list.shown = true
end
