-- Wowhead link: "Wowhead link" in the item menu shows the item's Wowhead
-- (Forever) page address, selected, ready to copy: the client
-- can't open web pages or write to the clipboard. The page is in the addon's
-- language.
--
-- Blizzard's GENERIC_INPUT_BOX can't be pre-filled, so we register our own
-- dialog. Its edit box puts the address back if the player types in it.

local _, ns = ...

local Wowhead = ns:GetFeature("inventory", "wowhead")

local Link = {}
Wowhead.Link = Link

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

-- `guid`: the item the menu was opened on, ignored if it has left `itemLocation` since.
local function ShowLink(itemLocation, guid)
    if ns.Containers:GetItemGUID(itemLocation) ~= guid then
        return
    end
    local url = ns.L["inventory.wowhead.url"]:format(C_Item.GetItemID(itemLocation))
    StaticPopupDialogs[DIALOG].text = ns.L["inventory.wowhead.prompt"]
    StaticPopup_Show(DIALOG, C_Item.GetItemLink(itemLocation), nil, { url = url })
end

ns:AddItemButtonHandler(Wowhead, {
    menuOrder = MENU_ORDER,
    AddMenuEntries = function(rootDescription, itemLocation, guid)
        if guid then
            rootDescription:CreateButton(ns.L["inventory.wowhead.link"], function()
                ShowLink(itemLocation, guid)
            end)
        end
    end,
})

function Link:HideDialog()
    StaticPopup_Hide(DIALOG)
end
