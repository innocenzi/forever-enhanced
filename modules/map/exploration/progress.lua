-- What's explored of a map. A zone's entries are its areas: its overlays (data.lua),
-- those showing the same areas as one, explored once the client lists one of them
-- (matched by size and offset). A continent's are its zones, the world's its
-- continents: each explored once all of its own entries are. Maps without any
-- (cities, dungeons, maps off Azeroth) have none.

local _, ns = ...

local Exploration = ns:GetFeature("map", "exploration")

local Progress = {}
Exploration.Progress = Progress

-- mapID -> its progress, or false without one
local cache = {}

local function Key(width, height, x, y)
    return width .. ":" .. height .. ":" .. x .. ":" .. y
end

-- The areas' names, each once, joined.
local function AreaNames(areaIDs)
    local names, seen = {}, {}
    for _, areaID in ipairs(areaIDs) do
        local name = C_Map.GetAreaInfo(areaID)
        if name and name ~= "" and not seen[name] then
            seen[name] = true
            table.insert(names, name)
        end
    end
    return #names > 0 and table.concat(names, ", ") or UNKNOWN
end

local function SortEntries(entries)
    table.sort(entries, function(a, b)
        return a.name < b.name
    end)
end

-- A zone's areas, from its overlays.
local function ZoneEntries(mapID, overlays)
    local explored = {}
    for _, info in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
        explored[Key(info.textureWidth, info.textureHeight, info.offsetX, info.offsetY)] = true
    end
    local entries, byAreas = {}, {}
    for _, overlay in ipairs(overlays) do
        local areaIDs = { select(5, unpack(overlay)) }
        local areas = table.concat(areaIDs, ",")
        local entry = byAreas[areas]
        if not entry then
            entry = { name = AreaNames(areaIDs), explored = 0, total = 1, area = true }
            byAreas[areas] = entry
            table.insert(entries, entry)
        end
        if explored[Key(overlay[1], overlay[2], overlay[3], overlay[4])] then
            entry.explored = 1
        end
    end
    return entries
end

-- A continent's zones, or the world's continents: each with its own progress.
local function ChildEntries(mapID)
    local entries = {}
    for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID) or {}) do
        local progress = Progress:Of(child.mapID)
        if progress then
            table.insert(entries, { name = child.name, explored = progress.explored, total = progress.total })
        end
    end
    return entries
end

-- The map's progress: { kind, explored, total, entries = { { name, explored, total, area } } },
-- `explored` counting the entries fully explored, `kind` what they are ("areas", "zones" or
-- "continents"); nil for a map without any.
function Progress:Of(mapID)
    if cache[mapID] == nil then
        local entries, kind
        local info = C_Map.GetMapInfo(mapID)
        local overlays = Exploration.Overlays[C_Map.GetMapArtID(mapID)]
        if overlays then
            entries, kind = ZoneEntries(mapID, overlays), "areas"
        elseif info and info.mapType == Enum.UIMapType.Continent then
            entries, kind = ChildEntries(mapID), "zones"
        elseif info and info.mapType == Enum.UIMapType.World then
            entries, kind = ChildEntries(mapID), "continents"
        end
        if entries and #entries > 0 then
            SortEntries(entries)
            local explored = 0
            for _, entry in ipairs(entries) do
                if entry.explored == entry.total then
                    explored = explored + 1
                end
            end
            cache[mapID] = { kind = kind, explored = explored, total = #entries, entries = entries }
        else
            cache[mapID] = false
        end
    end
    return cache[mapID] or nil
end

-- Forgets every map's progress: the player explored somewhere.
function Progress:Reset()
    wipe(cache)
end
