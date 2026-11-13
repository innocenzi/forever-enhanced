-- Localization. Each slice registers its own strings for enUS and frFR.
--
-- Every locale is kept; the language is chosen once the saved variables are
-- loaded (ns:SetLanguage, from Database:Initialize): the player's choice in the
-- options, or the client's ("auto"). enUS is the fallback; a missing key
-- renders as the key itself, and so does every key until the language is set.

local _, ns = ...

-- The supported locales, in the options' order, with their names in their own language.
-- Adding a language: append it here and its native name to LANGUAGE_NAMES, and add it
-- to LOCALES in tests/run.lua.
ns.LANGUAGES = { "enUS", "frFR" }
local LANGUAGE_NAMES = {
    enUS = "English",
    frFR = "Français",
}
local FALLBACK = "enUS"

local strings = {}
for _, locale in ipairs(ns.LANGUAGES) do
    strings[locale] = {}
end

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
ns.L = L

function ns:RegisterLocale(locale, localeStrings)
    local target = assert(strings[locale], "unsupported locale: " .. tostring(locale))
    for key, value in pairs(localeStrings) do
        target[key] = value
    end
end

-- Fills L (the table every file holds) with `language`, "auto" for the client's.
function ns:SetLanguage(language)
    if language == "auto" then
        language = GetLocale()
    end
    wipe(L)
    for key, value in pairs(strings[FALLBACK]) do
        rawset(L, key, value)
    end
    for key, value in pairs(strings[language] or {}) do
        rawset(L, key, value)
    end
end

function ns:GetLanguageName(locale)
    return LANGUAGE_NAMES[locale]
end

-- Whether `value` is the string for `key` in any locale.
function ns:IsLocaleString(key, value)
    if value == nil then
        return false
    end
    for _, localeStrings in pairs(strings) do
        if localeStrings[key] == value then
            return true
        end
    end
    return false
end
