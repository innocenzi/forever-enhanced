-- Incidents: something went wrong because of ForeverEnhanced (taint, an error,
-- a blocked action). Each is logged with the context it happened in and the
-- events just before it, and announced once in chat.

local _, ns = ...

local MAX_PER_SESSION = 30

local count = 0

local function ActiveFeatures()
    local addon = _G.ForeverEnhanced
    if not (addon and addon.EnumerateModules) then
        return "?"
    end
    local ids = {}
    for _, module in addon:EnumerateModules() do
        for _, feature in ipairs(module.sortedFeatures) do
            if feature:IsActive() then
                table.insert(ids, module.id .. "." .. feature.id)
            end
        end
    end
    return table.concat(ids, " ")
end

local function Context()
    local inInstance, instanceType = IsInInstance()
    return ("zone=%s instance=%s combat=%s version=%s\n  active: %s"):format(
        tostring(GetRealZoneText()),
        inInstance and tostring(instanceType) or "none",
        tostring(InCombatLockdown()),
        C_AddOns.GetAddOnMetadata(ns.ADDON, "Version") or "?",
        ActiveFeatures()
    )
end

-- Logs an incident under `tag`: `summary` (one line, also shown in chat),
-- `details` (more lines, or nil) and the events recorded since `since`
-- (GetTime()). At most MAX_PER_SESSION per session; returns whether logged.
function ns:Incident(tag, summary, details, since)
    if count >= MAX_PER_SESSION then
        return false
    end
    count = count + 1
    local ok, context = pcall(Context)
    local parts = { summary }
    if details then
        table.insert(parts, details)
    end
    table.insert(parts, "context: " .. (ok and context or "<" .. tostring(context) .. ">"))
    table.insert(parts, "events before:\n" .. self.Recorder:Dump(since))
    if count == MAX_PER_SESSION then
        table.insert(parts, ("(%d incidents: no more this session)"):format(MAX_PER_SESSION))
    end
    self:Append(tag, table.concat(parts, "\n"))
    self:Print(summary .. " (/fedebug)")
    return true
end
