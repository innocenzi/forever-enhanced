-- LayerSwap's addon whispers, both ways. Sending is paced like the client
-- allows an addon (a burst, then about one message a second per prefix):
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

local BURST = 8
local PER_SECOND = 1

local THROTTLED = {
    [Enum.SendAddonMessageResult.AddonMessageThrottle] = true,
    [Enum.SendAddonMessageResult.ChannelThrottle] = true,
}

C_ChatInfo.RegisterAddonMessagePrefix(Protocol.PREFIX)

-- { target, message (a string, or a function returning one), owner, onSent }
local queue = {}
local tokens = BURST
local refilledAt = 0
local pumpTimer

local function Refill()
    local now = GetTime()
    tokens = math.min(BURST, tokens + (now - refilledAt) * PER_SECOND)
    refilledAt = now
end

local Pump

local function SchedulePump()
    if pumpTimer or #queue == 0 then
        return
    end
    pumpTimer = C_Timer.NewTimer(math.max(0.1, (1 - tokens) / PER_SECOND), function()
        pumpTimer = nil
        Pump()
    end)
end

function Pump()
    Refill()
    while #queue > 0 and tokens >= 1 do
        local entry = queue[1]
        local message = entry.message
        if type(message) == "function" then
            message = message()
        end
        tokens = tokens - 1
        local result = C_ChatInfo.SendAddonMessage(Protocol.PREFIX, message, "WHISPER", entry.target)
        if THROTTLED[result] then
            tokens = 0
            break
        end
        table.remove(queue, 1)
        if entry.onSent then
            entry.onSent(entry.target, result == Enum.SendAddonMessageResult.Success)
        end
    end
    SchedulePump()
end

-- Whispers `message` to `target` ("Name-Realm" or "Name") after what waits.
-- onSent(target, delivered) once the client took or refused it.
function Comm:Send(target, message, owner, onSent)
    table.insert(queue, { target = target, message = message, owner = owner, onSent = onSent })
    Pump()
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
        if issecretvalue(prefix) or issecretvalue(text) or issecretvalue(sender) then
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
    if pumpTimer then
        pumpTimer:Cancel()
        pumpTimer = nil
    end
    queue = {}
end
