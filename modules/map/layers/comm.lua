-- LayerSwap's addon whispers, both ways. Sending is paced (core/pacing.lua):
-- messages wait in order, and one the client throttles waits for the next
-- round. A message can be a function, called when it goes out, so a burst
-- carries what the player knows by then (the layer read meanwhile). Messages
-- belong to an owner (an ask) that can drop the rest of them.
--
-- Received whispers go to the host when they ask for a swap, to the swap
-- otherwise (replies to the player's own ask).

local _, ns = ...

local Layers = ns:GetFeature("map", "layers")
local Protocol = Layers.Protocol

local Comm = {}
Layers.Comm = Comm

C_ChatInfo.RegisterAddonMessagePrefix(Protocol.PREFIX)

-- { target, message (a string, or a function returning one), owner, onSent }
local queue = {}

-- What waits, for the pacer.
local Outbox = {}

function Outbox:HasNext()
    return #queue > 0
end

function Outbox:SendNext()
    local entry = queue[1]
    local message = entry.message
    if type(message) == "function" then
        message = message()
    end
    local result = C_ChatInfo.SendAddonMessage(Protocol.PREFIX, message, "WHISPER", entry.target)
    if ns:IsMessageThrottled(result) then
        return false
    end
    table.remove(queue, 1)
    if entry.onSent then
        entry.onSent(entry.target, result == Enum.SendAddonMessageResult.Success)
    end
    return true
end

local pacer = ns:CreateMessagePacer(Outbox)

-- Whispers `message` to `target` ("Name-Realm" or "Name") after what waits.
-- onSent(target, delivered) once the client took or refused it.
function Comm:Send(target, message, owner, onSent)
    table.insert(queue, { target = target, message = message, owner = owner, onSent = onSent })
    pacer:Pump()
end

-- Drops the messages of `owner` still waiting.
function Comm:Drop(owner)
    for index = #queue, 1, -1 do
        if queue[index].owner == owner then
            table.remove(queue, index)
        end
    end
end

local listener = ns:CreateEventListener({
    CHAT_MSG_ADDON = function(_, prefix, text, chatType, sender)
        if ns:IsAnySecret(prefix, text, sender) then
            return
        end
        if prefix ~= Protocol.PREFIX or chatType ~= "WHISPER" then
            return
        end
        if Protocol:SenderKey(sender) == Protocol:UnitKey("player") then
            return
        end
        if Protocol:IsAsk(text) then
            Layers.Host:OnAsk(text, sender)
        else
            Layers.Swap:OnReply(text, sender)
        end
    end,
})

function Comm:Enable()
    listener:Start()
end

function Comm:Disable()
    listener:Stop()
    pacer:Cancel()
    queue = {}
end
