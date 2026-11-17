-- search: the search box in the macro icon picker (MacroPopupFrame, load-on-demand
-- with Blizzard_MacroUI), beside the icon type dropdown; it hides with the
-- dropdown while the player drags something onto the picker.
--
-- While searching, Blizzard's grid shows our list of matching icons (through
-- its own SetSelectionsDataProvider, as MacroPopupFrameMixin:Update does), each
-- icon once. Clicking one runs Blizzard's selection callback, and OK saves the
-- selected icon button's texture as always. Blizzard's code that selects an
-- icon by its index in the full list (the type dropdown, dropping a spell or
-- an item) is followed by ours: the type dropdown searches again, a drop ends
-- the search so the dropped icon shows selected in the full list.

local _, ns = ...

local Macros = ns:GetFeature("interface", "macros")

local Picker = {}
Macros.Picker = Picker

local BOX_WIDTH = 120
local BOX_HEIGHT = 20

local box
-- The lowercased words searched; none while not searching.
local terms = {}
-- The icons Blizzard's grid shows while searching.
local matches = {}
-- Whether the grid shows our matches (until Blizzard's next OnShow gives it the full list).
local filtered = false

local function IsActive()
    return Macros:IsPartActive("search")
end

local function GetMatch(index)
    return matches[index]
end

local function GetNumMatches()
    return #matches
end

local function GetSelectedIcon(popup)
    return popup.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
end

local function ShowMatches(popup)
    filtered = true
    Macros.Names:Search(terms)
    wipe(matches)
    local seen = {}
    for index = 1, popup:GetNumIcons() do
        local icon = popup:GetIconByIndex(index)
        if icon and not seen[icon] then
            seen[icon] = true
            if Macros.Names:Matches(icon) then
                table.insert(matches, icon)
            end
        end
    end
    local selector = popup.IconSelector
    selector:SetSelectionsDataProvider(GetMatch, GetNumMatches)
    selector:SetSelectedIndex(tIndexOf(matches, GetSelectedIcon(popup)))
    selector.ScrollBox:ScrollToBegin()
end

-- Blizzard's full list back, the selected icon in view.
local function ShowAll(popup)
    filtered = false
    local selector = popup.IconSelector
    selector:SetSelectionsDataProvider(
        GenerateClosure(popup.GetIconByIndex, popup),
        GenerateClosure(popup.GetNumIcons, popup)
    )
    selector:SetSelectedIndex(popup:GetIndexOfIcon(GetSelectedIcon(popup)))
    selector:ScrollToSelectedIndex()
end

-- Shows what the search asks for: our matches, or the full list.
local function Refresh()
    local popup = MacroPopupFrame
    if not popup:IsShown() then
        filtered = false
    elseif IsActive() and #terms > 0 then
        ShowMatches(popup)
    elseif filtered then
        ShowAll(popup)
    end
end

local function SetText(text)
    terms = {}
    for term in text:lower():gmatch("%S+") do
        table.insert(terms, term)
    end
    Refresh()
end

local function ClearBox()
    box:SetText("")
    box:ClearFocus()
end

-- Blizzard gave the grid the full list, or selected an icon by its index in it.
local function OnFullListSelection(popup)
    if filtered then
        ShowMatches(popup)
    end
end

local function Install()
    local popup = MacroPopupFrame
    local dropdown = popup.BorderBox.IconTypeDropdown
    box = CreateFrame("EditBox", nil, dropdown, "SearchBoxTemplate")
    box:SetSize(BOX_WIDTH, BOX_HEIGHT)
    box:SetPoint("RIGHT", dropdown, "LEFT", -10, 0)
    box:SetShown(IsActive())
    box:HookScript("OnTextChanged", function(editBox)
        SetText(editBox:GetText())
    end)

    -- Each visit starts with the full list (Blizzard's OnShow sets it).
    popup:HookScript("OnHide", ClearBox)
    -- MacroPopupFrameMixin:Update and the type dropdown (through
    -- ReevaluateSelectedIcon) give the grid the full list.
    ns:HookSecureFunc(popup, "Update", OnFullListSelection)
    ns:HookSecureFunc(popup, "ReevaluateSelectedIcon", OnFullListSelection)
    ns:HookSecureFunc(popup, "SetIconFromMouse", function()
        if filtered then
            ClearBox()
        end
    end)
end

Macros:OnMacroUILoaded(Install)

function Picker:Enable()
    if box then
        box:Show()
    end
end

function Picker:Disable()
    if box then
        -- The part is inactive by now: the full list comes back.
        ClearBox()
        box:Hide()
    end
end
