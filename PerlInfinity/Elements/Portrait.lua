-- The square portrait: a 3D model, a picture, or a class icon for players.
-- 3D models need to know who the unit is, which the game hides for some
-- creatures inside instances; those fall back to the picture.
local _, ns = ...

local Classes = ns.Classes

local UnitIsVisible, UnitIsPlayer, UnitClass, UnitIsConnected =
	UnitIsVisible, UnitIsPlayer, UnitClass, UnitIsConnected
local SetPortraitTexture = SetPortraitTexture
local ShouldIdentityBeSecret = C_Secrets.ShouldUnitIdentityBeSecret

local Portrait = ns.Element("Portrait", {
	unitEvents = { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION" },
})

local INSET = 4

function Portrait.Enabled(frame, conf)
	return frame.PortraitBox ~= nil and conf.portrait ~= false
end

function Portrait.Create(frame)
	local box = frame.PortraitBox
	local texture = box:CreateTexture(nil, "ARTWORK")
	texture:SetPoint("TOPLEFT", INSET, -INSET)
	texture:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	frame.PortraitTexture = texture

	local model = CreateFrame("PlayerModel", nil, box)
	model:SetPoint("TOPLEFT", INSET, -INSET)
	model:SetPoint("BOTTOMRIGHT", -INSET, INSET)
	model:Hide()
	frame.PortraitModel = model
end

function Portrait.Configure(frame)
	frame.PortraitBox:Show()
	frame.portraitStyle = ns.db.look.portraitStyle
end

function Portrait.Disable(frame)
	if frame.PortraitModel then
		frame.PortraitModel:Hide()
		frame.PortraitModel:ClearModel()
	end
end

local function ShowClassIcon(frame, classToken)
	local coords = Classes.IconCoords(classToken)
	if not coords then
		return false
	end
	local texture = frame.PortraitTexture
	texture:SetTexture(Classes.ICON_TEXTURE)
	texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	return true
end

function Portrait.Update(frame, unit)
	local texture, model = frame.PortraitTexture, frame.PortraitModel
	local style = frame.portraitStyle

	if style == "class" and UnitIsPlayer(unit) then
		local _, classToken = UnitClass(unit)
		if not ns.Secret.Is(classToken) and ShowClassIcon(frame, classToken) then
			model:Hide()
			texture:Show()
			return
		end
	end

	if style == "3d" and UnitIsVisible(unit) and UnitIsConnected(unit) and not ShouldIdentityBeSecret(unit) then
		texture:Hide()
		model:Show()
		model:SetUnit(unit)
		model:SetPortraitZoom(1)
		model:SetCamDistanceScale(1)
		return
	end

	model:Hide()
	texture:SetTexCoord(0, 1, 0, 1)
	SetPortraitTexture(texture, unit)
	texture:Show()
end

function Portrait.Preview(frame, sample)
	local texture, model = frame.PortraitTexture, frame.PortraitModel
	model:Hide()
	if frame.portraitStyle == "class" and sample.class and ShowClassIcon(frame, sample.class) then
		texture:Show()
		return
	end
	if sample.unit then
		if frame.portraitStyle == "3d" then
			texture:Hide()
			model:Show()
			model:SetUnit(sample.unit)
			model:SetPortraitZoom(1)
			return
		end
		texture:SetTexCoord(0, 1, 0, 1)
		SetPortraitTexture(texture, sample.unit)
	else
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		texture:SetTexture(sample.icon or 136235)
	end
	texture:Show()
end
