-- The "openmap" part: speaks the protocol of the OpenMap addon, so friends who
-- use OpenMap show on the world map, and the player on theirs while sharing.
-- OpenMap's messages, under its own prefix, fields separated by tabs:
--   "H1"                                    hello, sent to each friend as they come online
--   "H2"                                    answer to a hello, when not sharing
--   "L1 <uiMapID> <x> <y> <CLASS> <level>"  the sender's position (also the answer to a hello)
--   "L0"                                    the sender stopped sharing
-- A friend who sends anything uses OpenMap. Unlike the addon's own protocol,
-- OpenMap has no requests: each client sends its position to every friend who
-- uses OpenMap, every MOVING_SECONDS while moving and every STILL_SECONDS
-- otherwise, and drops a dot after GONE_SECONDS without news. OpenMap also
-- shares with the guild; this part only ever talks to friends.
--
-- With OpenMap itself loaded, this part does nothing: OpenMap speaks for the
-- player, and two clients on one prefix would answer twice.

local _, ns = ...

local Friends = ns:GetFeature("map", "friends")
local Roster, Comm, Map, Sharing = Friends.Roster, Friends.Comm, Friends.Map, Friends.Sharing

local OpenMap = {}
Friends.OpenMap = OpenMap

local PREFIX = "OpenMapLoc"
local TICK_SECONDS = 2
local MOVING_SECONDS = 10
local STILL_SECONDS = 60
local GONE_SECONDS = 150
-- a smaller change of x or y isn't a move
local MOVED = 0.002

-- guid -> true: friends greeted while online / friends known to use OpenMap
local greeted = {}
local users = {}
-- the last position sent, { mapID, x, y, time, message }; nil while not sharing
local last
-- runs while the part does, unless OpenMap itself is loaded
local ticker
local channel

-- The player's position while "share" is on, or nil.
local function SharedPosition()
    if not Friends:IsPartActive("share") then
        return nil
    end
    return Sharing:CurrentPosition()
end

local function PositionMessage(mapID, x, y)
    local _, classFile = UnitClass("player")
    return ("L1\t%d\t%.4f\t%.4f\t%s\t%d"):format(mapID, x, y, classFile, UnitLevel("player"))
end

local function Broadcast(message)
    for guid in pairs(users) do
        channel:Send(guid, message)
    end
end

local function StopSharing()
    if last then
        last = nil
        Broadcast("L0")
    end
end

local function Tick()
    local mapID, x, y = SharedPosition()
    if not mapID then
        StopSharing()
        return
    end
    local now = GetTime()
    if last then
        local moved = mapID ~= last.mapID or math.abs(x - last.x) > MOVED or math.abs(y - last.y) > MOVED
        if now - last.time < (moved and MOVING_SECONDS or STILL_SECONDS) then
            return
        end
    end
    last = { mapID = mapID, x = x, y = y, time = now, message = PositionMessage(mapID, x, y) }
    Broadcast(last.message)
end

local function OnMessage(guid, text)
    local kind, mapID, x, y = strsplit("\t", text)
    local isNew = not users[guid]
    users[guid] = true
    if kind == "H1" then
        local sharedMapID, sharedX, sharedY = SharedPosition()
        channel:Send(guid, sharedMapID and PositionMessage(sharedMapID, sharedX, sharedY) or "H2")
        return
    end
    if isNew and last then
        channel:Send(guid, last.message)
    end
    if kind == "L1" then
        mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
        if mapID and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            Map:SetPosition(guid, mapID, x, y, GONE_SECONDS)
        end
    elseif kind == "L0" then
        Map:ClearPosition(guid)
    end
end

channel = Comm:CreateChannel(PREFIX, OnMessage)

-- Says hello to online friends not greeted yet: those who use OpenMap answer.
local function Greet()
    for guid in Roster:Enumerate() do
        if not greeted[guid] then
            greeted[guid] = true
            channel:Send(guid, "H1")
        end
    end
end

-- Forgets friends who went offline, and greets those who came online.
function OpenMap:OnRosterChanged()
    if not ticker then
        return
    end
    for guid in pairs(greeted) do
        if not Roster:Get(guid) then
            greeted[guid], users[guid] = nil, nil
        end
    end
    Greet()
end

function OpenMap:Enable()
    if C_AddOns.IsAddOnLoaded("OpenMap") then
        return
    end
    channel:Start()
    Greet()
    Tick()
    ticker = C_Timer.NewTicker(TICK_SECONDS, Tick)
end

-- Tells friends who use OpenMap the player stopped sharing, and removes theirs.
function OpenMap:Disable()
    if not ticker then
        return
    end
    ticker:Cancel()
    ticker = nil
    StopSharing()
    channel:Stop()
    for guid in pairs(users) do
        Map:ClearPosition(guid)
    end
    greeted, users = {}, {}
end
