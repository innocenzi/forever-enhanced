-- Zone level ranges: the world map names the zone under the cursor with its level range, as
-- Blizzard's map does when the client knows it (C_Map.GetMapLevels), which it never does for
-- zones here (ranges.lua). On Blizzard's map (label.lua) and on map.seamless's view, which
-- names its maps through Levels:WithRange.
--
-- Files of this slice:
--   feature.lua  registration, lifecycle and the public API (this file)
--   locales.lua  strings
--   ranges.lua   the zones' level ranges, written by hand
--   label.lua    the range on Blizzard's area label

local _, ns = ...

local Levels = ns:RegisterFeature("map", "levels", {
    page = "map",
    order = 3,
})

function Levels:OnEnable()
    self.Label:Enable()
end

function Levels:OnDisable()
    self.Label:Disable()
end

-- `mapID`'s level range: the client's, else ours while the feature is active; nil without one.
function Levels:GetRange(mapID)
    local low, high = C_Map.GetMapLevels(mapID)
    if low and high and low > 0 and high > 0 then
        return low, high
    end
    local range = self:IsActive() and self.RANGES[mapID]
    if range then
        return range[1], range[2]
    end
end

-- `name` with `mapID`'s level range after it, coloured against the player's level, as
-- Blizzard's area label (AreaLabelFrameMixin:OnUpdate); `name` alone without a range.
function Levels:WithRange(name, mapID)
    local low, high = self:GetRange(mapID)
    if not low then
        return name
    end
    local level = UnitLevel("player")
    local color
    if level < low then
        color = GetQuestDifficultyColor(low)
    elseif level > high then
        -- (Blizzard's: zones entirely below the player's level aren't yellow)
        color = GetQuestDifficultyColor(high - 2)
    else
        color = QuestDifficultyColors["difficult"]
    end
    local range = low ~= high and low .. "-" .. high or tostring(high)
    return name .. RGBTableToColorCode(color) .. " (" .. range .. ")" .. FONT_COLOR_CODE_CLOSE
end
