-- Taint watches: Blizzard state our features touch, checked for taint from
-- ForeverEnhanced. A table field written by tainted code stays tainted
-- (issecurevariable says by whom), and Blizzard code reading it runs tainted
-- from there on.
--
-- Two ways to catch it:
--   - writer hooks: after a listed method ran, the fields it writes are
--     checked; tainted, the stack names the code on the call path (ours);
--   - a scan of every field of the watched tables every SCAN_INTERVAL: catches
--     tainted data too, without a stack, with the events since the last scan.
-- Each tainted field is logged once per session; each hook's stack too.
-- The watches only read Blizzard tables and post-hook their methods.
--
-- WATCHES: add the Blizzard state a bug showed tainted. Each entry:
--   name     incident tag suffix (taint.<name>)
--   resolve  returns the tables to watch now (called every scan: frames of
--            load-on-demand addons appear when loaded)
--   hooks    { { method, keys = { ... } } }: methods of those tables to hook
--            (when they have it), and the fields to check after each call
--   ignore   optional function(tbl, key): fields tainted by design

local _, ns = ...

local SCAN_INTERVAL = 0.5
-- Events dumped with an incident: since this long before the previous scan.
local CONTEXT_SECONDS = 2
local MAX_KEYS_LISTED = 20

local WATCHES = {
    {
        -- The tracker's update reads the player's auras: tainted, it throws
        -- in combat (ShouldShowMawBuffs).
        name = "objectiveTracker",
        resolve = function()
            local tables = { ObjectiveTrackerFrame }
            if ObjectiveTrackerManager then
                for module in pairs(ObjectiveTrackerManager.moduleToContainerMap) do
                    table.insert(tables, module)
                end
            end
            return tables
        end,
        hooks = {
            -- Container: dirty; modules: isDirty. The next frame's update runs
            -- with the taint of whoever marked it dirty (RunNextFrame).
            { method = "MarkDirty", keys = { "dirty", "isDirty" } },
            { method = "Update", keys = { "wasDisplayedLastLayout" } },
        },
    },
    {
        -- The tracker reads the quest log's focused quest.
        name = "questLog",
        resolve = function()
            return { QuestMapFrame, QuestMapFrame and QuestMapFrame.DetailsFrame }
        end,
        hooks = {},
    },
    {
        -- Every panel open or close reads it, and resizes the tracker.
        name = "panelManager",
        resolve = function()
            local tables = { UIPanelWindows }
            for name, attributes in pairs(UIPanelWindows) do
                if type(attributes) == "table" and not name:find("^ForeverEnhanced") then
                    table.insert(tables, attributes)
                end
            end
            return tables
        end,
        hooks = {},
        -- Our own panels (RegisterUIPanel) are ours to write.
        ignore = function(tbl, key)
            return tbl == UIPanelWindows and type(key) == "string" and key:find("^ForeverEnhanced") ~= nil
        end,
    },
}

-- reported[tbl][key]: logged this session. Weak keys: frames may go away.
local reported = setmetatable({}, { __mode = "k" })
local seenStacks = {}
-- hooked[tbl][method]
local hooked = setmetatable({}, { __mode = "k" })
local lastScan

local function IsTainted(tbl, key)
    local ok, secure, taintedBy = pcall(issecurevariable, tbl, key)
    if ok and not secure then
        return true, taintedBy
    end
    return false
end

local function IsReported(tbl, key)
    return reported[tbl] ~= nil and reported[tbl][key] == true
end

local function MarkReported(tbl, key)
    reported[tbl] = reported[tbl] or {}
    reported[tbl][key] = true
end

local function IsIgnored(watch, tbl, key)
    return watch.ignore ~= nil and watch.ignore(tbl, key)
end

local function CheckAfterCall(watch, method, keys, tbl)
    for _, key in ipairs(keys) do
        local tainted, taintedBy = IsTainted(tbl, key)
        if tainted and not IsIgnored(watch, tbl, key) then
            local stack = debugstack(2, 20, 0)
            if not seenStacks[stack] then
                seenStacks[stack] = true
                MarkReported(tbl, key)
                ns:Incident(
                    "taint." .. watch.name,
                    ("%s.%s tainted by %s (after %s)"):format(ns:Name(tbl), key, tostring(taintedBy), method),
                    "stack:\n" .. stack,
                    (lastScan or 0) - CONTEXT_SECONDS
                )
            end
        end
    end
end

local function InstallHooks(watch, tbl)
    hooked[tbl] = hooked[tbl] or {}
    for _, hook in ipairs(watch.hooks) do
        if not hooked[tbl][hook.method] and type(tbl[hook.method]) == "function" then
            hooked[tbl][hook.method] = true
            hooksecurefunc(tbl, hook.method, function(self)
                securecallfunction(CheckAfterCall, watch, hook.method, hook.keys, self)
            end)
        end
    end
end

-- Adds the newly tainted fields of `tbl` to `found`, as "owner.key (by)".
local function ScanTable(watch, tbl, found)
    for key in pairs(tbl) do
        if type(key) == "string" and not IsReported(tbl, key) then
            local tainted, taintedBy = IsTainted(tbl, key)
            if tainted and not IsIgnored(watch, tbl, key) then
                MarkReported(tbl, key)
                table.insert(found, ("%s.%s (%s)"):format(ns:Name(tbl), key, tostring(taintedBy)))
            end
        end
    end
end

local function ScanWatch(watch)
    local found = {}
    for _, tbl in pairs(watch.resolve()) do
        if type(tbl) == "table" then
            InstallHooks(watch, tbl)
            ScanTable(watch, tbl, found)
        end
    end
    if #found == 0 then
        return
    end
    local listed = {}
    for index = 1, math.min(#found, MAX_KEYS_LISTED) do
        listed[index] = "  " .. found[index]
    end
    if #found > MAX_KEYS_LISTED then
        table.insert(listed, ("  ...+%d"):format(#found - MAX_KEYS_LISTED))
    end
    ns:Incident(
        "taint." .. watch.name,
        ("%d %s field(s) found tainted"):format(#found, watch.name),
        table.concat(listed, "\n"),
        (lastScan or 0) - CONTEXT_SECONDS
    )
end

local function Scan()
    for _, watch in ipairs(WATCHES) do
        securecallfunction(ScanWatch, watch)
    end
    lastScan = GetTime()
end

-- Scans from login on, every SCAN_INTERVAL (an OnUpdate of our own frame,
-- out of the way of the addon's timers).
local scanner = CreateFrame("Frame")
local sinceScan = 0
scanner:RegisterEvent("PLAYER_LOGIN")
scanner:SetScript("OnEvent", function()
    scanner:UnregisterAllEvents()
    Scan()
    scanner:SetScript("OnUpdate", function(_, elapsed)
        sinceScan = sinceScan + elapsed
        if sinceScan >= SCAN_INTERVAL then
            sinceScan = 0
            Scan()
        end
    end)
end)
