-- TEMPORARY debug logger, copied in by the debugging skill (.claude/skills/debugging).
-- Delete this file, its TOC line and every ns:Debug* call once the bug is fixed.
--
-- /fedebug shows the log in a window, selected for Ctrl+C; /fedebug clear
-- empties it. The log lives in memory only: a /reload starts a new one.
--
-- In combat, some APIs return secret values (e.g. cooldown times): addon code
-- can pass them along but not read them (tostring, concatenation, comparisons
-- throw). They print as <secret type>, like Blizzard's /dump does, and a log
-- call never throws into the code it instruments.

local addonName, ns = ...

local MAX_ENTRIES = 5000 -- older entries are dropped
local MAX_DEPTH = 3 -- nested tables deeper than this print as {...}
local MAX_KEYS = 40 -- per table
local FRAME_NAME = "ForeverEnhancedDebugFrame" -- UISpecialFrames needs a name

-- Each entry: { time, combat, tag, text, count, lastTime }; consecutive
-- identical entries are counted on the first one.
local entries = {}
local dropped = 0
local frame
local shownText = ""

local Serialize

local function KeyOrder(a, b)
    local typeA, typeB = type(a), type(b)
    if typeA ~= typeB then
        return typeA < typeB
    end
    if typeA == "number" or typeA == "string" then
        return a < b
    end
    return tostring(a) < tostring(b)
end

-- Secret keys can't be compared: such a table keeps its pairs() order.
local function SortKeys(keys)
    for _, key in ipairs(keys) do
        if not canaccessvalue(key) then
            return
        end
    end
    table.sort(keys, KeyOrder)
end

