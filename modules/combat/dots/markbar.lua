-- What marks (Death Mark) will deal, on an overlay (overlays.lua): a bar over
-- the whole overlay, filling in reverse from its right end (the health's). It
-- shows the health the hit will remove darkened, its own color and gloss
-- underneath.

local _, ns = ...

local DoTs = ns:GetFeature("combat", "dots")

local MarkBar = {}
DoTs.MarkBar = MarkBar

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local SHADE_ALPHA = 0.5
-- Draw sublevels range from -8 to 7.
local MAX_SUBLEVEL = 7

-- The mark bar of each overlay.
local bars = setmetatable({}, { __mode = "k" })

-- `mask`: the health bar's shape, if it has one.
function MarkBar:Create(overlay, mask)
    local bar = CreateFrame("StatusBar", nil, overlay)
    bar:SetUsingParentLevel(true)
    bar:SetAllPoints(overlay)
    bar:SetReverseFill(true)
    bar:SetStatusBarTexture(WHITE_TEXTURE)
    bar:SetStatusBarColor(0, 0, 0, SHADE_ALPHA)
    if mask then
        bar:GetStatusBarTexture():AddMaskTexture(mask)
    end
    bar:Hide()
    bars[overlay] = bar
end

-- Draws the overlay's mark bar in `layer`, at `subLevel`.
function MarkBar:SetDrawLayer(overlay, layer, subLevel)
    bars[overlay]:GetStatusBarTexture():SetDrawLayer(layer, math.min(subLevel, MAX_SUBLEVEL))
end

-- Shows on the overlay that marks will deal `stored` of the unit's `health`
-- (secret), or hides it when they won't deal any.
function MarkBar:Update(overlay, health, stored)
    local bar = bars[overlay]
    bar:SetMinMaxValues(0, health)
    bar:SetValue(stored)
    bar:SetShown(stored > 0)
end
