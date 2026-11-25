-- What the ticks will deal, drawn on an overlay's fill (overlays.lua), as if that
-- part of the health were alive: the animated art of Forever's Poisons skill bar,
-- drained of its green and tinted with the health bar's color, up to the flare of
-- that skill bar's end.
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
-- A pale line along the flare's end.
local LINE_WIDTH = 1
local LINE_ALPHA = 0.45
-- Draw sublevels range from -8 to 7.
local MAX_SUBLEVEL = 7

-- What each overlay is drawn with: { healthBar, color, info (the atlas's), art,
-- flare, textures (the art, the flare and its line, from the lowest up) }.
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

-- A texture adding its light along the fill's end.
local function CreateEnd(overlay, width, inset)
    local texture = overlay:CreateTexture()
    texture:SetBlendMode("ADD")
    texture:SetWidth(width)
    local fill = overlay:GetStatusBarTexture()
    texture:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, -inset)
    texture:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, inset)
    return texture
end

local function CreateFlare(overlay, inset)
    local flare = CreateEnd(overlay, FLARE_WIDTH, inset)
    flare:SetAtlas(FLARE_ATLAS)
    flare:SetDesaturated(true)
    flare:SetAlpha(FLARE_ALPHA)
    return flare
end

local function CreateLine(overlay, inset)
    local line = CreateEnd(overlay, LINE_WIDTH, inset)
    line:SetColorTexture(1, 1, 1, LINE_ALPHA)
    return line
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
    local line = CreateLine(overlay, style.inset)
    art:AddMaskTexture(fillMask)
    flare:AddMaskTexture(fillMask)
    if mask then
        for _, texture in ipairs({ fill, art, flare, line }) do
            texture:AddMaskTexture(mask)
        end
    end
    drawings[overlay] = {
        healthBar = healthBar,
        color = style.color,
        info = info,
        art = art,
        flare = flare,
        textures = { art, flare, line },
    }
end

-- Draws the overlay's fill and its art in `layer`, from `subLevel` up. Returns
-- the sublevel above them.
function TickBar:SetDrawLayer(overlay, layer, subLevel)
    local textures = drawings[overlay].textures
    overlay:GetStatusBarTexture():SetDrawLayer(layer, math.min(subLevel, MAX_SUBLEVEL))
    for above, texture in ipairs(textures) do
        texture:SetDrawLayer(layer, math.min(subLevel + above, MAX_SUBLEVEL))
    end
    return subLevel + #textures + 1
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
    for _, texture in ipairs(drawing.textures) do
        texture:SetShown(ticks > 0)
    end
end