local function SerializeTable(value, depth, seen)
    if not canaccesstable(value) then
        return "<secret table>"
    end
    -- Widgets are tables around a userdata at [0]: print their name, not their fields.
    if type(value[0]) == "userdata" and value.GetObjectType then
        return ("<%s %s>"):format(value:GetObjectType(), value:GetDebugName() or "?")
    end
    if seen[value] then
        return "<cycle>"
    end
    if depth >= MAX_DEPTH then
        return "{...}"
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    SortKeys(keys)
    local parts = {}
    for index, key in ipairs(keys) do
        if index > MAX_KEYS then
            table.insert(parts, ("...+%d"):format(#keys - MAX_KEYS))
            break
        end
        local valueText = Serialize(value[key], depth + 1, seen)
        -- The array part (sorted first) prints without its indices.
        if type(key) == "number" and canaccessvalue(key) and key == index then
            table.insert(parts, valueText)
        else
            local keyText = type(key) == "string" and canaccessvalue(key) and key:match("^[%a_][%w_]*$") and key
                or "[" .. Serialize(key, depth + 1, seen) .. "]"
            table.insert(parts, keyText .. "=" .. valueText)
        end
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

function Serialize(value, depth, seen)
    local valueType = type(value)
    if not canaccessvalue(value) then
        return ("<secret %s>"):format(valueType)
    elseif valueType == "string" then
        return depth == 0 and value or ("%q"):format(value)
    elseif valueType == "table" then
        return SerializeTable(value, depth, seen)
    elseif valueType == "function" then
        return "<function>"
    end
    return tostring(value)
end

local function Join(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = Serialize((select(index, ...)), 0, {})
    end
    return table.concat(parts, " ")
end

-- Logs `...` (any values; tables are dumped) under `tag`.
-- An entry that can't be built is logged as such instead of throwing.
function ns:DebugLog(tag, ...)
    local ok, text = pcall(Join, ...)
    if not ok then
        text = "<not logged: " .. tostring(text) .. ">"
    end
    tag = tostring(tag)
    local now = GetTime()
    local combat = InCombatLockdown()
    local last = entries[#entries]
    if last and last.tag == tag and last.text == text and last.combat == combat then
        last.count = last.count + 1
        last.lastTime = now
        return
    end
    table.insert(entries, { time = now, combat = combat, tag = tag, text = text, count = 1 })
    if #entries > MAX_ENTRIES then
        table.remove(entries, 1)
        dropped = dropped + 1
    end
end

-- "[time] tag: values", "!" after the time in combat; repeats as
-- "[first-last] tag: values (xN)".
local function FormatEntry(entry)
    local time = ("%.3f"):format(entry.time)
    local repeats = ""
    if entry.count > 1 then
        time = time .. ("-%.3f"):format(entry.lastTime)
        repeats = (" (x%d)"):format(entry.count)
    end
    return ("[%s%s] %s: %s%s"):format(time, entry.combat and "!" or "", entry.tag, entry.text, repeats)
end

-- What the log was taken from, for whoever reads it.
local function FormatHeader()
    local _, build = GetBuildInfo()
    local header = ("%s %s, build %s, %s, exported at %.3f, %d entries"):format(
        addonName,
        C_AddOns.GetAddOnMetadata(addonName, "Version"),
        build,
        GetLocale(),
        GetTime(),
        #entries
    )
    if dropped > 0 then
        header = header .. (" (%d older dropped)"):format(dropped)
    end
    return header
end

-- Logs every firing of the given events with their arguments.
function ns:DebugEvents(tag, ...)
    local listener = CreateFrame("Frame")
    for index = 1, select("#", ...) do
        listener:RegisterEvent((select(index, ...)))
    end
    listener:SetScript("OnEvent", function(_, event, ...)
        ns:DebugLog(tag, event, ...)
    end)
end

-- Logs every call of a function after it ran, with its arguments:
-- ns:DebugHook(tag, "GlobalFunction") or ns:DebugHook(tag, table, "method").
function ns:DebugHook(tag, target, method)
    local name = method or target
    local function Log(...)
        ns:DebugLog(tag, name, ...)
    end
    if method then
        hooksecurefunc(target, method, Log)
    else
        hooksecurefunc(target, Log)
    end
end

-- Logs the call stack of the caller.
function ns:DebugStack(tag)
    ns:DebugLog(tag, "\n" .. debugstack(2, 8, 0))
end

local function Refresh()
    local lines = { FormatHeader() }
    for _, entry in ipairs(entries) do
        table.insert(lines, FormatEntry(entry))
    end
    -- Doubled pipes keep color codes and links as plain text.
    shownText = table.concat(lines, "\n"):gsub("|", "||")
    frame.EditBox:SetText(shownText)
    frame.EditBox:SetFocus()
    frame.EditBox:HighlightText()
    C_Timer.After(0, function()
        frame.Scroll:SetVerticalScroll(frame.Scroll:GetVerticalScrollRange())
    end)
end

local function CreateButton(text, onClick)
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function BuildFrame()
    frame = CreateFrame("Frame", FRAME_NAME, UIParent, "PortraitFrameTemplate")
    frame:Hide()
    frame:SetSize(760, 540)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetTitle("Forever Enhanced debug log")
    frame:SetPortraitToAsset("Interface\\AddOns\\ForeverEnhanced\\media\\icon")
    table.insert(UISpecialFrames, FRAME_NAME)

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", 66, -34)
    hint:SetText("Ctrl+C copies the selected log. Refresh to see new entries.")

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -64)
    scroll:SetPoint("BOTTOMRIGHT", -32, 40)
    frame.Scroll = scroll

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(760 - 14 - 32)
    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)
    -- Read-only: typing puts the log back.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(shownText)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(editBox)
    frame.EditBox = editBox

    local refresh = CreateButton("Refresh", Refresh)
    refresh:SetPoint("BOTTOMRIGHT", -10, 10)
    local clear = CreateButton("Clear", function()
        wipe(entries)
        dropped = 0
        Refresh()
    end)
    clear:SetPoint("RIGHT", refresh, "LEFT", -6, 0)
    local selectAll = CreateButton("Select all", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    selectAll:SetPoint("RIGHT", clear, "LEFT", -6, 0)
end

SLASH_FOREVERENHANCEDDEBUG1 = "/fedebug"
SlashCmdList.FOREVERENHANCEDDEBUG = function(message)
    if strtrim(message):lower() == "clear" then
        wipe(entries)
        dropped = 0
        ns:Print("Debug log cleared.")
        return
    end
    if not frame then
        BuildFrame()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        Refresh()
    end
end
