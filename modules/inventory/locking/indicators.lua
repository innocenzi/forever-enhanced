-- Lock indicators drawn on item buttons. The style comes from the "indicator"
-- setting. Each style is one Blizzard padlock atlas with a size and an anchor,
-- drawn on our own frame laid over the button (below the click shield).

local _, ns = ...

local Locking = ns:GetFeature("inventory", "locking")

local Indicators = {}
Locking.Indicators = Indicators

local SHADOW_OFFSET_X, SHADOW_OFFSET_Y = 1, -1
local SHADOW_COLOR = CreateColor(0, 0, 0, 0.9)

-- Indicator styles, keyed by the "indicator" dropdown options ("none" draws nothing).
-- height: on-screen height; the width follows the atlas aspect ratio.
local STYLES = {
    -- Small padlock with a drop shadow in the free bottom-left corner (top-left
    -- holds the junk coin and upgrade arrow, bottom-right the stack count).
    padlock = {
        atlas = "QuestSharing-Padlock",
        height = 16,
        anchor = "BOTTOMLEFT",
        offsetX = 2,
        offsetY = 2,
        shadow = true,
    },
    -- Blizzard's locked bank slot padlock, centered.
    center = {
        atlas = "bankslot-icon-lock",
        height = 24,
        anchor = "CENTER",
        offsetX = 0,
        offsetY = 0,
    },
    -- Blizzard's locked bank slot padlock, top-right corner.
    corner = {
        atlas = "bankslot-icon-lock",
        height = 20,
        anchor = "TOPRIGHT",
        offsetX = -2,
        offsetY = -2,
    },
}

-- Every dropdown option must have a style.
for _, entry in ipairs(Locking.settings) do
    if entry.key == "indicator" then
        for _, option in ipairs(entry.options) do
            assert(option == "none" or STYLES[option], "no lock indicator style for option: " .. option)
        end
    end
end

-- Per Blizzard item button: { holder, glyph, shadow, styleKey }.
local decorations = setmetatable({}, { __mode = "k" })

local function GetGlyphWidth(style)
    if not style.width then
        local info = C_Texture.GetAtlasInfo(style.atlas)
        style.width = info.width * style.height / info.height
    end
    return style.width
end

local function PlaceGlyph(texture, style, offsetX, offsetY)
    texture:SetAtlas(style.atlas)
    texture:SetSize(GetGlyphWidth(style), style.height)
    texture:ClearAllPoints()
    texture:SetPoint(style.anchor, style.offsetX + offsetX, style.offsetY + offsetY)
end

local function CreateDecoration(button)
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints()
    holder:SetFrameLevel(button:GetFrameLevel() + 1)

    return {
        holder = holder,
        shadow = holder:CreateTexture(nil, "OVERLAY", nil, 6),
        glyph = holder:CreateTexture(nil, "OVERLAY", nil, 7),
    }
end

local function ApplyStyle(decoration, style)
    PlaceGlyph(decoration.glyph, style, 0, 0)

    local shadow = decoration.shadow
    shadow:SetShown(style.shadow == true)
    if style.shadow then
        PlaceGlyph(shadow, style, SHADOW_OFFSET_X, SHADOW_OFFSET_Y)
        shadow:SetDesaturated(true)
        shadow:SetVertexColor(SHADOW_COLOR:GetRGBA())
    end
end

function Indicators:Update(button, styleKey)
    local style = STYLES[styleKey]
    local decoration = decorations[button]

    if not style then
        if decoration then
            decoration.holder:Hide()
        end
        return
    end

    if not decoration then
        decoration = CreateDecoration(button)
        decorations[button] = decoration
    end
    if decoration.styleKey ~= styleKey then
        ApplyStyle(decoration, style)
        decoration.styleKey = styleKey
    end
    decoration.holder:Show()
end

function Indicators:HideAll()
    for _, decoration in pairs(decorations) do
        decoration.holder:Hide()
    end
end
