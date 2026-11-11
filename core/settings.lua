-- Builds the Options > AddOns panel from the registered modules and features.
--
-- Root page: language, preset picker (core/presets.lua), one toggle per module.
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
-- is greyed out unless it has that value (and that entry is editable).

local _, ns = ...

local L = ns.L

local SettingsPanel = {}
ns.SettingsPanel = SettingsPanel

local VARIABLE_PREFIX = "ForeverEnhanced."
-- Our rows, defined in settings.xml: Blizzard's own under our names, so their
-- pages never reuse (and run tainted in) frames our rows used.
local TEMPLATES = {
    header = "ForeverEnhancedSettingsSectionHeaderTemplate",
    checkbox = "ForeverEnhancedSettingsCheckboxControlTemplate",
    dropdown = "ForeverEnhancedSettingsDropdownControlTemplate",
    slider = "ForeverEnhancedSettingsSliderControlTemplate",
    text = "ForeverEnhancedSettingsTextControlTemplate",
}
local TEXT_MAX_LETTERS = 200

local function OptionalText(key)
    return rawget(L, key)
end

-- Adds a control row for `setting` with our template of that kind. `options`:
-- a function returning a dropdown's options, or a slider's options.
local function AddControl(category, kind, setting, options, tooltip)
    local initializer = Settings.CreateControlInitializer(TEMPLATES[kind], setting, options, tooltip)
    Settings.RegisterInitializer(category, initializer)
    return initializer
end

local function AddCheckbox(category, setting, tooltip)
    return AddControl(category, "checkbox", setting, nil, tooltip)
end

local function AddSectionHeader(category, name, tooltip)
    local initializer = Settings.CreateElementInitializer(TEMPLATES.header, { name = name, tooltip = tooltip })
    Settings.RegisterInitializer(category, initializer)
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
            return AddCheckbox(category, setting, tooltip)
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
            return AddControl(category, "dropdown", setting, GetOptions, tooltip)
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
            return AddControl(category, "slider", setting, options, tooltip)
        end,
    },
    -- { key, type = "text", default = string } (a blank text resets to the default)
    text = {
        varType = Settings.VarType.String,
        create = function(category, setting, tooltip)
            return AddControl(category, "text", setting, nil, tooltip)
        end,
    },
}

local rootCategory
-- Registered settings by path ("<module>.enabled", "<module>.<feature>.<key>"):
-- presets change values through them, so controls and callbacks follow.
local settingsByPath = {}

local function RegisterSetting(category, path, key, tbl, varType, label, default)
    local setting = Settings.RegisterAddOnSetting(category, VARIABLE_PREFIX .. path, key, tbl, varType, label, default)
    settingsByPath[path] = setting
    return setting
end

function SettingsPanel:GetSetting(path)
    return assert(settingsByPath[path], "unknown setting: " .. path)
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

local function FindEntry(feature, key)
    for _, entry in ipairs(feature.settings) do
        if entry.key == key then
            return entry
        end
    end
end

-- Whether the entry's requirement holds, and its required entry's, up the chain.
local function RequirementMet(feature, entry)
    local key, value = GetRequirement(entry)
    return key == nil or (feature.db[key] == value and RequirementMet(feature, FindEntry(feature, key)))
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

-- Nests `initializer` under `parent` (indented, re-evaluated when the parent's
-- setting changes) without SetParentInitializer: the settings search reads its
-- `parentInitializer` field outside the rows' secure calls, so one written by
-- us taints the search and every frame it builds, e.g. the push-to-talk button
-- on the Keybindings page, which Blizzard keeps for the session (its Discord
-- check is then blocked). Rows read the parent through this getter.
local function SetParent(initializer, parent)
    initializer.GetParentInitializer = function()
        return parent
    end
end

local function AddSchemaEntry(category, feature, entry, parentInitializer)
    local control = assert(controls[entry.type], "unknown setting type: " .. tostring(entry.type))
    local labelKey = feature:GetLocaleKey(entry.key)
    local setting =
        RegisterSetting(category, labelKey, entry.key, feature.db, control.varType, L[labelKey], entry.default)

    local initializer = control.create(category, setting, OptionalText(labelKey .. ".tooltip"), entry, labelKey)
    SetParent(initializer, parentInitializer)
    -- Predicates aren't inherited from grandparents: check the whole chain here.
    initializer:AddModifyPredicate(function()
        return feature.module.db.enabled and feature.db.enabled and RequirementMet(feature, entry)
    end)

    setting:SetValueChangedCallback(function(_, value)
        if feature:IsActive() then
            feature:OnSettingChanged(entry.key, value)
        end
    end)
    return initializer
end

local function AddFeature(category, feature)
    local module = feature.module
    local prefix = feature:GetLocaleKey()
    local description = L[prefix .. ".description"]

    AddSectionHeader(category, L[prefix .. ".title"], description)

    local enabledSetting = RegisterSetting(
        category,
        prefix .. ".enabled",
        "enabled",
        feature.db,
        Settings.VarType.Boolean,
        L["core.enable"],
        feature.enabledByDefault
    )
    local enabledInitializer = AddCheckbox(category, enabledSetting, description)
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
    AddCheckbox(rootCategory, moduleSetting, L[module.id .. ".description"])
    moduleSetting:SetValueChangedCallback(function()
        ns:RefreshModule(module)
    end)

    local category = Settings.RegisterVerticalLayoutSubcategory(rootCategory, title)
    for _, feature in ipairs(module.sortedFeatures) do
        AddFeature(category, feature)
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
    AddControl(rootCategory, "dropdown", setting, GetOptions, L["core.language.tooltip"])
    setting:SetValueChangedCallback(function()
        StaticPopup_ShowCustomGenericConfirmation({
            text = L["core.language.reloadConfirm"],
            callback = ReloadUI,
        })
    end)
end

-- The preset picker: picking a preset asks for confirmation, then applies it.
-- Nothing is saved: the dropdown always reads "none", so it keeps showing its
-- placeholder.
local PRESET_NONE = "none"

local function ConfirmPreset(presetId)
    if presetId == PRESET_NONE then
        return
    end
    StaticPopup_ShowCustomGenericConfirmation({
        text = L["core.presets.confirm"]:format(L["core.presets." .. presetId]),
        callback = function()
            ns:ApplyPreset(presetId)
        end,
    })
end

local function AddPresets()
    local setting = Settings.RegisterProxySetting(
        rootCategory,
        VARIABLE_PREFIX .. "preset",
        Settings.VarType.String,
        L["core.presets"],
        PRESET_NONE,
        function()
            return PRESET_NONE
        end,
        ConfirmPreset
    )
    local function GetOptions()
        local container = Settings.CreateControlTextContainer()
        container:Add(PRESET_NONE, L["core.presets.none"])
        for _, presetId in ipairs(ns.PRESETS) do
            container:Add(presetId, L["core.presets." .. presetId], L["core.presets." .. presetId .. ".tooltip"])
        end
        return container:GetData()
    end
    AddControl(rootCategory, "dropdown", setting, GetOptions, L["core.presets.tooltip"])
end

function SettingsPanel:Build()
    rootCategory = Settings.RegisterVerticalLayoutCategory(ns.title)

    AddSectionHeader(rootCategory, L["core.general"])
    AddLanguage()
    AddPresets()

    AddSectionHeader(rootCategory, L["core.modules"], L["core.modules.tooltip"])

    for _, module in ns:EnumerateModules() do
        AddModule(module)
    end

    Settings.RegisterAddOnCategory(rootCategory)
end
