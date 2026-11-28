-- Recently run commands, per character: { recent = { key, ... } }, the most
-- recent first, at most MAX_RECENT.

local _, ns = ...

local Palette = ns:GetFeature("interface", "palette")

local Store = {}
Palette.Store = Store

local MAX_RECENT = 20

local function GetRecent()
    local store = Palette:GetCharacterStore()
    store.recent = store.recent or {}
    return store.recent
end

-- How recently each command ran: { [key] = rank }, higher for more recent.
function Store:GetLastRun()
    local lastRun = {}
    local recent = GetRecent()
    for index, key in ipairs(recent) do
        lastRun[key] = #recent - index + 1
    end
    return lastRun
end

function Store:Remember(key)
    local recent = GetRecent()
    for index = #recent, 1, -1 do
        if recent[index] == key then
            table.remove(recent, index)
        end
    end
    table.insert(recent, 1, key)
    for index = #recent, MAX_RECENT + 1, -1 do
        recent[index] = nil
    end
end
