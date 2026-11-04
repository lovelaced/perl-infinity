-- Sample frames shown in Edit Mode where a real frame has nothing to show yet
-- (no target, no focus, not in a party), so you can see its size and place
-- it. They're the same non-secure previews the options window uses.
local _, ns = ...

local Placeholders = {}
ns.Placeholders = Placeholders

local samples = {}

local SINGLE = {
	pet = true, pettarget = true, target = true, targettarget = true,
	targettargettarget = true, focus = true, focustarget = true,
}

function Placeholders:Set(key, mover, show)
	if not SINGLE[key] and key ~= "party" then
		return
	end
	local list = samples[key]
	if show then
		local spec = ns.Frames.specs[key]
		local real = ns.Frames:Get(key)
		if (real and real:IsShown()) or (spec.ShowingMembers and spec.ShowingMembers()) then
			return
		end
		if not list then
			list = {}
			local count = key == "party" and 4 or 1
			for i = 1, count do
				local preview = ns.Frames:CreatePreview(key, mover)
				preview:SetAlpha(0.6)
				preview:EnableMouse(false)
				list[i] = preview
			end
			samples[key] = list
		end
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
	elseif list then
		for _, preview in ipairs(list) do
			preview:Hide()
		end
	end
end
