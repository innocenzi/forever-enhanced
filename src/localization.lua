local ForeverEnhanced = _G.ForeverEnhanced

local FALLBACK_LOCALE = "enUS"

local STRINGS = {
    enUS = {
        ["core.loaded"] = "Loaded version {version}. Type {command} for options.",
        ["core.reset"] = "Settings have been reset.",
        ["core.unknownCommand"] = "Unknown command: {command}",
        ["core.help.header"] = "Available commands:",
        ["core.help.reset"] = "{command} — reset all settings",
    },
    frFR = {
        ["core.loaded"] = "Version {version} chargée. Tapez {command} pour les options.",
        ["core.reset"] = "Les paramètres ont été réinitialisés.",
        ["core.unknownCommand"] = "Commande inconnue : {command}",
        ["core.help.header"] = "Commandes disponibles :",
        ["core.help.reset"] = "{command} — réinitialiser tous les paramètres",
    },
}

local localeState = {
    effective = nil,
    activeStrings = nil,
    fallbackStrings = STRINGS[FALLBACK_LOCALE],
}

local function GetAutoLocaleKey()
    local locale = type(GetLocale) == "function" and GetLocale() or FALLBACK_LOCALE
    return STRINGS[locale] and locale or FALLBACK_LOCALE
end

local function NormalizeLocaleSetting(locale)
    if locale == "auto" or STRINGS[locale] then
        return locale
    end
    return "auto"
end

function ForeverEnhanced:RefreshLocaleState(force)
    if localeState.effective and not force then
        return localeState.effective
    end

    local stored = NormalizeLocaleSetting(self:GetSettings().locale)
    local effective = stored ~= "auto" and stored or GetAutoLocaleKey()

    localeState.effective = effective
    localeState.activeStrings = STRINGS[effective] or localeState.fallbackStrings
    return effective
end

function ForeverEnhanced:GetLocaleKey()
    return self:RefreshLocaleState()
end

function ForeverEnhanced:SetLocaleKey(locale)
    local settings = self:GetSettings()
    settings.locale = NormalizeLocaleSetting(locale)
    self:RefreshLocaleState(true)
    return settings.locale
end

local function FormatLocalizedText(text, vars)
    if type(vars) ~= "table" then
        return text
    end

    return (string.gsub(text, "{([%w_]+)}", function(name)
        local value = vars[name]
        if value == nil then
            return "{" .. name .. "}"
        end
        return tostring(value)
    end))
end

function ForeverEnhanced:T(key, vars)
    self:RefreshLocaleState()

    local text = localeState.activeStrings[key] or localeState.fallbackStrings[key] or key
    return FormatLocalizedText(text, vars)
end

-- Lets modules register their own strings: ForeverEnhanced:RegisterStrings({ enUS = {...}, frFR = {...} })
function ForeverEnhanced:RegisterStrings(stringsByLocale)
    for locale, strings in pairs(stringsByLocale or {}) do
        STRINGS[locale] = STRINGS[locale] or {}
        for key, value in pairs(strings) do
            STRINGS[locale][key] = value
        end
    end
end
