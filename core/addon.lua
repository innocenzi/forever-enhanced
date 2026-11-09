-- Namespace, module/feature registry and feature lifecycle.
--
-- A module groups features (one settings subcategory per module).
-- A feature is a self-contained vertical slice. It is active only when the
-- addon is ready, its module is enabled and the feature itself is enabled.
-- Core calls feature:OnEnable() / feature:OnDisable() on every transition.

local addonName, ns = ...

_G.ForeverEnhanced = ns

ns.title = C_AddOns.GetAddOnMetadata(addonName, "Title")

local modules = {}
local sortedModules = {}

local function ByOrder(a, b)
    if a.order ~= b.order then
        return a.order < b.order
    end
    return a.id < b.id
end

local function NoOp() end

local FeatureMixin = {
    OnEnable = NoOp,
    OnDisable = NoOp,
    OnSettingChanged = NoOp,
}

function FeatureMixin:IsActive()
    return self.active
end

function FeatureMixin:GetSetting(key)
    return self.db[key]
end

-- Per-character saved table owned by this feature.
function FeatureMixin:GetCharacterStore()
    return ns.Database:GetCharacterStore(self)
end

function ns:RegisterModule(id, definition)
    assert(not modules[id], "module already registered: " .. id)

    local module = {
        id = id,
        order = definition and definition.order or math.huge,
        features = {},
        sortedFeatures = {},
    }
    modules[id] = module
    table.insert(sortedModules, module)
    table.sort(sortedModules, ByOrder)
    return module
end

-- `definition` becomes the feature object: { order, settings = { schema entries } }.
function ns:RegisterFeature(moduleId, id, definition)
    local module = assert(modules[moduleId], "unknown module: " .. moduleId)
    assert(not module.features[id], "feature already registered: " .. moduleId .. "." .. id)

    local feature = Mixin(definition, FeatureMixin)
    feature.id = id
    feature.module = module
    feature.order = feature.order or math.huge
    feature.settings = feature.settings or {}
    feature.active = false

    module.features[id] = feature
    table.insert(module.sortedFeatures, feature)
    table.sort(module.sortedFeatures, ByOrder)
    return feature
end

function ns:GetFeature(moduleId, id)
    return modules[moduleId].features[id]
end

function ns:EnumerateModules()
    return ipairs(sortedModules)
end

local function ShouldBeActive(feature)
    return ns.ready and feature.module.db.enabled and feature.db.enabled
end

function ns:RefreshFeature(feature)
    local active = ShouldBeActive(feature) == true
    if active == feature.active then
        return
    end

    feature.active = active
    if active then
        feature:OnEnable()
    else
        feature:OnDisable()
    end
end

function ns:RefreshModule(module)
    for _, feature in ipairs(module.sortedFeatures) do
        self:RefreshFeature(feature)
    end
end

function ns:RefreshAll()
    for _, module in ipairs(sortedModules) do
        self:RefreshModule(module)
    end
end

local bootListener = ns:CreateEventListener({
    ADDON_LOADED = function(listener, loadedName)
        if loadedName ~= addonName then
            return
        end
        listener:Unregister("ADDON_LOADED")
        ns.Database:Initialize()
        ns.SettingsPanel:Build()
    end,
    PLAYER_LOGIN = function(listener)
        listener:Unregister("PLAYER_LOGIN")
        ns.ready = true
        ns:RefreshAll()
    end,
})
bootListener:Start()
