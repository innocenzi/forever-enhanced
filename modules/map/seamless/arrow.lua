-- The player's arrow on the seamless view, which covers Blizzard's map and its
-- own arrow. On the view, not its canvas, so it keeps its size as the map zooms.

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")

local Arrow = {}
Seamless.Arrow = Arrow

-- Blizzard's own arrow on its map (GroupMembersDataProvider's player pin), so the two match as
-- the view fades in and out over it.
local ATLAS = "UI-WorldMapArrow"
local SIZE = 27
Arrow.SIZE = SIZE

local frame, texture

-- Shows the arrow at (x, y) from the middle of `view` (screen px, y up), turned to `facing`.
function Arrow:Show(view, level, x, y, facing)
    if not frame then
        frame = CreateFrame("Frame", nil, view)
        frame:SetSize(SIZE, SIZE)
        texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetAtlas(ATLAS)
        frame:SetFrameLevel(level)
    end
    frame:SetPoint("CENTER", view, "CENTER", x, y)
    texture:SetRotation(facing)
    frame:Show()
end

function Arrow:Hide()
    if frame then
        frame:Hide()
    end
end
