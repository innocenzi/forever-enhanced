-- layout: MacroFrame's buttons grouped by what they act on.
--
--   [icon] Name
--          [Change Name/Icon] [Delete]      the selected macro
--   ...text...
--   [New][Duplicate]               [Save]   new macros | the text
--
-- Exit hides: the frame's close button does the same. Cancel hides too: it
-- only ends typing (the text is still saved on the next selection, tab change
-- or close), which clicking elsewhere does as well. Only Blizzard's own
-- buttons move (none is protected); their XML anchors are saved on install
-- and put back on disable. Delete hides along with Change Name/Icon, which
-- Blizzard hides while the tab has no macro (HideDetails).

local _, ns = ...

local Macros = ns:GetFeature("interface", "macros")

local Layout = {}
Macros.Layout = Layout

local SPACING = 2

local installed = false
-- Per moved button: its Blizzard anchors, { point, relativeTo, relativePoint, x, y } each.
local savedPoints = {}

local function IsActive()
    return Macros:IsPartActive("layout")
end

local function MovedButtons()
    return { MacroDeleteButton, MacroNewButton, MacroSaveButton }
end

local function SavePoints()
    for _, button in ipairs(MovedButtons()) do
        local points = {}
        for index = 1, button:GetNumPoints() do
            table.insert(points, { button:GetPoint(index) })
        end
        savedPoints[button] = points
    end
end

local function RestorePoints()
    for _, button in ipairs(MovedButtons()) do
        button:ClearAllPoints()
        for _, point in ipairs(savedPoints[button]) do
            button:SetPoint(unpack(point, 1, 5))
        end
    end
end

local function UpdateDeleteButton()
    if IsActive() then
        MacroDeleteButton:SetShown(MacroEditButton:IsShown())
    end
end

local function Apply()
    MacroDeleteButton:ClearAllPoints()
    MacroDeleteButton:SetPoint("LEFT", MacroEditButton, "RIGHT", SPACING, 0)
    MacroNewButton:ClearAllPoints()
    MacroNewButton:SetPoint("BOTTOMLEFT", MacroFrame, "BOTTOMLEFT", 4, 4)
    MacroSaveButton:ClearAllPoints()
    MacroSaveButton:SetPoint("BOTTOMRIGHT", MacroFrame, "BOTTOMRIGHT", -5, 4)
    MacroCancelButton:Hide()
    MacroExitButton:Hide()
    UpdateDeleteButton()
    Macros.Duplicate:UpdateAnchor()
end

local function Restore()
    RestorePoints()
    MacroCancelButton:Show()
    MacroExitButton:Show()
    MacroDeleteButton:Show()
    Macros.Duplicate:UpdateAnchor()
end

local function Install()
    installed = true
    SavePoints()
    -- After HideDetails and ShowDetails, which every selection runs.
    ns:HookSecureFunc(MacroFrame, "UpdateButtons", UpdateDeleteButton)
    if IsActive() then
        Apply()
    end
end

Macros:OnMacroUILoaded(Install)

function Layout:Enable()
    if installed then
        Apply()
    end
end

function Layout:Disable()
    if installed then
        Restore()
    end
end
