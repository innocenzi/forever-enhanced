-- save: Blizzard's Save button (MacroSaveButton) disabled while the macro text
-- matches the selected macro's saved body, or while no macro is selected.
--
-- MacroFrame.textChanged can't tell: MacroFrameText's OnTextChanged sets it on
-- every change, SelectMacro's own SetText included. Comparing the text also
-- disables Save again when the player undoes their edit by hand.
--
-- Blizzard never enables or disables Save itself, so disabling the part just
-- enables it back.

local _, ns = ...

local Macros = ns:GetFeature("interface", "macros")

local Save = {}
Macros.Save = Save

local installed = false

local function IsActive()
    return Macros:IsPartActive("save")
end

local function HasUnsavedText()
    local frame = MacroFrame
    local index = frame:GetSelectedIndex()
    if not index then
        return false
    end
    local _, _, body = GetMacroInfo(frame:GetMacroDataIndex(index))
    return MacroFrameText:GetText() ~= (body or "")
end

local function UpdateButton()
    if installed and IsActive() then
        MacroSaveButton:SetEnabled(HasUnsavedText())
    end
end

local function Install()
    installed = true
    -- Typing, and SelectMacro's SetText.
    MacroFrameText:HookScript("OnTextChanged", UpdateButton)
    -- Called after every selection, tab change, save and macro change.
    ns:HookSecureFunc(MacroFrame, "UpdateButtons", UpdateButton)
    UpdateButton()
end

Macros:OnMacroUILoaded(Install)

function Save:Enable()
    UpdateButton()
end

function Save:Disable()
    if installed then
        MacroSaveButton:Enable()
    end
end
