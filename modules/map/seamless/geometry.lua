-- Maps on the world. Positions on the world are normalized (u, v) on Azeroth's
-- map (947); lengths are "world units", the pixels of its art. Each continent,
-- zone and city is placed where C_Map.GetMapRectOnMap puts it on 947.

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")

local Geometry = {}
Seamless.Geometry = Geometry

local WORLD = 947
Geometry.WORLD = WORLD

-- Each city's zone, whose land is under the city's middle. A city's map is its
-- continent's child, and the continent gives it for any point of its whole
-- rectangle, which reaches well out over its zone: so the city counts only in
-- the middle of its rectangle (CITY_EDGE: the share of each side left to its
-- zone), and its zone comes before it (Kharanos is Dun Morogh, not Ironforge).
local CITY_ZONES = {
    [1453] = 1429, -- Stormwind City in Elwynn Forest
    [1454] = 1411, -- Orgrimmar in Durotar
    [1455] = 1426, -- Ironforge in Dun Morogh
    [1456] = 1412, -- Thunder Bluff in Mulgore
    [1457] = 1438, -- Darnassus in Teldrassil
    [1458] = 1420, -- Undercity in Tirisfal Glades
}
local CITY_EDGE = 0.25

-- mapID -> { left, right, top, bottom } on the world, or false off it
local rects = {}
local worldWidth, worldHeight

-- The map's first art layer: its width and height (its canvas units), and the layer.
function Geometry:ArtSize(mapID)
    local layers = C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    if layer then
        return layer.layerWidth, layer.layerHeight, layer
    end
end

-- The world's size, in world units.
function Geometry:Size()
    if not worldWidth then
        worldWidth, worldHeight = self:ArtSize(WORLD)
    end
    return worldWidth, worldHeight
end

-- The map's rectangle on the world (left, right, top, bottom), or nothing off it.
function Geometry:Rect(mapID)
    if mapID == WORLD then
        return 0, 1, 0, 1
    end
    local rect = rects[mapID]
    if rect == nil then
        -- (errors for a map with no place on the world)
        local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, mapID, WORLD)
        rect = ok and left and right > left and bottom > top and { left, right, top, bottom } or false
        rects[mapID] = rect
    end
    if rect then
        return rect[1], rect[2], rect[3], rect[4]
    end
end

-- Whether the map is drawn on the stitched world: the world, a continent or a zone (cities are zones).
function Geometry:IsStitchable(mapID)
    if not mapID then
        return false
    end
    if mapID == WORLD then
        return true
    end
    local info = C_Map.GetMapInfo(mapID)
    if not info or (info.mapType ~= Enum.UIMapType.Continent and info.mapType ~= Enum.UIMapType.Zone) then
        return false
    end
    return self:Rect(mapID) ~= nil and self:ArtSize(mapID) ~= nil
end

-- A point of the map (normalized) on the world, and back.
function Geometry:ToWorld(mapID, x, y)
    local left, right, top, bottom = self:Rect(mapID)
    return left + x * (right - left), top + y * (bottom - top)
end

function Geometry:FromWorld(mapID, u, v)
    local left, right, top, bottom = self:Rect(mapID)
    return (u - left) / (right - left), (v - top) / (bottom - top)
end

-- The maps under a world point, from the world down: { 947, continent, zone },
-- and a city after its zone: { 947, continent, zone, city }.
function Geometry:ChainAt(u, v)
    local chain = { WORLD }
    local mapID, x, y = WORLD, u, v
    for _ = 1, 4 do
        local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
        if not info or info.mapID == mapID then
            break
        end
        if info.mapType ~= Enum.UIMapType.Continent and info.mapType ~= Enum.UIMapType.Zone then
            break
        end
        local left, right, top, bottom = C_Map.GetMapRectOnMap(info.mapID, mapID)
        if not left or right <= left or bottom <= top then
            break
        end
        local cx, cy = (x - left) / (right - left), (y - top) / (bottom - top)
        local zone = CITY_ZONES[info.mapID]
        if zone and self:Rect(zone) then
            table.insert(chain, zone)
            if math.min(cx, 1 - cx) < CITY_EDGE or math.min(cy, 1 - cy) < CITY_EDGE then
                break
            end
        end
        mapID, x, y = info.mapID, cx, cy
        table.insert(chain, mapID)
    end
    return chain
end

-- Whether the world point is in a city's own middle.
function Geometry:IsInCity(u, v)
    local chain = self:ChainAt(u, v)
    return CITY_ZONES[chain[#chain]] ~= nil
end
