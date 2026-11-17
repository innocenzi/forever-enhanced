-- The Duplicate button, left of Blizzard's New button at the bottom of
-- MacroFrame (load-on-demand with Blizzard_MacroUI).
--
-- It copies the selected macro into the same tab and selects the copy, the way
-- MacroPopupFrameMixin:OkayButton_OnClick does for a new macro. The icon comes
-- from C_Macro.GetSelectedMacroIcon (what the player picked, as the icon
-- picker reads it), not GetMacroInfo's shown icon, so a question mark icon
-- stays dynamic on the copy.
--
-- It's enabled like New (room left in the tab, not in click binding mode),
-- with a macro selected, the icon picker closed (it disables New directly) and
-- out of combat (macros can't be created then).

local _, ns = ...

local L = ns.L
local Macros = ns:GetFeature("interface", "macros")

local Button = {}
Macros.Button = Button

local MACRO_ADDON = "Blizzard_MacroUI"
local BUTTON_WIDTH, BUTTON_HEIGHT = 80, 22

local button

local function IsCharacterTab(frame)
    return frame.macroBase > 0
end

local function GetNumTabMacros(frame)
    local numAccountMacros, numCharacterMacros = GetNumMacros()
    return IsCharacterTab(frame) and numCharacterMacros or numAccountMacros
end

local function CanDuplicate()
    local frame = MacroFrame
    -- Its tab (macroBase, macroMax) is set on show.
    return frame:IsShown()
        and frame:GetSelectedIndex() ~= nil
        and GetNumTabMacros(frame) < frame.macroMax
        and not MacroPopupFrame:IsShown()
        and not InClickBindingMode()
        and not InCombatLockdown()
end

local function UpdateButton()
    if button and Macros:IsActive() then
        button:SetEnabled(CanDuplicate())
    end
end

local listener = ns:CreateEventListener({
    PLAYER_REGEN_DISABLED = function()
        -- The lockdown starts right after this event.
        if button then
            button:Disable()
        end
    end,
    PLAYER_REGEN_ENABLED = UpdateButton,
})

local function Duplicate()
    if not CanDuplicate() then
        return
    end
    local frame = MacroFrame
    -- Like New: unsaved text first, so the copy has it.
    frame:SaveMacro()
    local actualIndex = frame:GetMacroDataIndex(frame:GetSelectedIndex())
    local name, _, body = GetMacroInfo(actualIndex)
    local icon = C_Macro.GetSelectedMacroIcon(actualIndex)
    local index = CreateMacro(name, icon, body, IsCharacterTab(frame)) - frame.macroBase
    local scrollToSelected = true
    frame:SelectMacro(index, scrollToSelected)
    frame:Update()
    MacroFrameText:ClearFocus()
end

local function Install()
    button = CreateFrame("Button", nil, MacroFrame, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetPoint("RIGHT", MacroNewButton, "LEFT", -2, 0)
    button:SetText(L["interface.macros.duplicate"])
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        Duplicate()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["interface.macros.duplicate.tooltip"])
        if InClickBindingMode() then
            GameTooltip_AddErrorLine(GameTooltip, CLICK_BINDING_BUTTON_DISABLED)
        elseif InCombatLockdown() then
            GameTooltip_AddErrorLine(GameTooltip, ERR_NOT_IN_COMBAT)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetShown(Macros:IsActive())

    -- Called after every selection, tab change and macro change.
    ns:HookSecureFunc(MacroFrame, "UpdateButtons", UpdateButton)
    -- The icon picker enables and disables Blizzard's buttons itself.
    MacroPopupFrame:HookScript("OnShow", UpdateButton)
    MacroPopupFrame:HookScript("OnHide", UpdateButton)
    UpdateButton()
end

if C_AddOns.IsAddOnLoaded(MACRO_ADDON) then
    Install()
else
    ns:CreateEventListener({
        ADDON_LOADED = function(self, addonName)
            if addonName == MACRO_ADDON then
                self:Stop()
                Install()
            end
        end,
    }):Start()
end

function Button:Enable()
    listener:Start()
    if button then
        button:Show()
        UpdateButton()
    end
end

function Button:Disable()
    listener:Stop()
    if button then
        button:Hide()
    end
end
