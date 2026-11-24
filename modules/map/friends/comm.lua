-- Addon messages between friends' clients. A channel is one addon message
-- prefix, paced (core/pacing.lua), and only the latest message to each friend
-- waits in its queue, which keeps it as long as the number of friends at most.
-- Messages from anyone but an online friend are dropped.
--
-- The addon's own protocol has a channel of its own (Comm:Send). Every message
-- starts with the protocol version:
--   "1W"                  the sender's map is open: answer with your position
--   "1P:<mapID>:<x>:<y>"  the sender's position on a map
--   "1H"                  the sender has no position to share (in an instance)
-- openmap.lua speaks OpenMap's protocol on another channel.

local _, ns = ...

local Friends = ns:GetFeature("map", "friends")
local Roster = Friends.Roster

local Comm = {}
Friends.Comm = Comm

local PREFIX = "FEFriends"
local VERSION = "1"

Comm.WATCH = VERSION .. "W"
Comm.HIDDEN = VERSION .. "H"

local Channel = {}
Channel.__index = Channel

local channels = {}

-- A channel on `prefix`, registered now. onMessage(guid, text) gets what
-- online friends send on it while it's started.
function Comm:CreateChannel(prefix, onMessage)
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    local channel = setmetatable({
        prefix = prefix,
        -- friends with a message waiting, in order, and the message for each
        queue = {},
        pending = {},
    }, Channel)
    channel.pacer = ns:CreateMessagePacer(channel)
    channel.listener = ns:CreateEventListener({
        CHAT_MSG_ADDON = function(_, messagePrefix, text, chatType, sender)
            if messagePrefix ~= prefix or chatType ~= "WHISPER" then
                return
            end
            local guid = Roster:FindBySender(sender)
            if guid then
                onMessage(guid, text)
            end
        end,
        BN_CHAT_MSG_ADDON = function(_, messagePrefix, text, _, senderID)
            if messagePrefix ~= prefix then
                return
            end
            local guid = Roster:FindByGameAccount(senderID)
            if guid then
                onMessage(guid, text)
            end
        end,
    })
    table.insert(channels, channel)
    return channel
end

-- False when the client throttled the message, to send it again later.
function Channel:Deliver(guid, message)
    local friend = Roster:Get(guid)
    if not friend then
        return true
    end
    local result
    if friend.gameAccountID then
        result = C_BattleNet.SendGameData(friend.gameAccountID, self.prefix, message)
    else
        result = C_ChatInfo.SendAddonMessage(self.prefix, message, "WHISPER", friend.name)
    end
    return not ns:IsMessageThrottled(result)
end

function Channel:HasNext()
    return #self.queue > 0
end

function Channel:SendNext()
    local guid = self.queue[1]
    if not self:Deliver(guid, self.pending[guid]) then
        return false
    end
    table.remove(self.queue, 1)
    self.pending[guid] = nil
    return true
end

-- Sends `message` to the online friend `guid`, replacing one still waiting.
function Channel:Send(guid, message)
    if not self.pending[guid] then
        table.insert(self.queue, guid)
    end
    self.pending[guid] = message
    self.pacer:Pump()
end

-- Starts receiving.
function Channel:Start()
    self.listener:Start()
end

-- Stops receiving. Messages still waiting go out.
function Channel:Stop()
    self.listener:Stop()
end

-- Drops the messages still waiting.
function Channel:Clear()
    self.pacer:Cancel()
    self.queue = {}
    self.pending = {}
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

local channel = Comm:CreateChannel(PREFIX, Dispatch)

function Comm:PositionMessage(mapID, x, y)
    return ("%sP:%d:%.4f:%.4f"):format(VERSION, mapID, x, y)
end

function Comm:Send(guid, message)
    channel:Send(guid, message)
end

-- Drops what an earlier session of the feature left waiting.
function Comm:Enable()
    for _, each in ipairs(channels) do
        each:Clear()
    end
    channel:Start()
end

-- Stops receiving on every channel. What still waits (the parts' goodbyes)
-- goes out at the usual pace.
function Comm:Disable()
    for _, each in ipairs(channels) do
        each:Stop()
    end
end
