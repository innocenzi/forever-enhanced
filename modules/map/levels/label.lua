-- The range on Blizzard's world map. Its area label (AreaLabelDataProvider's) names the map
-- under the cursor (a zone on a continent, a continent on the world), with a range only when
-- the client has one. While it names a map we have a range for, a font string of ours in its
-- name's place, font and colour shows the name with the range, and Blizzard's name is made
-- transparent.
--
-- TAINT: nothing of ours is written into Blizzard's map or its label. The label's OnUpdate is
-- post-hooked (HookScript: Blizzard's runs first and sets this frame's name); the hook only
-- reads the label's name, the map's ID and its cursor. Our font string sits on a frame of
-- ours (a child of the label's, for its scale, strata and visibility), and the name's alpha
-- (SetAlpha: no Lua value of Blizzard's) is the one change to the label, put back when ours
-- hides.

local _, ns = ...

local Levels = ns:GetFeature("map", "levels")

local Label = {}
Levels.Label = Label

local installed = false
local label -- Blizzard's area label frame
local text -- ours

-- The label of Blizzard's map, from its data provider.
local function FindLabel()
    for provider in pairs(WorldMapFrame.dataProviders) do
        if provider.OnSetAreaLabel == AreaLabelDataProviderMixin.OnSetAreaLabel and provider.Label then
            return provider.Label
        end
    end
end

-- What ours shows: the map Blizzard's label names, with our range; nil when it names none of
-- ours (nothing, an area of the zone, a higher priority label), or adds the client's range.
local function Text()
    local name = label.Name:GetText()
    local mapID = WorldMapFrame:GetMapID()
    if not name or name == "" or not mapID then
        return nil
    end
    local info = C_Map.GetMapInfoAtPosition(mapID, WorldMapFrame:GetNormalizedCursorPosition())
    if not info or info.mapID == mapID or not Levels.RANGES[info.mapID] or info.name ~= name then
        return nil
    end
    local low = C_Map.GetMapLevels(info.mapID)
    if low and low > 0 then
        return nil
    end
    return Levels:WithRange(info.name, info.mapID)
end

local function Hide()
    if text:IsShown() then
        text:Hide()
        label.Name:SetAlpha(1)
    end
end

local function Update()
    local shown = Levels:IsActive() and Text()
    if shown then
        text:SetText(shown)
        text:Show()
        label.Name:SetAlpha(0)
    else
        Hide()
    end
end

local function Install()
    installed = true
    label = FindLabel()
    if not label then
        return
    end
    local frame = CreateFrame("Frame", nil, label)
    frame:SetAllPoints(label)
    text = frame:CreateFontString(nil, "OVERLAY", "WorldMapTextFont")
    text:SetPoint("TOP", label.Name, "TOP")
    text:SetVertexColor(AREA_NAME_FONT_COLOR:GetRGB())
    text:Hide()
    label:HookScript("OnUpdate", Update)
end

function Label:Enable()
    if not installed then
        Install()
    end
end

function Label:Disable()
    if text then
        Hide()
    end
end
