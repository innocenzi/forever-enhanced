-- Builds the Options > AddOns panel from the registered modules and features.
--
-- Root page: one toggle per module.
-- Module page: per feature, a section header, an "Enable" toggle, then the
-- feature's schema entries as children of that toggle.
--
-- Labels come from locale keys by convention:
--   <module>.title, <module>.description
--   <module>.<feature>.title, <module>.<feature>.description
--   <module>.<feature>.<key>, <module>.<feature>.<key>.tooltip (optional)
--   <module>.<feature>.<key>.<option> for each dropdown option
--   <module>.<feature>.<key>.format for a slider's value label (optional)
--
-- An entry with `requires = { key = value }` sits under that earlier entry and
-- is greyed out unless it has that value.

local _, ns = ...

local L = ns.L

local SettingsPanel = {}
ns.SettingsPanel = SettingsPanel

local VARIABLE_PREFIX = "ForeverEnhanced."

local function OptionalText(key)
    return rawget(L, key)
end

-- Schema entry type -> setting type and control factory.
-- create(category, setting, tooltip, entry, labelKey) returns the initializer.
local controls = {
    -- { key, type = "toggle", default = boolean }
    toggle = {
        varType = Settings.VarType.Boolean,
        create = function(category, setting, tooltip)
            return Settings.CreateCheckbox(category, setting, tooltip)
        end,
    },
    -- { key, type = "dropdown", default = option, options = { option, ... } }
    dropdown = {
        varType = Settings.VarType.String,
        create = function(category, setting, tooltip, entry, labelKey)
            local function GetOptions()
                local container = Settings.CreateControlTextContainer()
                for _, option in ipairs(entry.options) do
                    container:Add(option, L[labelKey .. "." .. option])
                end
                return container:GetData()
            end
            return Settings.CreateDropdown(category, setting, GetOptions, tooltip)
        end,
    },
    -- { key, type = "slider", default = number, min, max, step } (whole numbers)
    -- The value label uses the optional <labelKey>.format string (e.g. "%d yd"),
    -- or the plain number.
    slider = {
        varType = Settings.VarType.Number,
        create = function(category, setting, tooltip, entry, labelKey)
            local options = Settings.CreateSliderOptions(entry.min, entry.max, entry.step)
            local format = OptionalText(labelKey .. ".format") or "%d"
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
                return format:format(value)
            end)
            return Settings.CreateSlider(category, setting, options, tooltip)
        end,
    },
}

local rootCategory

local function RegisterSetting(category, path, key, tbl, varType, label, default)
    return Settings.RegisterAddOnSetting(category, VARIABLE_PREFIX .. path, key, tbl, varType, label, default)
end

-- The `requires = { key = value }` pair of an entry, or nil.
local function GetRequirement(entry)
    if not entry.requires then
        return nil
    end
    local key, value = next(entry.requires)
    assert(next(entry.requires, key) == nil, "requires takes a single setting: " .. entry.key)
    return key, value
end

local function RequirementMet(entry, db)
    local key, value = GetRequirement(entry)
    return key == nil or db[key] == value
end

-- The initializer the entry hangs under: the feature toggle, or the entry it
-- requires (which must come earlier in the schema).
local function GetParentInitializer(entry, featureInitializer, entryInitializers)
    local requiredKey = GetRequirement(entry)
    if not requiredKey then
        return featureInitializer
    end
    return assert(entryInitializers[requiredKey], "required setting must come first: " .. requiredKey)
end

local function AddSchemaEntry(category, feature, entry, parentInitializer)
    local control = assert(controls[entry.type], "unknown setting type: " .. tostring(entry.type))
    local labelKey = feature.module.id .. "." .. feature.id .. "." .. entry.key
    local setting =
        RegisterSetting(category, labelKey, entry.key, feature.db, control.varType, L[labelKey], entry.default)

    local initializer = control.create(category, setting, OptionalText(labelKey .. ".tooltip"), entry, labelKey)
    -- Predicates aren't inherited from grandparents: check the whole chain here.
    initializer:SetParentInitializer(parentInitializer, function()
        return feature.module.db.enabled and feature.db.enabled and RequirementMet(entry, feature.db)
    end)

    setting:SetValueChangedCallback(function(_, value)
        if feature:IsActive() then
            feature:OnSettingChanged(entry.key, value)
        end
    end)
    return initializer
end

local function AddFeature(category, layout, feature)
    local module = feature.module
    local prefix = module.id .. "." .. feature.id
    local description = L[prefix .. ".description"]

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L[prefix .. ".title"], description))

    local enabledSetting = RegisterSetting(
        category,
        prefix .. ".enabled",
        "enabled",
        feature.db,
        Settings.VarType.Boolean,
        L["core.enable"],
        ns.Database.ENABLED_DEFAULT
    )
    local enabledInitializer = Settings.CreateCheckbox(category, enabledSetting, description)
    enabledInitializer:AddModifyPredicate(function()
        return module.db.enabled
    end)
    enabledSetting:SetValueChangedCallback(function()
        ns:RefreshFeature(feature)
    end)

    local entryInitializers = {}
    for _, entry in ipairs(feature.settings) do
        local parent = GetParentInitializer(entry, enabledInitializer, entryInitializers)
        entryInitializers[entry.key] = AddSchemaEntry(category, feature, entry, parent)
    end
end

local function AddModule(module)
    local title = L[module.id .. ".title"]

    local moduleSetting = RegisterSetting(
        rootCategory,
        module.id .. ".enabled",
        "enabled",
        module.db,
        Settings.VarType.Boolean,
        title,
        ns.Database.ENABLED_DEFAULT
    )
    Settings.CreateCheckbox(rootCategory, moduleSetting, L[module.id .. ".description"])
    moduleSetting:SetValueChangedCallback(function()
        ns:RefreshModule(module)
    end)

    local category, layout = Settings.RegisterVerticalLayoutSubcategory(rootCategory, title)
    for _, feature in ipairs(module.sortedFeatures) do
        AddFeature(category, layout, feature)
    end
end

function SettingsPanel:Build()
    local layout
    rootCategory, layout = Settings.RegisterVerticalLayoutCategory(ns.title)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["core.modules"], L["core.modules.tooltip"]))

    for _, module in ns:EnumerateModules() do
        AddModule(module)
    end

    Settings.RegisterAddOnCategory(rootCategory)
end
