-- The /way, /wayb and /cway slash commands.
--
-- The chat edit box runs commands from hash_SlashCmdList, which it fills from
-- SlashCmdList and the SLASH_<KEY>n globals, moving each entry into a proxy
-- table behind SlashCmdList. Blizzard keeps these tables global so addons can
-- unregister commands: disabling removes ours from all of them. A command
-- another addon (TomTom) already registered is left to it.

local _, ns = ...

local L = ns.L
local Pin = ns:GetFeature("map", "pin")
local Parser = Pin.Parser

local Commands = {}
Pin.Commands = Commands

-- Our registered entries, each { key, command, handler }.
local registered = {}

-- Silent like Blizzard's own pin: the map, the arrow and the sound show it.
local function Place(mapID, x, y)
    if not mapID or not C_Map.CanSetUserWaypointOnMap(mapID) then
        ns:Error(MAP_PIN_INVALID_MAP)
        return
    end
    ns:ShieldObjectiveTracker(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        if Pin:GetSetting("track") then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end)
    PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK)
end

local function Clear()
    ns:ShieldObjectiveTracker(C_Map.ClearUserWaypoint)
    PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_REMOVE)
end

-- The zone the player is in. Guides write coordinates on the zone, while the
-- player's own map may be a starting area, a cave or a building inside it.
local function GetPlayerZone()
    local mapID = C_Map.GetBestMapForUnit("player")
    local info = mapID and not IsInInstance() and C_Map.GetMapInfo(mapID)
    while info and (info.mapType == Enum.UIMapType.Micro or info.mapType == Enum.UIMapType.Dungeon) do
        local parent = C_Map.GetMapInfo(info.parentMapID)
        if not parent or parent.mapType < Enum.UIMapType.Zone then
            break
        end
        info = parent
    end
    return info and info.mapID or mapID
end

-- /way [zone] x y [description], /way reset
local function PlaceFromText(text)
    local lower = text:lower()
    if lower == "reset" or lower == "reset all" then
        Clear()
        return
    end
    local point = Parser:Parse(text)
    if not point then
        ns:Print(L["map.pin.usage"])
        return
    end
    local mapID
    if point.zone then
        mapID = Parser:FindMap(point.zone)
        if not mapID then
            ns:Error(L["map.pin.unknownZone"]:format(point.zone))
            return
        end
    else
        mapID = GetPlayerZone()
    end
    Place(mapID, point.x / 100, point.y / 100)
end

-- /wayb [description]: the player's position.
local function WayBack()
    local mapID = GetPlayerZone()
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        ns:Error(MAP_PIN_INVALID_MAP)
        return
    end
    Place(mapID, position.x, position.y)
end

local COMMANDS = {
    { key = "FOREVERENHANCED_WAY", command = "/way", handler = PlaceFromText },
    { key = "FOREVERENHANCED_WAYB", command = "/wayb", handler = WayBack },
    { key = "FOREVERENHANCED_CWAY", command = "/cway", handler = Clear },
}

-- Whether another addon registered the command, imported by the chat edit box or not.
local function IsTaken(entry)
    local tag = entry.command:upper()
    if hash_SlashCmdList[tag] then
        return true
    end
    for key in pairs(SlashCmdList) do
        if key ~= entry.key then
            local i = 1
            local command = _G["SLASH_" .. key .. i]
            while command do
                if command:upper() == tag then
                    return true
                end
                i = i + 1
                command = _G["SLASH_" .. key .. i]
            end
        end
    end
    return false
end

function Commands:Register()
    for _, entry in ipairs(COMMANDS) do
        if not IsTaken(entry) then
            _G["SLASH_" .. entry.key .. "1"] = entry.command
            SlashCmdList[entry.key] = entry.handler
            table.insert(registered, entry)
        end
    end
end

function Commands:Unregister()
    local proxy = getmetatable(SlashCmdList).__index
    for _, entry in ipairs(registered) do
        local tag = entry.command:upper()
        SlashCmdList[entry.key] = nil
        proxy[entry.key] = nil
        _G["SLASH_" .. entry.key .. "1"] = nil
        if hash_SlashCmdList[tag] == entry.handler then
            hash_SlashCmdList[tag] = nil
        end
        if hash_ChatTypeInfoList[tag] == entry.key then
            hash_ChatTypeInfoList[tag] = nil
        end
    end
    wipe(registered)
end
