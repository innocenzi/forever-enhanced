-- Reads TomTom's "[zone] x y [description]" and finds zones by name.
--
-- Coordinates are percents (0 to 100), written "45 63", "45.2 63.1",
-- "45.2, 63.1", "45,63", or with French decimal commas "45,2 63,1". The zone
-- is a name ("Elwynn Forest", any case) or a map ID ("#1429"). The game's pin
-- can't hold a label, so the description is ignored.

local _, ns = ...

local Pin = ns:GetFeature("map", "pin")

local Parser = {}
Pin.Parser = Parser

local NUMBER = "%d+%.?%d*"

-- Zone index of each map tree, by root map ID: { [normalized name] = map info }.
local indexes = {}

local function ToCoordinate(text)
    local value = text and tonumber(text)
    if value and value >= 0 and value <= 100 then
        return value
    end
end

-- The coordinates starting at words[i] (x and y, as text), or nil.
local function ReadCoordinates(words, i)
    local first, second = words[i], words[i + 1]
    -- "45,2 63,1"
    if second and first:match("^%d+,%d+$") and second:match("^%d+,%d+$") then
        return (first:gsub(",", ".")), (second:gsub(",", "."))
    end
    -- "45,63"
    local x, y = first:match("^(" .. NUMBER .. "),(" .. NUMBER .. ")$")
    if x then
        return x, y
    end
    -- "45 63", "45.2, 63.1"
    x, y = first:match("^(" .. NUMBER .. "),?$"), second and second:match("^(" .. NUMBER .. ")$")
    if x and y then
        return x, y
    end
end

-- { zone = text or nil, x, y }, x and y in percents, or nil when the text
-- holds no valid coordinates.
function Parser:Parse(text)
    local words = {}
    for word in text:gmatch("%S+") do
        table.insert(words, word)
    end
    for i = 1, #words do
        local x, y = ReadCoordinates(words, i)
        if x then
            x, y = ToCoordinate(x), ToCoordinate(y)
            if not x or not y then
                return nil
            end
            local zone = table.concat(words, " ", 1, i - 1)
            return { zone = zone ~= "" and zone or nil, x = x, y = y }
        end
    end
end

-- Case, spaces, commas, apostrophes and hyphens don't count in zone names.
local function Normalize(name)
    return (name:lower():gsub("’", ""):gsub("[%s',%-]", ""))
end

local function GetRootMapID()
    local mapID = C_Map.GetBestMapForUnit("player")
    local info = mapID and C_Map.GetMapInfo(mapID)
    while info and info.parentMapID and info.parentMapID ~= 0 do
        local parent = C_Map.GetMapInfo(info.parentMapID)
        if not parent then
            break
        end
        info = parent
    end
    return info and info.mapID
end

-- Every map under the root, zones winning over other maps of the same name.
local function BuildIndex(rootID)
    local index = {}
    for _, info in ipairs(C_Map.GetMapChildrenInfo(rootID, nil, true)) do
        local key = Normalize(info.name)
        local known = index[key]
        if not known or (known.mapType ~= Enum.UIMapType.Zone and info.mapType == Enum.UIMapType.Zone) then
            index[key] = info
        end
    end
    return index
end

-- The map ID named by a zone ("Elwynn Forest", "#1429"), or nil.
function Parser:FindMap(zone)
    local mapID = zone:match("^#(%d+)$")
    if mapID then
        return tonumber(mapID)
    end
    local rootID = GetRootMapID()
    if not rootID then
        return nil
    end
    indexes[rootID] = indexes[rootID] or BuildIndex(rootID)
    local info = indexes[rootID][Normalize(zone)]
    return info and info.mapID
end
