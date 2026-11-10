-- The "share" part: answers friends whose map is open with the player's
-- position. A friend watches for WATCHER_SECONDS after each request (their
-- client asks again while the map stays open). The ticker runs only while
-- someone watches, and skips a friend whose last answer still holds, except
-- for a keepalive. Without a map position (in an instance), the answer is
-- "hidden", which removes the player from their map.

local _, ns = ...

local Friends = ns:GetFeature("map", "friends")
local Comm = Friends.Comm

local Sharing = {}
Friends.Sharing = Sharing

local TICK_SECONDS = 3
local WATCHER_SECONDS = 40
local KEEPALIVE_SECONDS = 15

-- guid -> time of the friend's last request
local watchers = {}
-- guid -> { message, time } of the last answer
local answers = {}
local ticker

local function CurrentMessage()
    if IsInInstance() then
        return Comm.HIDDEN
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return Comm.HIDDEN
    end
    return Comm:PositionMessage(mapID, position.x, position.y)
end

local function Answer(guid, message, now)
    local last = answers[guid]
    if last and last.message == message and now - last.time < KEEPALIVE_SECONDS then
        return
    end
    answers[guid] = { message = message, time = now }
    Comm:Send(guid, message)
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Tick()
    local now = GetTime()
    local message = CurrentMessage()
    for guid, watchedAt in pairs(watchers) do
        if now - watchedAt > WATCHER_SECONDS then
            watchers[guid] = nil
            answers[guid] = nil
        else
            Answer(guid, message, now)
        end
    end
    if next(watchers) == nil then
        StopTicker()
    end
end

-- A friend opened their map, or still has it open.
function Sharing:OnWatch(guid)
    if not Friends:IsPartActive("share") then
        return
    end
    local now = GetTime()
    local isNew = watchers[guid] == nil
    watchers[guid] = now
    if isNew then
        answers[guid] = nil
    end
    Answer(guid, CurrentMessage(), now)
    if not ticker then
        ticker = C_Timer.NewTicker(TICK_SECONDS, Tick)
    end
end

function Sharing:Enable() end

-- Removes the player from the map of friends still watching.
function Sharing:Disable()
    StopTicker()
    for guid in pairs(watchers) do
        Comm:Send(guid, Comm.HIDDEN)
    end
    watchers = {}
    answers = {}
end
