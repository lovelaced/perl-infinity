-- Status bars in the X-Perl style: the chosen bar texture over a dim copy of
-- itself, with value text centered on the bar. Values may be secret; they go
-- straight into SetValue, which accepts them.
local _, ns = ...

local Bars = ns:NewModule("Bars")
local Media = ns.Media

local Immediate = Enum.StatusBarInterpolation.Immediate
local Smooth = Enum.StatusBarInterpolation.ExponentialEaseOut

local bars = setmetatable({}, { __mode = "k" })

function Bars.ApplyLook(bar)
	local look = ns.db.look
	local texture = Media.BarTexture(look.texture)
	bar:SetStatusBarTexture(texture)
	bar.Background:SetTexture(look.texturedBackground and texture or Media.BAR_BACKGROUND)
	bar.interpolation = (look.smoothBars and not bar.noSmoothing) and Smooth or Immediate
	if bar.inverts then
		bar:SetFillStyle(look.invertBars and Enum.StatusBarFillStyle.Reverse or Enum.StatusBarFillStyle.Standard)
	end
end

-- Creates a bar. `inverts` marks bars that follow the "inverted bars" setting.
function Bars.Create(parent, inverts)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)

	local background = bar:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	bar.Background = background

	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	text:SetWordWrap(false)
	bar.Text = text

	bar.inverts = inverts
	bars[bar] = true
	Bars.ApplyLook(bar)
	return bar
end

-- Colors the fill and its dim background. r, g, b may be secret.
function Bars.SetColor(bar, r, g, b)
	bar:SetStatusBarColor(r, g, b)
	bar.Background:SetVertexColor(r, g, b, 0.25)
end

-- Sets value and range in one go, honoring the smooth bars setting.
function Bars.Set(bar, value, maxValue)
	bar:SetMinMaxValues(0, maxValue)
	bar:SetValue(value, bar.interpolation)
end

-- Jumps straight to the current value, so a new target doesn't animate
-- from the previous one.
function Bars.Snap(bar)
	if bar.SetToTargetValue then
		bar:SetToTargetValue()
	end
end

function Bars:Init()
	ns.Config:Subscribe("look", self, function()
		for bar in pairs(bars) do
			Bars.ApplyLook(bar)
		end
	end)
end
