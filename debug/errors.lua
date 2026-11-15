-- Our errors and blocked actions, as incidents. Errors come from BugGrabber
-- (!BugGrabber, BugSack's error catcher): Blizzard's error handler only takes
-- handlers from secure code, and replacing it would taint every error. BugSack
-- keeps the full error; the incident adds the context and the events before.

local _, ns = ...

local MAX_STACK_LINES = 10
-- Events dumped with an error: since this long before it.
local CONTEXT_SECONDS = 15

-- seen[message] / seen[event .. function]: logged this session.
local seen = {}

local function FindError(tableID)
    local errors = BugGrabber:GetDB()
    for index = #errors, 1, -1 do
        if tostring(errors[index]) == tableID then
            return errors[index]
        end
    end
end

local function FirstLines(text, count)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        table.insert(lines, "  " .. line)
        if #lines == count then
            break
        end
    end
    return table.concat(lines, "\n")
end

local function OnBugGrabbed(_, tableID)
    local err = FindError(tableID)
    if not (err and type(err.message) == "string") then
        return
    end
    local stack = type(err.stack) == "string" and err.stack or ""
    if not (err.message:find(ns.ADDON, 1, true) or stack:find(ns.ADDON, 1, true)) then
        return
    end
    local firstLine = err.message:match("^[^\n]*")
    if seen[err.message] then
        ns:Append("error.again", firstLine)
        return
    end
    seen[err.message] = true
    ns:Incident(
        "error",
        "error: " .. firstLine,
        "message: " .. err.message .. "\nstack:\n" .. FirstLines(stack, MAX_STACK_LINES),
        GetTime() - CONTEXT_SECONDS
    )
end

-- BugGrabber loads before us (OptionalDeps), or later when loaded on demand.
local listening = false
local function ListenToBugGrabber()
    if BugGrabber and not listening then
        listening = true
        EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", OnBugGrabbed, ns)
    end
end
ListenToBugGrabber()

local listener = CreateFrame("Frame")
listener:RegisterEvent("ADDON_LOADED")
listener:RegisterEvent("ADDON_ACTION_BLOCKED")
listener:RegisterEvent("ADDON_ACTION_FORBIDDEN")
listener:SetScript("OnEvent", function(_, event, addon, func)
    if event == "ADDON_LOADED" then
        ListenToBugGrabber()
        return
    end
    if addon ~= ns.ADDON then
        return
    end
    local key = event .. tostring(func)
    if seen[key] then
        ns:Append("blocked.again", event .. " " .. tostring(func))
        return
    end
    seen[key] = true
    ns:Incident(
        "blocked",
        ("%s: %s"):format(event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked", tostring(func)),
        nil,
        GetTime() - CONTEXT_SECONDS
    )
end)
