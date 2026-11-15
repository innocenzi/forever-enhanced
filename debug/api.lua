-- What the debugging skill's temporary calls use (.claude/skills/debugging).
-- None of them ever throws into the code it instruments.

local _, ns = ...

-- Logs `...` (any values; tables are dumped) under `tag`.
-- An entry that can't be built is logged as such.
function ns:Log(tag, ...)
    local ok, text = pcall(self.Join, self, ...)
    if not ok then
        text = "<not logged: " .. tostring(text) .. ">"
    end
    self:Append(tostring(tag), text)
end

-- Logs every firing of the given events with their arguments.
function ns:Events(tag, ...)
    local listener = CreateFrame("Frame")
    for index = 1, select("#", ...) do
        listener:RegisterEvent((select(index, ...)))
    end
    listener:SetScript("OnEvent", function(_, event, ...)
        ns:Log(tag, event, ...)
    end)
end

-- Logs every call of a function after it ran, with its arguments:
-- ns:Hook(tag, "GlobalFunction") or ns:Hook(tag, table, "method").
function ns:Hook(tag, target, method)
    local name = method or target
    local function Log(...)
        ns:Log(tag, name, ...)
    end
    if method then
        hooksecurefunc(target, method, Log)
    else
        hooksecurefunc(target, Log)
    end
end

-- Logs the call stack of the caller.
function ns:Stack(tag)
    self:Log(tag, "\n" .. debugstack(2, 12, 0))
end
