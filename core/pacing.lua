-- Paced addon messages: the client throttles each addon message prefix on its
-- own (about ten messages at once, then one per second), so whatever sends on
-- a prefix goes through a pacer, which stays just under that.

local _, ns = ...

local BURST = 8
local PER_SECOND = 1
local MIN_WAIT = 0.1

local THROTTLED = {
    [Enum.SendAddonMessageResult.AddonMessageThrottle] = true,
    [Enum.SendAddonMessageResult.ChannelThrottle] = true,
}

local PacerMixin = {}

function PacerMixin:Refill()
    local now = GetTime()
    self.tokens = math.min(BURST, self.tokens + (now - self.refilledAt) * PER_SECOND)
    self.refilledAt = now
end

function PacerMixin:Schedule()
    if self.timer or not self.source:HasNext() then
        return
    end
    self.timer = C_Timer.NewTimer(math.max(MIN_WAIT, (1 - self.tokens) / PER_SECOND), function()
        self.timer = nil
        self:Pump()
    end)
end

-- Sends what waits, as far as the pace allows, and the rest later.
function PacerMixin:Pump()
    self:Refill()
    while self.tokens >= 1 and self.source:HasNext() do
        self.tokens = self.tokens - 1
        if not self.source:SendNext() then
            self.tokens = 0
            break
        end
    end
    self:Schedule()
end

-- Stops sending what waits, until the next Pump.
function PacerMixin:Cancel()
    if self.timer then
        self.timer:Cancel()
        self.timer = nil
    end
end

-- A pacer for one prefix. `source` holds what waits: HasNext() says whether a
-- message does, SendNext() sends the next one and takes it off, or leaves it
-- and returns false when the client throttled it (ns:IsMessageThrottled).
function ns:CreateMessagePacer(source)
    return Mixin({ source = source, tokens = BURST, refilledAt = 0 }, PacerMixin)
end

-- Whether the client refused the message for now (result: what sending
-- returned), to send it again later.
function ns:IsMessageThrottled(result)
    return THROTTLED[result] == true
end
