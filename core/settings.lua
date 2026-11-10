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
--   <module>.<feature>.<key>.default for an entry without a `default`
--
-- An entry with `requires = { key = value }` sits under that earlier entry and
-- is greyed out unless it has that value.

local _, ns = ...

local L = ns.L

local SettingsPanel = {}
ns.SettingsPanel = SettingsPanel

local VARIABLE_PREFIX = "ForeverEnhanced."
-- Our text row, defined in settings.xml.
local TEXT_TEMPLATE = "ForeverEnhancedSettingsTextControlTemplate"
local TEXT_MAX_LETTERS = 200

local function OptionalText(key)
    return rawget(L, key)
end

-- Text row: Blizzard's settings have no edit box control, so settings.xml
-- defines a row built like theirs (SettingsControlMixin) with this mixin on top.
local TextControlMixin = {}
SettingsPanel.TextControlMixin = TextControlMixin

function TextControlMixin:OnLoad()
    SettingsControlMixin.OnLoad(self)

    local editBox = CreateFrame("EditBox", nil, self, "InputBoxTemplate")
    editBox:SetHeight(22)
    editBox:SetPoint("LEFT", self, "CENTER", -75, 0)
    editBox:SetPoint("RIGHT", self, "RIGHT", -20, 0)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(TEXT_MAX_LETTERS)
    editBox:SetScript("OnEnterPressed", function(box)
        box:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(box)
        box:SetText(self:GetSetting():GetValue())
        box:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost", function(box)
        box:HighlightText(0, 0)
        self:Commit()
    end)
    editBox:SetScript("OnEnter", function()
        self.Tooltip:OnEnter()
    end)
    editBox:SetScript("OnLeave", function()
        self.Tooltip:OnLeave()
    end)
    self.EditBox = editBox
end

function TextControlMixin:Init(initializer)
    SettingsControlMixin.Init(self, initializer)
    self:ShowValue(self:GetSetting():GetValue())
    self:EvaluateState()
end

function TextControlMixin:Release()
    -- Commits a pending edit while the row still knows its setting.
    self.EditBox:ClearFocus()
    SettingsControlMixin.Release(self)
end

function TextControlMixin:ShowValue(value)
    self.EditBox:SetText(value)
    self.EditBox:SetCursorPosition(0)
end

-- A blank text restores the default.
function TextControlMixin:Commit()
    if not self.data then
        return
    end
    local setting = self:GetSetting()
    local text = self.EditBox:GetText()
    if not text:find("%S") then
        text = setting:GetDefaultValue()
    end
    if text ~= setting:GetValue() then
        setting:SetValue(text)
    end
    self:ShowValue(setting:GetValue())
end

-- The setting changed elsewhere (e.g. the Defaults button).
function TextControlMixin:SetValue(value)
    if not self.EditBox:HasFocus() then
        self:ShowValue(value)
    end
end

function TextControlMixin:EvaluateState()
    SettingsListElementMixin.EvaluateState(self)
    local enabled = self:IsEnabled()
    self.EditBox:SetEnabled(enabled)
    self:DisplayEnabled(enabled)
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
    -- { key, type = "text", default = string } (a blank text resets to the default)
    text = {
        varType = Settings.VarType.String,
        create = function(category, setting, tooltip)
            local initializer = Settings.CreateControlInitializer(TEXT_TEMPLATE, setting, nil, tooltip)
            Settings.RegisterInitializer(category, initializer)
            return initializer
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
    local labelKey = feature:GetLocaleKey(entry.key)
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
    local prefix = feature:GetLocaleKey()
    local description = L[prefix .. ".description"]

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L[prefix .. ".title"], description))

    local enabledSetting = RegisterSetting(
        category,
        prefix .. ".enabled",
        "enabled",
        feature.db,
        Settings.VarType.Boolean,
        L["core.enable"],
        feature.enabledByDefault
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

-- The addon's language: the client's ("auto") or one of ns.LANGUAGES, named in
-- their own language. Strings are taken when frames are built, so it applies
-- after a reload, which the player is offered right away.
local function AddLanguage()
    local setting = RegisterSetting(
        rootCategory,
        "language",
        "language",
        ForeverEnhancedDB,
        Settings.VarType.String,
        L["core.language"],
        ns.Database.LANGUAGE_DEFAULT
    )
    local function GetOptions()
        local container = Settings.CreateControlTextContainer()
        container:Add(ns.Database.LANGUAGE_DEFAULT, L["core.language.auto"])
        for _, locale in ipairs(ns.LANGUAGES) do
            container:Add(locale, ns:GetLanguageName(locale))
        end
        return container:GetData()
    end
    Settings.CreateDropdown(rootCategory, setting, GetOptions, L["core.language.tooltip"])
    setting:SetValueChangedCallback(function()
        StaticPopup_ShowCustomGenericConfirmation({
            text = L["core.language.reloadConfirm"],
            callback = ReloadUI,
        })
    end)
end

function SettingsPanel:Build()
    local layout
    rootCategory, layout = Settings.RegisterVerticalLayoutCategory(ns.title)

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["core.general"]))
    AddLanguage()

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["core.modules"], L["core.modules.tooltip"]))

    for _, module in ns:EnumerateModules() do
        AddModule(module)
    end

    Settings.RegisterAddOnCategory(rootCategory)
end
