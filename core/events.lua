-- Small event listener: a table of handlers keyed by event name, started and
-- stopped as a unit so features can tie their events to their lifecycle.

local _, ns = ...

local EventListenerMixin = {}

function EventListenerMixin:Start()
    for event in pairs(self.handlers) do
        self.frame:RegisterEvent(event)
    end
end

function EventListenerMixin:Stop()
    self.frame:UnregisterAllEvents()
end

function EventListenerMixin:Unregister(event)
    self.frame:UnregisterEvent(event)
end

-- handlers: { EVENT_NAME = function(listener, ...) end }
function ns:CreateEventListener(handlers)
    local listener = Mixin({ handlers = handlers, frame = CreateFrame("Frame") }, EventListenerMixin)
    listener.frame:SetScript("OnEvent", function(_, event, ...)
        handlers[event](listener, ...)
    end)
    return listener
end
