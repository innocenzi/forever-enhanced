-- What the ticks will deal, drawn on an overlay's fill (overlays.lua), as if that
-- part of the health were alive: the animated art of Forever's Poisons skill bar,
-- drained of its green and tinted with the health bar's color, brightening toward
-- its end with that skill bar's flare.
--
-- A bar squeezes its texture to its own width, which here is the health left. So
-- the art isn't the overlay's texture: it lies on the health bar, at its own
-- proportions, and a mask on the overlay's fill shows the part over it.
--
-- The health bar's color may be secret: it is only handed over, never read.

local _, ns = ...

local DoTs = ns:GetFeature("combat", "dots")

local TickBar = {}
DoTs.TickBar = TickBar

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
-- The overlay's fill, under the art: seen on the health bar's edges, which the
-- art leaves.
local SHADE_ALPHA = 0.5
local ART_ATLAS = "Skillbar_Fill_Flipbook_Poisons"
-- The atlas holds the frames of a seamless loop, row by row.
local COLUMNS, ROWS = 2, 30
local FRAMES_PER_SECOND = 30
-- A frame's width, for one of its height.
local PROPORTION = 856 / 34
local FLARE_ATLAS = "Skillbar_Flare_Poisons"
local FLARE_WIDTH = 13
local FLARE_ALPHA = 0.6
-- Draw sublevels range from -8 to 7.
local MAX_SUBLEVEL = 7

-- What each overlay is drawn with: { healthBar, color, info (the atlas's), art,
-- flare }.
local drawings = setmetatable({}, { __mode = "k" })

local function CreateArt(overlay, healthBar, style, info)
    local art = overlay:CreateTexture()
    art:SetTexture(info.file or info.filename)
    art:SetDesaturated(true)
    art:SetWidth(style.height * PROPORTION)
    art:SetPoint("TOPLEFT", healthBar, "TOPLEFT", style.inset, -style.inset)
    art:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", style.inset, style.inset)
    return art
end

-- Adds its light along the fill's end.
local function CreateFlare(overlay, inset)
    local flare = overlay:CreateTexture()
    flare:SetAtlas(FLARE_ATLAS)
    flare:SetDesaturated(true)
    flare:SetBlendMode("ADD")
    flare:SetAlpha(FLARE_ALPHA)
    flare:SetWidth(FLARE_WIDTH)
    local fill = overlay:GetStatusBarTexture()
    flare:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, -inset)
    flare:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, inset)
    return flare
end

-- `mask`: the health bar's shape, if it has one. `style`: see overlays.lua.
function TickBar:SetUp(overlay, healthBar, mask, style)
    overlay:SetStatusBarTexture(WHITE_TEXTURE)
    overlay:SetStatusBarColor(0, 0, 0, SHADE_ALPHA)
    local fill = overlay:GetStatusBarTexture()
    local fillMask = overlay:CreateMaskTexture()
    fillMask:SetTexture(WHITE_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    fillMask:SetAllPoints(fill)

    local info = C_Texture.GetAtlasInfo(ART_ATLAS)
    local art = CreateArt(overlay, healthBar, style, info)
    local flare = CreateFlare(overlay, style.inset)
    art:AddMaskTexture(fillMask)
    flare:AddMaskTexture(fillMask)
    if mask then
        for _, texture in ipairs({ fill, art, flare }) do
            texture:AddMaskTexture(mask)
        end
    end
    drawings[overlay] = {
        healthBar = healthBar,
        color = style.color,
        info = info,
        art = art,
        flare = flare,
    }
end

-- Draws the overlay's fill and its art in `layer`, from `subLevel` up. Returns
-- the sublevel above them.
function TickBar:SetDrawLayer(overlay, layer, subLevel)
    local drawing = drawings[overlay]
    overlay:GetStatusBarTexture():SetDrawLayer(layer, math.min(subLevel, MAX_SUBLEVEL))
    drawing.art:SetDrawLayer(layer, math.min(subLevel + 1, MAX_SUBLEVEL))
    drawing.flare:SetDrawLayer(layer, math.min(subLevel + 2, MAX_SUBLEVEL))
    return subLevel + 3
end

-- Shows the animation's current frame, the same on every overlay.
local function ShowFrame(art, info)
    local frame = math.floor(GetTime() * FRAMES_PER_SECOND) % (COLUMNS * ROWS)
    local column, row = frame % COLUMNS, math.floor(frame / COLUMNS)
    local width = (info.rightTexCoord - info.leftTexCoord) / COLUMNS
    local height = (info.bottomTexCoord - info.topTexCoord) / ROWS
    local left = info.leftTexCoord + column * width
    local top = info.topTexCoord + row * height
    art:SetTexCoord(left, left + width, top, top + height)
end

local function Tint(drawing)
    local color = drawing.color
    local r, g, b
    if color then
        r, g, b = color.r, color.g, color.b
    else
        r, g, b = drawing.healthBar:GetStatusBarColor()
    end
    drawing.art:SetVertexColor(r, g, b)
    drawing.flare:SetVertexColor(r, g, b)
end

-- Shows on the overlay that the ticks will deal `ticks` of the unit's `health`
-- (secret).
function TickBar:Update(overlay, health, ticks)
    local drawing = drawings[overlay]
    overlay:SetMinMaxValues(0, health)
    overlay:SetValue(ticks)
    if ticks > 0 then
        ShowFrame(drawing.art, drawing.info)
        Tint(drawing)
    end
    -- An empty bar's fill may not sit at its left end.
    drawing.art:SetShown(ticks > 0)
    drawing.flare:SetShown(ticks > 0)
end
