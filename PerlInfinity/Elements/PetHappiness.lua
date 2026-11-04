-- How a hunter's pet feels, on the pet frame's portrait. Happy pets do more
-- damage, so X-Perl can flash the icon when the pet is unhappy.
local _, ns = ...

local L = ns.L

local PetHappiness = ns.Element("PetHappiness", {
	unitEvents = { "UNIT_HAPPINESS" },
	events = { "UNIT_PET" },
})

local ATLAS = { "UI-PetMad", "UI-PetNeutral", "UI-PetHappiness" }
local TEXT = { PET_HAPPINESS1, PET_HAPPINESS2, PET_HAPPINESS3 }

function PetHappiness.Enabled(frame, conf)
	if frame.kind ~= "pet" or conf.happiness == "hidden" then
		return false
	end
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

function PetHappiness.Create(frame)
	local holder = CreateFrame("Frame", nil, frame.Content)
	holder:SetSize(24, 24)
	holder:SetPoint("BOTTOMLEFT", frame.PortraitBox or frame.StatsBox, "BOTTOMLEFT", -6, -6)
	holder:SetFrameLevel(frame.Content:GetFrameLevel() + 6)
	holder:EnableMouse(true)
	holder:SetScript("OnEnter", function(self)
		if self.happiness then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(TEXT[self.happiness] or "")
			if self.damage then
				GameTooltip:AddLine(L.PET_DAMAGE:format(self.damage), 1, 1, 1)
			end
			GameTooltip:Show()
		end
	end)
	holder:SetScript("OnLeave", GameTooltip_Hide)
	local icon = holder:CreateTexture(nil, "OVERLAY")
	icon:SetAllPoints()
	holder.Icon = icon

	local flash = holder:CreateAnimationGroup()
	flash:SetLooping("BOUNCE")
	local alpha = flash:CreateAnimation("Alpha")
	alpha:SetFromAlpha(1)
	alpha:SetToAlpha(0.2)
	alpha:SetDuration(0.6)
	holder.Flash = flash
	frame.Happiness = holder
end

function PetHappiness.Configure(frame, conf)
	frame.happinessMode = conf.happiness
	frame.happinessFlash = conf.happinessFlash
end

function PetHappiness.Disable(frame)
	frame.Happiness:Hide()
	frame.Happiness.Flash:Stop()
end

local function Show(frame, happiness, damage)
	local holder = frame.Happiness
	holder.happiness, holder.damage = happiness, damage
	if not happiness or not ATLAS[happiness] then
		holder:Hide()
		holder.Flash:Stop()
		return
	end
	local unhappy = happiness < 3
	if frame.happinessMode == "unhappy" and not unhappy then
		holder:Hide()
		holder.Flash:Stop()
		return
	end
	holder.Icon:SetAtlas(ATLAS[happiness])
	holder:Show()
	if unhappy and frame.happinessFlash then
		holder.Flash:Play()
	else
		holder.Flash:Stop()
		holder:SetAlpha(1)
	end
end

function PetHappiness.Update(frame)
	local happiness, damage = C_PetInfo.GetPetHappiness()
	Show(frame, happiness, damage)
end

function PetHappiness.Preview(frame, sample)
	Show(frame, sample.happiness, 100)
end
