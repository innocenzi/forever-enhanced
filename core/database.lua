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
-- keys are dropped. A multiselect is saved as { [option] = boolean } for every
-- option: a missing or mistyped option gets its default, unknown ones are dropped.

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
-- slider bounds, text that isn't blank, a multiselect's options as booleans).
local function IsAllowed(entry, value)
    if entry.type == "multiselect" then
        for option, selected in pairs(value) do
            if not tContains(entry.options, option) or type(selected) ~= "boolean" then
                return false
            end
        end
        return true
    end
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

-- Every option of a multiselect as a boolean: what `selection` says, else the default's.
local function CompleteSelection(entry, selection, default)
    local complete = {}
    for _, option in ipairs(entry.options) do
        local selected = selection[option]
        if type(selected) ~= "boolean" then
            selected = default[option] == true
        end
        complete[option] = selected
    end
    return complete
end

local function ApplyDefault(tbl, key, default, entry)
    local value = tbl[key]
    if entry and entry.type == "multiselect" then
        tbl[key] = CompleteSelection(entry, type(value) == "table" and value or {}, default)
        return
    end
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
        -- A key binding is the game's to save (core/settings.lua), and presets can't set it.
        if entry.type ~= "binding" then
            ResolveDefault(featureDb, feature, entry)
            knownKeys[entry.key] = true
            entries[entry.key] = entry
            ApplyDefault(featureDb, entry.key, entry.default, entry)
        end
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

-- Features that moved to another module: their settings and stores follow them.
local MOVED_FEATURES = {
    { id = "ranks", from = "interface", to = "combat" },
    { id = "combopoints", from = "interface", to = "combat" },
    { id = "swaps", from = "interface", to = "combat" },
}

-- Moves `container[from][id]` to `container[to][id]`, unless one is there already.
local function MoveFeatureEntry(container, move)
    local from = container[move.from]
    if type(from) == "table" and from[move.id] ~= nil then
        local to = GetOrCreateTable(container, move.to)
        if to[move.id] == nil then
            to[move.id] = from[move.id]
        end
        from[move.id] = nil
    end
end

-- The saved features of a module, if any.
local function SavedFeatures(savedModules, moduleId)
    local moduleDb = savedModules[moduleId]
    return type(moduleDb) == "table" and type(moduleDb.features) == "table" and moduleDb.features or nil
end

-- A part of `features[from]` (its toggle `part`, nested `keys`) that became the
-- feature `features[to]`: on only if the part was in effect (both toggles on,
-- a missing one counting as on), its nested settings follow. The old keys go
-- either way; a new feature already saved keeps its own values.
local function MovePartToFeature(features, from, part, to, keys)
    local old = features[from]
    if type(old) ~= "table" or old[part] == nil then
        return
    end
    if features[to] == nil then
        local new = { enabled = old.enabled ~= false and old[part] ~= false }
        for _, key in ipairs(keys) do
            new[key] = old[key]
        end
        features[to] = new
    end
    old[part] = nil
    for _, key in ipairs(keys) do
        old[key] = nil
    end
end

