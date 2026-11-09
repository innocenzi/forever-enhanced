-- Saved banks, in the account store so every character can read them.
--
-- characters[guid] = {
--     name, class, realm,
--     tabs = { { size, items = { [slot] = { link, count, icon, quality, itemID, isBound, name } } }, ... },
--     bags = { [tabNumber] = { purchased, link, icon, quality } }, -- bank bag slots, from tab 2
-- }
--
-- Characters are grouped by realm name: Forever has no visible realms, and each
-- ruleset is its own realm.

local _, ns = ...

local Bank = ns:GetFeature("inventory", "bank")

local Store = {}
Bank.Store = Store

local function GetCharacters()
    local store = Bank:GetAccountStore()
    store.characters = store.characters or {}
    return store.characters
end

function Store:GetPlayerKey()
    return UnitGUID("player")
end

function Store:GetRealm()
    return GetNormalizedRealmName()
end

function Store:Save(record)
    GetCharacters()[self:GetPlayerKey()] = record
end

function Store:Get(key)
    return GetCharacters()[key]
end

function Store:Forget(key)
    GetCharacters()[key] = nil
end

-- How many of the item the character's saved bank holds (0 when none, or not saved).
function Store:CountItem(key, itemID)
    local record = self:Get(key)
    local count = 0
    for _, tab in ipairs(record and record.tabs or {}) do
        for _, item in pairs(tab.items) do
            if item.itemID == itemID then
                count = count + item.count
            end
        end
    end
    return count
end

-- Characters to pick from: { key, name, class, isPlayer }, the player first
-- (saved bank or not), then the alts of the same realm by name.
function Store:List()
    local playerKey, realm = self:GetPlayerKey(), self:GetRealm()
    local _, playerClass = UnitClass("player")
    local entries = {}

    for key, record in pairs(GetCharacters()) do
        if key ~= playerKey and record.realm == realm then
            table.insert(entries, { key = key, name = record.name, class = record.class })
        end
    end
    table.sort(entries, function(a, b)
        return a.name < b.name
    end)

    table.insert(entries, 1, { key = playerKey, name = UnitName("player"), class = playerClass, isPlayer = true })
    return entries
end
