-- The log, kept across reloads and sessions in ForeverEnhancedDebugDB:
-- { session = n, entries = { ... }, dropped = n, announce = true or nil }. A
-- session is one load of the UI (login or /reload). Each entry: { session, date, time, combat, tag,
-- text, count, lastTime }; consecutive identical entries are counted on the
-- first one. The debug addon loads before ForeverEnhanced (its OptionalDeps), so
-- entries logged before our saved variables load wait in `pending`.

local addonName, ns = ...

local MAX_ENTRIES = 5000 -- older entries are dropped

local pending = {}
local store

local function Trim(entries)
    while #entries > MAX_ENTRIES do
        table.remove(entries, 1)
        if store then
            store.dropped = store.dropped + 1
        end
    end
end

-- Adds `text` under `tag`, or counts it on the last entry when identical.
function ns:Append(tag, text)
    local entries = store and store.entries or pending
    local now = GetTime()
    local combat = InCombatLockdown()
    local last = entries[#entries]
    if last and last.session == self.session and last.tag == tag and last.text == text and last.combat == combat then
        last.count = last.count + 1
        last.lastTime = now
        return
    end
    table.insert(entries, {
        session = self.session,
        date = GetServerTime(),
        time = now,
        combat = combat,
        tag = tag,
        text = text,
        count = 1,
    })
    Trim(entries)
end

function ns:Clear()
    if store then
        wipe(store.entries)
        store.dropped = 0
    end
    wipe(pending)
end

function ns:GetEntries()
    return store and store.entries or pending
end

-- Whether incidents are announced in chat (off by default: they stay in the log).
function ns:IsAnnouncing()
    return store ~= nil and store.announce == true
end

function ns:SetAnnouncing(announce)
    if store then
        store.announce = announce or nil
    end
end

-- "[time] tag: text", "!" after the time in combat; repeats as
-- "[first-last] tag: text (xN)". Times are GetTime(), which restarts with
-- the client: session headers carry the date.
local function FormatEntry(entry)
    local time = ("%.3f"):format(entry.time)
    local repeats = ""
    if entry.count > 1 then
        time = time .. ("-%.3f"):format(entry.lastTime)
        repeats = (" (x%d)"):format(entry.count)
    end
    return ("[%s%s] %s: %s%s"):format(time, entry.combat and "!" or "", entry.tag, entry.text, repeats)
end

local function FormatHeader(count)
    local _, build = GetBuildInfo()
    local header = ("%s %s, build %s, %s, exported %s (%.3f), %d entries"):format(
        ns.ADDON,
        C_AddOns.GetAddOnMetadata(ns.ADDON, "Version") or "?",
        build,
        GetLocale(),
        date("%Y-%m-%d %H:%M:%S", GetServerTime()),
        GetTime(),
        count
    )
    if store and store.dropped > 0 then
        header = header .. (" (%d older dropped)"):format(store.dropped)
    end
    return header
end

-- The log as text; only this session's entries when `currentOnly`.
function ns:FormatLog(currentOnly)
    local lines, count, session = {}, 0, nil
    for _, entry in ipairs(self:GetEntries()) do
        if not currentOnly or entry.session == self.session then
            if entry.session ~= session then
                session = entry.session
                table.insert(
                    lines,
                    ("== session %s, %s =="):format(tostring(session), date("%Y-%m-%d %H:%M:%S", entry.date))
                )
            end
            table.insert(lines, FormatEntry(entry))
            count = count + 1
        end
    end
    table.insert(lines, 1, FormatHeader(count))
    return table.concat(lines, "\n")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, name)
    if name ~= addonName then
        return
    end
    loader:UnregisterEvent("ADDON_LOADED")
    local db = type(ForeverEnhancedDebugDB) == "table" and ForeverEnhancedDebugDB or {}
    ForeverEnhancedDebugDB = db
    db.session = (tonumber(db.session) or 0) + 1
    db.entries = type(db.entries) == "table" and db.entries or {}
    db.dropped = tonumber(db.dropped) or 0
    ns.session = db.session
    store = db
    for _, entry in ipairs(pending) do
        entry.session = ns.session
        table.insert(db.entries, entry)
    end
    wipe(pending)
    Trim(db.entries)
end)
