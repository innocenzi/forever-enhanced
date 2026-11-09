local addonName = ...

local ForeverEnhanced = _G.ForeverEnhanced or {}
_G.ForeverEnhanced = ForeverEnhanced

ForeverEnhanced.addonName = addonName or ForeverEnhanced.addonName or "ForeverEnhanced"
ForeverEnhanced.displayName = "Forever Enhanced"
ForeverEnhanced.mediaPath = "Interface\\AddOns\\" .. ForeverEnhanced.addonName .. "\\media\\"
ForeverEnhanced.modules = ForeverEnhanced.modules or {}
ForeverEnhanced.moduleOrder = ForeverEnhanced.moduleOrder or {}

local DEFAULT_SETTINGS = {
    modules = {},
    locale = "auto",
    informationalChatMessagesEnabled = true,
    errorChatMessagesEnabled = true,
    showChatMessagePrefix = true,
}

local DEFAULT_CHARACTER_SETTINGS = {
    modules = {},
}

local function CopyDefaults(target, source)
    if type(target) ~= "table" then
        target = {}
    end
    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            target[key] = CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

ForeverEnhanced.CopyDefaults = CopyDefaults

-- Modules ---------------------------------------------------------------------

function ForeverEnhanced:CreateModule(key, displayName)
    local module = self.modules[key]
    if not module then
        module = {}
        self.modules[key] = module
        self.moduleOrder[#self.moduleOrder + 1] = key
    end
    module.key = key
    module.displayName = displayName or module.displayName or key
    module.addon = self
    return module
end

function ForeverEnhanced:GetModule(key)
    return self.modules[key]
end

function ForeverEnhanced:IterateModules()
    local index = 0
    return function()
        index = index + 1
        local key = self.moduleOrder[index]
        if key then
            return key, self.modules[key]
        end
    end
end

-- Settings --------------------------------------------------------------------

function ForeverEnhanced:GetSettings()
    ForeverEnhancedSettings = CopyDefaults(ForeverEnhancedSettings, DEFAULT_SETTINGS)
    return ForeverEnhancedSettings
end

function ForeverEnhanced:GetModuleSettings(moduleKey, defaults)
    local settings = self:GetSettings()
    settings.modules[moduleKey] = CopyDefaults(settings.modules[moduleKey], defaults)
    return settings.modules[moduleKey]
end

function ForeverEnhanced:GetCharacterSettings()
    ForeverEnhancedCharacterSettings = CopyDefaults(ForeverEnhancedCharacterSettings, DEFAULT_CHARACTER_SETTINGS)
    return ForeverEnhancedCharacterSettings
end

function ForeverEnhanced:GetCharacterModuleSettings(moduleKey, defaults)
    local settings = self:GetCharacterSettings()
    settings.modules[moduleKey] = CopyDefaults(settings.modules[moduleKey], defaults)
    return settings.modules[moduleKey]
end

function ForeverEnhanced:IsModuleEnabled(moduleKey)
    local module = self.modules[moduleKey]
    if module and module.IsEnabled then
        return module:IsEnabled()
    end

    return self:GetModuleSettings(moduleKey, { enabled = true }).enabled ~= false
end

function ForeverEnhanced:SetModuleEnabled(moduleKey, enabled)
    local settings = self:GetModuleSettings(moduleKey, { enabled = true })
    settings.enabled = not not enabled

    local module = self.modules[moduleKey]
    if module and module.SetEnabled then
        module:SetEnabled(settings.enabled)
    end
end

function ForeverEnhanced:ResetSettings()
    ForeverEnhancedSettings = nil
    ForeverEnhancedCharacterSettings = nil
    self:GetSettings()
    self:GetCharacterSettings()

    for moduleKey, module in self:IterateModules() do
        if module.ResetSettings then
            module:ResetSettings()
        end
        if module.SetEnabled then
            module:SetEnabled(self:IsModuleEnabled(moduleKey))
        end
    end

    if self.RefreshLocaleState then
        self:RefreshLocaleState(true)
    end

    return ForeverEnhancedSettings
end

-- Chat output -----------------------------------------------------------------

function ForeverEnhanced:PrintMessage(message, level)
    local settings = self:GetSettings()
    if level == "error" then
        if settings.errorChatMessagesEnabled == false then
            return
        end
    elseif settings.informationalChatMessagesEnabled == false then
        return
    end

    if not (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage) then
        return
    end

    if settings.showChatMessagePrefix ~= false then
        message = "|cff5fd3f0" .. self.displayName .. ":|r " .. message
    end

    DEFAULT_CHAT_FRAME:AddMessage(message)
end
