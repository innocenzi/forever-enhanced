-- Saved variables.
--
-- ForeverEnhancedDB (account):
--   language = "auto" (the client's) or one of ns.LANGUAGES
--   modules[moduleId] = { features = { [featureId] = { enabled, <schema keys> } } }
--   stores[moduleId][featureId] = feature-owned table, shared by every character
-- ForeverEnhancedCharacterDB (character):
--   [moduleId][featureId] = feature-owned table
--
-- Account settings are derived from the registered schemas: missing, mistyped,
-- unknown-option, out-of-range or blank text values get their default, unknown
-- keys are dropped.

local _, ns = ...

local Database = {
    -- The addon speaks the client's language unless the player picks another.
    LANGUAGE_DEFAULT = "auto",
}

local LANGUAGE_ENTRY = { options = { Database.LANGUAGE_DEFAULT, unpack(ns.LANGUAGES) } }
ns.Database = Database

local function GetOrCreateTable(parent, key)
    local value = parent[key]
    if type(value) ~= "table" then
        value = {}
        parent[key] = value
    end
    return value
end

-- Whether a value of the right type is allowed by the entry (dropdown options,
-- slider bounds, text that isn't blank).
local function IsAllowed(entry, value)
    if entry.type == "text" then
        return value:find("%S") ~= nil
    end
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

-- An entry without a default takes it from the locale, so it can be in the
-- player's language (every locale file is loaded and the language set by now).
-- A saved value left at another language's default follows the language.
local function ResolveDefault(featureDb, feature, entry)
    if entry.default ~= nil and not entry.localeDefault then
        return
    end
    local key = feature:GetLocaleKey(entry.key .. ".default")
    entry.default = assert(rawget(ns.L, key), "missing default: " .. key)
    entry.localeDefault = true
    if ns:IsLocaleString(key, featureDb[entry.key]) then
        featureDb[entry.key] = entry.default
    end
end

-- Preset values must name a known preset and a setting of the feature, with a
-- value its schema accepts: a typo fails at load instead of applying nothing.
local function ValidatePresets(feature, entries)
    for presetId, values in pairs(feature.presets) do
        local name = feature:GetLocaleKey() .. " preset " .. tostring(presetId)
        assert(tContains(ns.PRESETS, presetId), "unknown preset: " .. name)
        for key, value in pairs(values) do
            local entry = entries[key]
            if key == "enabled" then
                assert(type(value) == "boolean", "invalid value for enabled in " .. name)
            else
                assert(entry, "unknown setting " .. tostring(key) .. " in " .. name)
                assert(
                    type(value) == type(entry.default) and IsAllowed(entry, value),
                    "invalid value for " .. key .. " in " .. name
                )
            end
        end
    end
end

local function InitializeFeature(savedFeatures, feature)
    local featureDb = GetOrCreateTable(savedFeatures, feature.id)
    local knownKeys = { enabled = true }
    local entries = {}

    ApplyDefault(featureDb, "enabled", feature.enabledByDefault)
    for _, entry in ipairs(feature.settings) do
        ResolveDefault(featureDb, feature, entry)
        knownKeys[entry.key] = true
        entries[entry.key] = entry
        ApplyDefault(featureDb, entry.key, entry.default, entry)
    end

    KeepOnly(featureDb, knownKeys)
    ValidatePresets(feature, entries)
    feature.db = featureDb
end

local function InitializeModule(savedModules, module)
    local moduleDb = GetOrCreateTable(savedModules, module.id)
    local savedFeatures = GetOrCreateTable(moduleDb, "features")
    local knownFeatures = {}

    KeepOnly(moduleDb, { features = true })

    for _, feature in ipairs(module.sortedFeatures) do
        knownFeatures[feature.id] = true
        InitializeFeature(savedFeatures, feature)
    end

    KeepOnly(savedFeatures, knownFeatures)
end

-- Features that moved to another module: their settings follow them (these
-- slices keep no stores).
local MOVED_FEATURES = {
    { id = "ranks", from = "interface", to = "combat" },
    { id = "combopoints", from = "interface", to = "combat" },
    { id = "swaps", from = "interface", to = "combat" },
}

-- The saved features of a module, if any.
local function SavedFeatures(savedModules, moduleId)
    local moduleDb = savedModules[moduleId]
    return type(moduleDb) == "table" and type(moduleDb.features) == "table" and moduleDb.features or nil
end

-- Brings settings saved by earlier versions up to date, before the schemas apply.
local function Migrate(savedModules)
    -- Modules had their own toggle: one turned off turns off its features.
    for moduleId, moduleDb in pairs(savedModules) do
        if type(moduleDb) == "table" and moduleDb.enabled == false then
            for _, featureDb in pairs(SavedFeatures(savedModules, moduleId) or {}) do
                if type(featureDb) == "table" then
                    featureDb.enabled = false
                end
            end
        end
    end

    for _, move in ipairs(MOVED_FEATURES) do
        local from = SavedFeatures(savedModules, move.from)
        if from and from[move.id] ~= nil then
            local to = GetOrCreateTable(GetOrCreateTable(savedModules, move.to), "features")
            to[move.id] = to[move.id] or from[move.id]
            from[move.id] = nil
        end
    end

    -- Hiding Questie announcements moved from Objective announcements to Quest
    -- helpers, where it works on its own: it stays on only if it was in effect.
    local quests = SavedFeatures(savedModules, "quests")
    local announce = quests and quests.announce
    if type(announce) == "table" and announce.hideQuestie ~= nil then
        if announce.enabled == true and announce.hideQuestie == true then
            GetOrCreateTable(quests, "helpers").hideQuestie = true
        end
        announce.hideQuestie = nil
    end
end

function Database:Initialize()
    ForeverEnhancedDB = type(ForeverEnhancedDB) == "table" and ForeverEnhancedDB or {}
    ForeverEnhancedCharacterDB = type(ForeverEnhancedCharacterDB) == "table" and ForeverEnhancedCharacterDB or {}

    -- Before the modules: their locale defaults come in this language.
    ApplyDefault(ForeverEnhancedDB, "language", Database.LANGUAGE_DEFAULT, LANGUAGE_ENTRY)
    ns:SetLanguage(ForeverEnhancedDB.language)

    local savedModules = GetOrCreateTable(ForeverEnhancedDB, "modules")
    local knownModules = {}
    Migrate(savedModules)

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
