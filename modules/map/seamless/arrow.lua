-- The player's arrow, while the map underneath can't show it: Blizzard draws the
-- player only on a map they're on, and the stitched map shows the neighbours too
-- (on Westfall's map, the player just over the border in Elwynn Forest). On the
-- map's view, not its canvas, so it keeps its size as the map zooms.

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")

local Arrow = {}
Seamless.Arrow = Arrow

local SIZE = 28

local frame, texture

-- Shows the arrow at (x, y) from the middle of `view` (screen px, y up), turned to `facing`.
function Arrow:Show(view, level, x, y, facing)
    if not frame then
        frame = CreateFrame("Frame", nil, view)
        frame:SetSize(SIZE, SIZE)
        texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetAllPoints()
        texture:SetTexture("Interface\\Minimap\\MinimapArrow")
    end
    frame:SetFrameLevel(level)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", view, "CENTER", x, y)
    texture:SetRotation(facing)
    frame:Show()
end

function Arrow:Hide()
    if frame then
        frame:Hide()
    end
end
