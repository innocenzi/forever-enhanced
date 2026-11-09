-- Saved variables.
--
-- ForeverEnhancedDB (account):
--   modules[moduleId] = { enabled, features = { [featureId] = { enabled, <schema keys> } } }
--   stores[moduleId][featureId] = feature-owned table, shared by every character
-- ForeverEnhancedCharacterDB (character):
--   [moduleId][featureId] = feature-owned table
--
-- Account settings are derived from the registered schemas: missing, mistyped
-- or unknown-option values get their default, unknown keys are dropped.

local _, ns = ...

local Database = {
    ENABLED_DEFAULT = true,
}
ns.Database = Database

local function GetOrCreateTable(parent, key)
    local value = parent[key]
    if type(value) ~= "table" then
        value = {}
        parent[key] = value
    end
    return value
end

-- Whether a value of the right type is allowed by the entry (dropdown options, slider bounds).
local function IsAllowed(entry, value)
    if entry.options then
        return tContains(entry.options, value)
    end
    if entry.min then
        return value >= entry.min and value <= entry.max
    end
    return true
end

local function ApplyDefault(tbl, key, default, entry)
    local value = tbl[key]
    if type(value) ~= type(default) or (entry and not IsAllowed(entry, value)) then
        tbl[key] = default
    end
end

local function KeepOnly(tbl, allowedKeys)
    for key in pairs(tbl) do
        if not allowedKeys[key] then
            tbl[key] = nil
        end
    end
end

local function InitializeFeature(savedFeatures, feature)
    local featureDb = GetOrCreateTable(savedFeatures, feature.id)
    local knownKeys = { enabled = true }

    ApplyDefault(featureDb, "enabled", Database.ENABLED_DEFAULT)
    for _, entry in ipairs(feature.settings) do
        knownKeys[entry.key] = true
        ApplyDefault(featureDb, entry.key, entry.default, entry)
    end

    KeepOnly(featureDb, knownKeys)
    feature.db = featureDb
end

local function InitializeModule(savedModules, module)
    local moduleDb = GetOrCreateTable(savedModules, module.id)
    local savedFeatures = GetOrCreateTable(moduleDb, "features")
    local knownFeatures = {}

    ApplyDefault(moduleDb, "enabled", Database.ENABLED_DEFAULT)
    KeepOnly(moduleDb, { enabled = true, features = true })

    for _, feature in ipairs(module.sortedFeatures) do
        knownFeatures[feature.id] = true
        InitializeFeature(savedFeatures, feature)
    end

    KeepOnly(savedFeatures, knownFeatures)
    module.db = moduleDb
end

function Database:Initialize()
    ForeverEnhancedDB = type(ForeverEnhancedDB) == "table" and ForeverEnhancedDB or {}
    ForeverEnhancedCharacterDB = type(ForeverEnhancedCharacterDB) == "table" and ForeverEnhancedCharacterDB or {}

    local savedModules = GetOrCreateTable(ForeverEnhancedDB, "modules")
    local knownModules = {}

    for _, module in ns:EnumerateModules() do
        knownModules[module.id] = true
        InitializeModule(savedModules, module)
    end

    KeepOnly(savedModules, knownModules)
end

function Database:GetCharacterStore(feature)
    local moduleStore = GetOrCreateTable(ForeverEnhancedCharacterDB, feature.module.id)
    return GetOrCreateTable(moduleStore, feature.id)
end

function Database:GetAccountStore(feature)
    local stores = GetOrCreateTable(ForeverEnhancedDB, "stores")
    local moduleStore = GetOrCreateTable(stores, feature.module.id)
    return GetOrCreateTable(moduleStore, feature.id)
end
