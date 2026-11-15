-- Flight recorder: the last events the client fired, in memory only. An
-- incident dumps the ones just before it into the log, so the log tells what
-- happened before taint showed up without logging every event all the time.

local _, ns = ...

local Recorder = {}
ns.Recorder = Recorder

local SIZE = 300
local MAX_ARGS = 4
local MAX_DUMPED = 80

-- Too frequent to tell anything apart.
local SKIPPED = {
    COMBAT_LOG_EVENT_UNFILTERED = true,
    UNIT_AURA = true,
    UNIT_HEALTH = true,
    UNIT_MAXHEALTH = true,
    UNIT_POWER_UPDATE = true,
    UNIT_POWER_FREQUENT = true,
    UNIT_ABSORB_AMOUNT_CHANGED = true,
    UNIT_THREAT_LIST_UPDATE = true,
    UNIT_THREAT_SITUATION_UPDATE = true,
    UNIT_COMBAT = true,
    SPELL_UPDATE_COOLDOWN = true,
    SPELL_UPDATE_USABLE = true,
    ACTIONBAR_UPDATE_COOLDOWN = true,
    ACTIONBAR_UPDATE_USABLE = true,
    ACTIONBAR_UPDATE_STATE = true,
    BAG_UPDATE_COOLDOWN = true,
    CURSOR_CHANGED = true,
    MODIFIER_STATE_CHANGED = true,
    WORLD_CURSOR_TOOLTIP_UPDATE = true,
    UPDATE_MOUSEOVER_UNIT = true,
    NAME_PLATE_UNIT_ADDED = true,
    NAME_PLATE_UNIT_REMOVED = true,
    CHAT_MSG_ADDON = true,
    CHAT_MSG_ADDON_LOGGED = true,
    UPDATE_UI_WIDGET = true,
    UPDATE_INVENTORY_DURABILITY = true,
    GLOBAL_MOUSE_DOWN = true,
    GLOBAL_MOUSE_UP = true,
}

-- Ring buffer of { time, combat, event, n, args }.
local records = {}
local nextIndex = 1

local function Record(event, ...)
    if SKIPPED[event] then
        return
    end
    -- Other units' events say little about what our code did.
    if event:find("^UNIT_") then
        local unit = ...
        if not (canaccessvalue(unit) and unit == "player") then
            return
        end
    end
    local count = math.min(select("#", ...), MAX_ARGS)
    records[nextIndex] = {
        time = GetTime(),
        combat = InCombatLockdown(),
        event = event,
        n = count,
        args = { ... },
    }
    nextIndex = nextIndex % SIZE + 1
end

local function FormatRecord(record)
    local ok, args = pcall(ns.Join, ns, unpack(record.args, 1, record.n))
    if not ok then
        args = "<not logged>"
    end
    local text = ("  [%.3f%s] %s"):format(record.time, record.combat and "!" or "", record.event)
    return args ~= "" and text .. " " .. args or text
end

-- The recorded events since `since` (GetTime()), oldest first, at most
-- MAX_DUMPED (the latest); consecutive identical lines collapse.
function Recorder:Dump(since)
    local lines = {}
    for offset = 0, SIZE - 1 do
        local record = records[(nextIndex - 1 + offset) % SIZE + 1]
        if record and record.time >= since then
            local line = FormatRecord(record)
            local last = lines[#lines]
            if last and last.line == line then
                last.count = last.count + 1
            else
                table.insert(lines, { line = line, count = 1 })
            end
        end
    end
    local first = math.max(1, #lines - MAX_DUMPED + 1)
    local texts = {}
    if first > 1 then
        table.insert(texts, ("  ... %d earlier"):format(first - 1))
    end
    for index = first, #lines do
        local entry = lines[index]
        table.insert(texts, entry.count > 1 and ("%s (x%d)"):format(entry.line, entry.count) or entry.line)
    end
    if #texts == 0 then
        return "  (none recorded)"
    end
    return table.concat(texts, "\n")
end

local listener = CreateFrame("Frame")
listener:RegisterAllEvents()
listener:SetScript("OnEvent", function(_, event, ...)
    Record(event, ...)
end)
