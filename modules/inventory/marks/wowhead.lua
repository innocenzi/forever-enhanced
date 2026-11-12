-- Wowhead link (the "wowhead" part): "Wowhead link" in the item menu shows the
-- item's Wowhead (Forever) page address, selected, ready to copy: the client
-- can't open web pages or write to the clipboard. The page is in the addon's
-- language.
--
-- Blizzard's GENERIC_INPUT_BOX can't be pre-filled, so we register our own
-- dialog. Its edit box puts the address back if the player types in it.

local _, ns = ...

local Marks = ns:GetFeature("inventory", "marks")

local Wowhead = {}
Marks.Wowhead = Wowhead

local DIALOG = "FOREVER_ENHANCED_WOWHEAD_LINK"
local MENU_ORDER = 30

local function ShowURL(editBox, data)
    editBox:SetText(data.url)
    editBox:HighlightText()
end

-- The text is set when shown: strings are in the player's language only after
-- the addon has loaded.
StaticPopupDialogs[DIALOG] = {
    button1 = CLOSE,
    hasEditBox = 1,
    editBoxWidth = 320,
    OnShow = function(dialog, data)
        ShowURL(dialog:GetEditBox(), data)
    end,
    EditBoxOnTextChanged = function(editBox, data)
        if editBox:GetText() ~= data.url then
            ShowURL(editBox, data)
        end
    end,
    EditBoxOnEnterPressed = function(editBox)
        editBox:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
    hideOnEscape = 1,
    timeout = 0,
    whileDead = 1,
}

local function ShowLink(itemLocation)
    local url = ns.L["inventory.marks.wowheadURL"]:format(C_Item.GetItemID(itemLocation))
    StaticPopupDialogs[DIALOG].text = ns.L["inventory.marks.wowheadPrompt"]
    StaticPopup_Show(DIALOG, C_Item.GetItemLink(itemLocation), nil, { url = url })
end

ns:AddItemButtonHandler(Marks, {
    part = "wowhead",
    menuOrder = MENU_ORDER,
    AddMenuEntries = function(rootDescription, itemLocation, guid)
        if guid then
            rootDescription:CreateButton(ns.L["inventory.marks.wowheadLink"], function()
                ShowLink(itemLocation)
            end)
        end
    end,
})

-- The click shield takes Alt clicks only while some feature adds menu entries.
function Wowhead:Enable()
    ns:RefreshItemButtons()
end

function Wowhead:Disable()
    StaticPopup_Hide(DIALOG)
    ns:RefreshItemButtons()
end
