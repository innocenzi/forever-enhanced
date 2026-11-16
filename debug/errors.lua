-- Our errors and anyone's blocked actions, as incidents. Errors come from
-- BugGrabber (!BugGrabber, BugSack's error catcher): Blizzard's error handler
-- only takes handlers from secure code, and replacing it would taint every
-- error. BugSack keeps the full error; the incident adds the context and the
-- events before.

local _, ns = ...

local MAX_STACK_LINES = 10
-- Events dumped with an error: since this long before it.
local CONTEXT_SECONDS = 15

-- seen[message] / seen[event .. addon .. function] / seen[stack]: logged this session.
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

-- Blocked actions, under "blocked" when the game blames us. The game shows the
-- same red message for other addons' and for macros', so those are logged too
-- (as "blocked.other" and "blocked.macro") to tell who caused one.
local function OnActionBlocked(event, addon, func)
    local tag, culprit
    if event == "MACRO_ACTION_BLOCKED" or event == "MACRO_ACTION_FORBIDDEN" then
        tag, culprit, func = "blocked.macro", "a macro", addon -- the macro events carry only the function
    elseif addon == ns.ADDON then
        tag = "blocked"
    else
        tag, culprit = "blocked.other", tostring(addon)
    end
    local key = event .. tostring(addon) .. tostring(func)
    if seen[key] then
        ns:Append(tag .. ".again", event .. " " .. tostring(func))
        return
    end
    seen[key] = true
    local summary = ("%s: %s"):format(event:find("FORBIDDEN", 1, true) and "forbidden" or "blocked", tostring(func))
    if culprit then
        summary = summary .. " (" .. culprit .. ")"
    end
    ns:Incident(tag, summary, nil, GetTime() - CONTEXT_SECONDS)
end

-- The red "Interface action failed because of an AddOn" message: the events
-- above show it, and so does the panel manager, with no event, when tainted
-- code shows or hides a panel in combat (CheckProtectedFunctionsAllowed in
-- UIParentPanelManager.lua). The game shows it once per session; here the
-- first call of a burst is logged with its stack, which names the code that
-- caused it, and the rest only counted: one tainted quest log update calls it
-- twice per quest, from several callers at once.
local BURST_SECONDS = 5
local lastBlockedMessage = -math.huge

local function OnBlockedMessage()
    local now = GetTime()
    local inBurst = now - lastBlockedMessage < BURST_SECONDS
    lastBlockedMessage = now
    local stack = debugstack(2, 20, 0)
    if inBurst or seen[stack] then
        ns:Append("blocked.message.again", "interface action blocked message")
        return
    end
    seen[stack] = true
    ns:Incident("blocked.message", "interface action blocked message", "stack:\n" .. stack, now - CONTEXT_SECONDS)
end

hooksecurefunc("DisplayInterfaceActionBlockedMessage", function()
    securecallfunction(OnBlockedMessage)
end)

local listener = CreateFrame("Frame")
listener:RegisterEvent("ADDON_LOADED")
listener:RegisterEvent("ADDON_ACTION_BLOCKED")
listener:RegisterEvent("ADDON_ACTION_FORBIDDEN")
listener:RegisterEvent("MACRO_ACTION_BLOCKED")
listener:RegisterEvent("MACRO_ACTION_FORBIDDEN")
listener:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        ListenToBugGrabber()
        return
    end
    OnActionBlocked(event, ...)
end)
