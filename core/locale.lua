-- Localization. Each slice registers its own strings for enUS and frFR.
-- enUS is the fallback; a missing key renders as the key itself.

local _, ns = ...

local clientLocale = GetLocale()

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})
ns.L = L

function ns:RegisterLocale(locale, strings)
    local isFallback = locale == "enUS"
    if not isFallback and locale ~= clientLocale then
        return
    end

    for key, value in pairs(strings) do
        -- The client locale wins over the fallback, whatever the load order.
        if not isFallback or rawget(L, key) == nil then
            rawset(L, key, value)
        end
    end
end
