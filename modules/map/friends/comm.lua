-- The message protocol between clients, under one addon message prefix. Every
-- message starts with the protocol version:
--   "1W"                  the sender's map is open: answer with your position
--   "1P:<mapID>:<x>:<y>"  the sender's position on a map
--   "1H"                  the sender has no position to share (in an instance)
--
-- The client throttles addon messages per prefix, so sending is paced: a
-- burst, then about one per second. Only the latest message to each friend
-- waits in the queue, which keeps it as long as the number of friends at most.
-- Messages from anyone but an online friend are dropped.

local _, ns = ...

local Friends = ns:GetFeature("map", "friends")
local Roster = Friends.Roster

local Comm = {}
Friends.Comm = Comm

local PREFIX = "FEFriends"
local VERSION = "1"
local BURST = 8
local PER_SECOND = 1

Comm.WATCH = VERSION .. "W"
Comm.HIDDEN = VERSION .. "H"

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local THROTTLED = {
    [Enum.SendAddonMessageResult.AddonMessageThrottle] = true,
    [Enum.SendAddonMessageResult.ChannelThrottle] = true,
}

-- Friends with a message waiting, in order, and the message for each.
local queue = {}
local pending = {}
local tokens = BURST
local refilledAt = 0
local pumpTimer

function Comm:PositionMessage(mapID, x, y)
    return ("%sP:%d:%.4f:%.4f"):format(VERSION, mapID, x, y)
end

local function Refill()
    local now = GetTime()
    tokens = math.min(BURST, tokens + (now - refilledAt) * PER_SECOND)
    refilledAt = now
end

-- False when the client throttled the message, to send it again later.
local function Deliver(guid, message)
    local friend = Roster:Get(guid)
    if not friend then
        return true
    end
    local result
    if friend.gameAccountID then
        result = C_BattleNet.SendGameData(friend.gameAccountID, PREFIX, message)
    else
        result = C_ChatInfo.SendAddonMessage(PREFIX, message, "WHISPER", friend.name)
    end
    return not THROTTLED[result]
end

local Pump

local function SchedulePump()
    if pumpTimer or #queue == 0 then
        return
    end
    local wait = math.max(0.1, (1 - tokens) / PER_SECOND)
    pumpTimer = C_Timer.NewTimer(wait, function()
        pumpTimer = nil
        Pump()
    end)
end

function Pump()
    Refill()
    while #queue > 0 and tokens >= 1 do
        local guid = queue[1]
        tokens = tokens - 1
        if not Deliver(guid, pending[guid]) then
            tokens = 0
            break
        end
        table.remove(queue, 1)
        pending[guid] = nil
    end
    SchedulePump()
end

function Comm:Send(guid, message)
    if not pending[guid] then
        table.insert(queue, guid)
    end
    pending[guid] = message
    Pump()
end

local function Dispatch(guid, text)
    if text:sub(1, 1) ~= VERSION then
        return
    end
    local kind = text:sub(2, 2)
    if kind == "W" then
        Friends.Sharing:OnWatch(guid)
    elseif kind == "H" then
        Friends.Map:OnHidden(guid)
    elseif kind == "P" then
        local mapID, x, y = text:match("^%dP:(%d+):([%d.]+):([%d.]+)$")
        if mapID then
            Friends.Map:OnPosition(guid, tonumber(mapID), tonumber(x), tonumber(y))
        end
    end
end

local listener = ns:CreateEventListener({
    CHAT_MSG_ADDON = function(_, prefix, text, channel, sender)
        if prefix ~= PREFIX or channel ~= "WHISPER" then
            return
        end
        local guid = Roster:FindBySender(sender)
        if guid then
            Dispatch(guid, text)
        end
    end,
    BN_CHAT_MSG_ADDON = function(_, prefix, text, _, senderID)
        if prefix ~= PREFIX then
            return
        end
        local guid = Roster:FindByGameAccount(senderID)
        if guid then
            Dispatch(guid, text)
        end
    end,
})

function Comm:Enable()
    tokens = BURST
    refilledAt = GetTime()
    listener:Start()
end

function Comm:Disable()
    listener:Stop()
    if pumpTimer then
        pumpTimer:Cancel()
        pumpTimer = nil
    end
    queue = {}
    pending = {}
end
