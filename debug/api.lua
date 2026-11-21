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

-- Runs `func` once the player is logged in and the addon's features are
-- enabled (the next frame), for probes in probe.lua. An error is logged under
-- `tag` instead of thrown.
function ns:AtLogin(tag, func)
    local function Run()
        C_Timer.After(0, function()
            local ok, err = xpcall(func, function(message)
                return tostring(message) .. "\n" .. debugstack(2, 12, 0)
            end)
            if not ok then
                ns:Log(tag, "<probe failed: " .. err .. ">")
            end
        end)
    end
    if IsLoggedIn() then
        Run()
        return
    end
    local listener = CreateFrame("Frame")
    listener:RegisterEvent("PLAYER_LOGIN")
    listener:SetScript("OnEvent", function()
        listener:UnregisterEvent("PLAYER_LOGIN")
        Run()
    end)
end