-- Brings settings and account stores saved by earlier versions up to date,
-- before the schemas apply.
local function Migrate(savedModules, stores)
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
        MoveFeatureEntry(stores, move)
    end

    -- Hiding Questie announcements moved from Objective announcements to Quest
    -- helpers, where it works on its own: it stays on only if it was in effect.
    local quests = SavedFeatures(savedModules, "quests")
    local announce = quests and quests.announce
    if type(announce) == "table" and announce.hideQuestie ~= nil then
        if announce.enabled == true and announce.hideQuestie == true then
            GetOrCreateTable(quests, "helpers").hideAnnouncements = true
        end
        announce.hideQuestie = nil
    end

    -- Hiding Questie announcements became hiding quest addon announcements
    -- (Questie and Polestar).
    local helpers = quests and quests.helpers
    if type(helpers) == "table" and helpers.hideQuestie ~= nil then
        if helpers.hideAnnouncements == nil then
            helpers.hideAnnouncements = helpers.hideQuestie
        end
        helpers.hideQuestie = nil
    end

    -- Tracking nearby quests moved from Quest helpers to a feature of its own:
    -- on only if it was in effect. Its "closest" scope became "anywhere".
    if type(helpers) == "table" and helpers.nearby ~= nil then
        local tracking = GetOrCreateTable(quests, "tracking")
        if tracking.enabled == nil then
            tracking.enabled = helpers.enabled ~= false and helpers.nearby == true
            for _, key in ipairs({ "scope", "range", "count", "sort", "dungeons", "keepManual" }) do
                tracking[key] = helpers[key]
            end
        end
        helpers.nearby = nil
    end
    local tracking = quests and quests.tracking
    if type(tracking) == "table" and tracking.scope == "closest" then
        tracking.scope = "anywhere"
    end

    -- Two-option dropdowns that became toggles.
    local inventory = SavedFeatures(savedModules, "inventory")
    local merchant = inventory and inventory.merchant
    if type(merchant) == "table" and merchant.repairFunds ~= nil then
        merchant.guildFunds = merchant.repairFunds == "guild"
        merchant.repairFunds = nil
    end
    local professions = SavedFeatures(savedModules, "professions")
    local reagents = professions and professions.reagents
    if type(reagents) == "table" and reagents.professions ~= nil then
        reagents.onlyMine = reagents.professions == "mine"
        reagents.professions = nil
    end

    -- The bank's two parts became features: Deposit and Withdraw buttons take the transfer
    -- settings, on only if its part was in effect, and the bank feature, now
    -- Saved bank, stays on only if its saved bank part was on.
    if inventory then
        MovePartToFeature(inventory, "bank", "transfers", "transfers", { "autoRefill", "autoDeposit", "autoSort" })
    end
    local bank = inventory and inventory.bank
    if type(bank) == "table" and bank.savedBank ~= nil then
        if bank.savedBank == false then
            bank.enabled = false
        end
        bank.savedBank = nil
    end

    -- The Wowhead link moved from Item marks to a feature of its own: on only
    -- if it was in effect.
    if inventory then
        MovePartToFeature(inventory, "marks", "wowhead", "wowhead", {})
    end
end

-- Brings character data saved by earlier versions up to date.
local function MigrateCharacter(characterDb)
    for _, move in ipairs(MOVED_FEATURES) do
        MoveFeatureEntry(characterDb, move)
    end

    -- Item notes moved from Item locking to Item marks. Item locking showed a
    -- note only while its item was locked: those notes follow.
    local inventory = characterDb.inventory
    local locking = type(inventory) == "table" and inventory.locking
    if type(locking) == "table" and type(locking.notes) == "table" then
        local locks = type(locking.locks) == "table" and locking.locks or {}
        local notes = GetOrCreateTable(GetOrCreateTable(inventory, "marks"), "notes")
        for guid, note in pairs(locking.notes) do
            if locks[guid] and notes[guid] == nil then
                notes[guid] = note
            end
        end
        locking.notes = nil
    end

    -- Tracking nearby quests moved from Quest helpers to a feature of its own:
    -- the quests the player pinned follow.
    local quests = characterDb.quests
    local helpers = type(quests) == "table" and quests.helpers
    if type(helpers) == "table" and helpers.pins ~= nil then
        local tracking = GetOrCreateTable(quests, "tracking")
        if tracking.pins == nil then
            tracking.pins = helpers.pins
        end
        helpers.pins = nil
    end
end

function Database:Initialize()
    ForeverEnhancedDB = type(ForeverEnhancedDB) == "table" and ForeverEnhancedDB or {}
    ForeverEnhancedCharacterDB = type(ForeverEnhancedCharacterDB) == "table" and ForeverEnhancedCharacterDB or {}
    MigrateCharacter(ForeverEnhancedCharacterDB)

    -- Before the modules: their locale defaults come in this language.
    ApplyDefault(ForeverEnhancedDB, "language", Database.LANGUAGE_DEFAULT, LANGUAGE_ENTRY)
    ns:SetLanguage(ForeverEnhancedDB.language)

    local savedModules = GetOrCreateTable(ForeverEnhancedDB, "modules")
    local knownModules = {}
    Migrate(savedModules, GetOrCreateTable(ForeverEnhancedDB, "stores"))

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
