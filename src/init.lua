local ForeverEnhanced = _G.ForeverEnhanced

local SLASH_COMMAND = "/fe"

local function GetAddonVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return getMetadata and getMetadata(ForeverEnhanced.addonName, "Version") or "?"
end

local function InitializeModules()
    for moduleKey, module in ForeverEnhanced:IterateModules() do
        if module.Initialize then
            local ok, err = pcall(module.Initialize, module)
            if not ok then
                ForeverEnhanced:PrintMessage(moduleKey .. ": " .. tostring(err), "error")
            end
        end
        if module.SetEnabled then
            module:SetEnabled(ForeverEnhanced:IsModuleEnabled(moduleKey))
        end
    end
end

local function PrintHelp()
    ForeverEnhanced:PrintMessage(ForeverEnhanced:T("core.help.header"))
    ForeverEnhanced:PrintMessage(ForeverEnhanced:T("core.help.reset", { command = SLASH_COMMAND .. " reset" }))
end

SLASH_FOREVERENHANCED1 = SLASH_COMMAND
SLASH_FOREVERENHANCED2 = "/foreverenhanced"
SlashCmdList.FOREVERENHANCED = function(input)
    local command = string.lower(strtrim(input or ""))

    if command == "" or command == "help" then
        PrintHelp()
    elseif command == "reset" then
        ForeverEnhanced:ResetSettings()
        ForeverEnhanced:PrintMessage(ForeverEnhanced:T("core.reset"))
    else
        ForeverEnhanced:PrintMessage(ForeverEnhanced:T("core.unknownCommand", { command = command }), "error")
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedAddonName)
    if event ~= "ADDON_LOADED" or loadedAddonName ~= ForeverEnhanced.addonName then
        return
    end

    self:UnregisterEvent("ADDON_LOADED")

    ForeverEnhanced:GetSettings()
    ForeverEnhanced:GetCharacterSettings()
    ForeverEnhanced:RefreshLocaleState(true)
    InitializeModules()

    ForeverEnhanced:PrintMessage(ForeverEnhanced:T("core.loaded", {
        version = GetAddonVersion(),
        command = SLASH_COMMAND,
    }))
end)
