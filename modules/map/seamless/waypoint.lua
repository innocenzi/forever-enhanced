-- The map pin from the seamless view and quests.lua's continent pins, as Blizzard's map
-- handles it: placed with Ctrl Click or a click with the map's pin button on, on the
-- deepest map that takes one; and a click on it removes it in that mode, shares it in chat
-- (Shift Click) or with the group (Alt Click, map.pin's), or turns its tracking on or off.
-- Every change goes through ns:ShieldObjectiveTracker, and none in combat (feature.lua, TAINT).

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")
local Geometry = Seamless.Geometry

local Waypoint = {}
Seamless.Waypoint = Waypoint

-- Whether the map's pin button is on.
local function PinButtonOn()
    local button = WorldMapFrame.WorldMapTrackingPinButton
    return button and button.isActive
end

-- Whether a left click places a map pin (or removes the one under the cursor), as on
-- Blizzard's map (its CanPlacePin): with Ctrl, or with the map's pin button on.
function Waypoint:IsPinMode()
    return not C_GameRules.IsGameRuleActive(Enum.GameRule.WorldMapTrackingPinDisabled)
        and (PinButtonOn() or IsControlKeyDown())
end

-- Whether a map pin change may go ahead: not in combat, where it has Blizzard's open map put
-- its pin up from our code, which the game blocks there (saying so).
local function CanChange()
    if InCombatLockdown() then
        ns:Error(ERR_NOT_IN_COMBAT)
        return false
    end
    return true
end

-- Places the map pin at (x, y) on `mapID` (normalized), as Blizzard's map does; false when the
-- map takes none.
local function Place(mapID, x, y)
    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        return false
    end
    PlaySound(PinButtonOn() and SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE or SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK)
    ns:ShieldObjectiveTracker(function()
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(false)
    end)
    return true
end

-- A click in pin mode at (x, y) on `mapID` (normalized): the map pin there.
function Waypoint:PlaceOn(mapID, x, y)
    if CanChange() and not Place(mapID, x, y) then
        ns:Error(MAP_PIN_INVALID_MAP)
    end
end

-- A click in pin mode at (u, v) on the world: the map pin on the deepest map there that takes one.
function Waypoint:PlaceAt(u, v)
    if not CanChange() then
        return
    end
    local chain = Geometry:ChainAt(u, v)
    for index = #chain, 1, -1 do
        local mapID = chain[index]
        if Place(mapID, Geometry:FromWorld(mapID, u, v)) then
            return
        end
    end
    ns:Error(MAP_PIN_INVALID_MAP)
end

-- A click on the map pin, as on Blizzard's: removed (in pin mode), shared in chat (Shift
-- Click) or with the group (Alt Click), or its tracking turned on or off.
function Waypoint:Click()
    if self:IsPinMode() then
        if not CanChange() then
            return
        end
        ns:ShieldObjectiveTracker(function()
            C_Map.ClearUserWaypoint()
            C_SuperTrack.SetSuperTrackedUserWaypoint(false)
        end)
        PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_REMOVE)
    elseif IsModifiedClick("CHATLINK") then
        ChatFrameUtil.InsertLink(C_Map.GetUserWaypointHyperlink())
        PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CHAT_SHARE)
    elseif IsAltKeyDown() then
        local pin = ns:GetFeature("map", "pin")
        if pin:CanShare() then
            pin:Share()
        end
    elseif not IsModifierKeyDown() and CanChange() then
        local tracked = not C_SuperTrack.IsSuperTrackingUserWaypoint()
        ns:ShieldObjectiveTracker(function()
            C_SuperTrack.SetSuperTrackedUserWaypoint(tracked)
        end)
        PlaySound(tracked and SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_ON or SOUNDKIT.UI_MAP_WAYPOINT_SUPER_TRACK_OFF)
    end
end
