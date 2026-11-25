-- What marks (Death Mark) will deal, on an overlay (overlays.lua): a marker where
-- their hit will leave the health, which flashes just before the hit.
--
-- The marker stands where the fill of an unseen bar starts: one over the whole
-- overlay, filling in reverse from its right end (the health's).

local _, ns = ...

local DoTs = ns:GetFeature("combat", "dots")

local MarkBar = {}
DoTs.MarkBar = MarkBar

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
-- The experience bar's rested pip, and how it shows under the cursor (ExpBar.xml's
-- ExhaustionTick).
local PIP_ATLAS = "UI-HUD-ExperienceBar-Frame-Pip"
local PIP_WIDTH, PIP_HEIGHT = 10, 14
local PIP_FLASH_ATLAS = "UI-HUD-ExperienceBar-Frame-Pip-Mouseover"
local PIP_FLASH_WIDTH, PIP_FLASH_HEIGHT = 12, 14
-- The line, and its flash (in the color of the pip's).
local LINE_COLOR = { r = 1, g = 1, b = 1, a = 0.6 }
local LINE_WIDTH = 1
local LINE_FLASH_COLOR = { r = 1, g = 0.75, b = 0, a = 1 }
local LINE_FLASH_WIDTH = 3
-- The seconds a flash takes, and how long before the hit they start: a whole
-- number of flashes and a half, so that they start unlit and end lit, on the hit.
local FLASH_SECONDS = 0.4
local FLASH_FROM = 4.5 * FLASH_SECONDS
-- Draw sublevels range from -8 to 7.
local MAX_SUBLEVEL = 7

-- The mark bar of each overlay: { bar, marker, flash }.
local marks = setmetatable({}, { __mode = "k" })

-- A texture of the pip, centered on the fill's start, past the bar's edges like
-- on the experience bar.
local function CreatePip(bar, atlas, width, height)
    local pip = bar:CreateTexture()
    pip:SetAtlas(atlas)
    pip:SetSize(width, height)
    pip:SetPoint("CENTER", bar:GetStatusBarTexture(), "LEFT")
    return pip
end

-- A line centered on the fill's start, within the bar's shape.
local function CreateLine(bar, mask, color, width)
    local line = bar:CreateTexture()
    line:SetColorTexture(color.r, color.g, color.b, color.a)
    line:SetWidth(width)
    local fill = bar:GetStatusBarTexture()
    line:SetPoint("TOP", fill, "TOPLEFT")
    line:SetPoint("BOTTOM", fill, "BOTTOMLEFT")
    if mask then
        line:AddMaskTexture(mask)
    end
    return line
end

-- `mask`: the health bar's shape, if it has one. `style`: see overlays.lua.
function MarkBar:Create(overlay, mask, style)
    local bar = CreateFrame("StatusBar", nil, overlay)
    bar:SetUsingParentLevel(true)
    bar:SetAllPoints(overlay)
    bar:SetReverseFill(true)
    bar:SetStatusBarTexture(WHITE_TEXTURE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    bar:Hide()
    local marker, flash
    if style.marker == "pip" then
        marker = CreatePip(bar, PIP_ATLAS, PIP_WIDTH, PIP_HEIGHT)
        flash = CreatePip(bar, PIP_FLASH_ATLAS, PIP_FLASH_WIDTH, PIP_FLASH_HEIGHT)
    else
        marker = CreateLine(bar, mask, LINE_COLOR, LINE_WIDTH)
        flash = CreateLine(bar, mask, LINE_FLASH_COLOR, LINE_FLASH_WIDTH)
    end
    flash:SetBlendMode("ADD")
    marks[overlay] = { bar = bar, marker = marker, flash = flash }
end

-- Draws the overlay's marker in `layer`, from `subLevel` up.
function MarkBar:SetDrawLayer(overlay, layer, subLevel)
    local mark = marks[overlay]
    mark.marker:SetDrawLayer(layer, math.min(subLevel, MAX_SUBLEVEL))
    mark.flash:SetDrawLayer(layer, math.min(subLevel + 1, MAX_SUBLEVEL))
end

-- How bright the flash is `left` seconds before the hit, from 0 to 1.
local function GetBrightness(left)
    if left >= FLASH_FROM then
        return 0
    end
    return (1 + math.cos(2 * math.pi * left / FLASH_SECONDS)) / 2
end

-- Shows on the overlay that marks will deal `stored` of the unit's `health`
-- (secret), the next in `left` seconds, or hides it when they won't deal any.
function MarkBar:Update(overlay, health, stored, left)
    local mark = marks[overlay]
    mark.bar:SetMinMaxValues(0, health)
    mark.bar:SetValue(stored)
    mark.bar:SetShown(stored > 0)
    if stored > 0 then
        mark.flash:SetAlpha(GetBrightness(left))
    end
end
