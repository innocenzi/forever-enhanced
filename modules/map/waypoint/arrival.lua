-- No event fires as the player moves, so the distance to the pin is checked on
-- a ticker, which only runs while a pin exists. A pin only clears once the
-- player has been out of range of it: one placed (or a range set) while
-- already standing within range stays until the player walks away and back.

local _, ns = ...

local Waypoint = ns:GetFeature("map", "waypoint")

local Arrival = {}
Waypoint.Arrival = Arrival

local TICK_SECONDS = 0.5

local ticker
local armed = false
-- The pin the ticker watches, to tell a new pin from a repeated update.
local watchedPin

-- Yards from the player to the pin, or nil when there is none or it can't be
-- compared (another continent, or the player is in an instance).
local function GetDistance()
    local point = C_Map.GetUserWaypoint()
    if not point then
        return nil
    end
    local continentID, pinPosition = C_Map.GetWorldPosFromMapPos(point.uiMapID, point.position)
    local playerY, playerX, _, instanceID = UnitPosition("player")
    if not continentID or not playerY or instanceID ~= continentID then
        return nil
    end
    local dx, dy = pinPosition.x - playerY, pinPosition.y - playerX
    return math.sqrt(dx * dx + dy * dy)
end

local function IsWithinRange()
    local distance = GetDistance()
    return distance ~= nil and distance <= Waypoint:GetSetting("range")
end

local function Check()
    -- A flight path passing over the pin isn't an arrival.
    if UnitOnTaxi("player") then
        return
    end
    if not IsWithinRange() then
        armed = true
    elseif armed then
        armed = false
        C_Map.ClearUserWaypoint()
        if Waypoint:GetSetting("announce") then
            UIErrorsFrame:AddExternalWarningMessage(NAVIGATION_DESTINATION_REACHED_MESSAGE)
        end
    end
end

local function GetPinKey()
    local point = C_Map.GetUserWaypoint()
    return point and ("%d:%f:%f"):format(point.uiMapID, point.position.x, point.position.y)
end

local function Update()
    local pin = GetPinKey()
    if pin ~= watchedPin then
        watchedPin = pin
        Arrival:Rearm()
    end
    if pin and not ticker then
        ticker = C_Timer.NewTicker(TICK_SECONDS, Check)
    elseif not pin and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local listener = ns:CreateEventListener({
    USER_WAYPOINT_UPDATED = Update,
    PLAYER_ENTERING_WORLD = Update,
})

function Arrival:Rearm()
    armed = not IsWithinRange()
end

function Arrival:Enable()
    listener:Start()
    Update()
end

function Arrival:Disable()
    listener:Stop()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    watchedPin = nil
    armed = false
end
