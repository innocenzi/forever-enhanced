-- Shipped setting presets (ns.PRESETS), picked in the root settings page.
--
-- Each feature declares its values per preset in RegisterFeature:
--   presets = { minimal = { enabled = true, announce = false }, ... }
-- Applying a preset copies those values over the current settings; whatever a
-- preset doesn't list stays as it is. A feature it turns on also turns its
-- module on. Values go through the registered settings, so the panel's
-- controls and the features' callbacks follow as if the player clicked.

local _, ns = ...

-- In dropdown order.
ns.PRESETS = { "minimal", "enhanced" }

local function Set(tbl, key, path, value)
    if tbl[key] ~= value then
        ns.SettingsPanel:GetSetting(path):SetValue(value)
    end
end

-- Settings first, then the toggle: a feature turned on reads its final values
-- in OnEnable instead of going through OnSettingChanged for each.
local function ApplyToFeature(feature, values)
    for _, entry in ipairs(feature.settings) do
        local value = values[entry.key]
        if value ~= nil then
            Set(feature.db, entry.key, feature:GetLocaleKey(entry.key), value)
        end
    end
    if values.enabled ~= nil then
        Set(feature.db, "enabled", feature:GetLocaleKey("enabled"), values.enabled)
    end
end

function ns:ApplyPreset(presetId)
    assert(tContains(self.PRESETS, presetId), "unknown preset: " .. tostring(presetId))
    for _, module in self:EnumerateModules() do
        local enablesModule = false
        for _, feature in ipairs(module.sortedFeatures) do
            local values = feature.presets[presetId]
            if values then
                ApplyToFeature(feature, values)
                enablesModule = enablesModule or values.enabled == true
            end
        end
        if enablesModule then
            Set(module.db, "enabled", module.id .. ".enabled", true)
        end
    end
end
