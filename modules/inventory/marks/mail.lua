-- Mail mark (the "mail" part): marking an item for mail asks who it goes to,
-- pre-filled with the last recipient entered; the recipient shows in the
-- tooltip of every copy. Blank text or Cancel leaves the item unmarked.
--
-- Blizzard's GENERIC_INPUT_BOX can't be pre-filled, so we register our own
-- dialog. Turning the part off hides it, so it never marks while the part is off.
-- Its name box completes names like the mail window's (Blizzard's dialog code
-- sets up autoCompleteSource on its edit box when shown, as for Add Friend).

local _, ns = ...

local Marks = ns:GetFeature("inventory", "marks")

local Mail = {}
Marks.Mail = Mail

local DIALOG = "FOREVER_ENHANCED_MAIL_RECIPIENT"
-- Room for a name and its realm.
local MAX_LETTERS = 48

local function Save(editBox, data)
    local recipient = strtrim(editBox:GetText())
    if recipient ~= "" then
        Marks:MarkForMail(data.itemID, recipient)
    end
end

-- The text is set when shown: strings are in the player's language only after
-- the addon has loaded.
StaticPopupDialogs[DIALOG] = {
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    autoCompleteSource = C_AutoComplete.GetAutoCompleteResults,
    autoCompleteArgs = { AUTOCOMPLETE_LIST.MAIL.include, AUTOCOMPLETE_LIST.MAIL.exclude },
    OnShow = function(dialog, data)
        local editBox = dialog:GetEditBox()
        editBox:SetMaxLetters(MAX_LETTERS)
        editBox:SetText(data.recipient or "")
        editBox:HighlightText()
    end,
    OnAccept = function(dialog, data)
        Save(dialog:GetEditBox(), data)
    end,
    EditBoxOnEnterPressed = function(editBox, data)
        Save(editBox, data)
        editBox:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
    hideOnEscape = 1,
    timeout = 0,
    whileDead = 1,
}

-- Asks who the item at `itemLocation` goes to, then marks it for mail.
function Mail:AskRecipient(itemLocation)
    local itemID = C_Item.GetItemID(itemLocation)
    StaticPopupDialogs[DIALOG].text = ns.L["inventory.marks.mailPrompt"]
    StaticPopup_Show(
        DIALOG,
        C_Item.GetItemLink(itemLocation),
        nil,
        { itemID = itemID, recipient = Marks:GetLastRecipient() }
    )
end

function Mail:HideDialog()
    StaticPopup_Hide(DIALOG)
end

ns:AddItemTooltipHandler(Marks, function(tooltip, data)
    local recipient = Marks:GetRecipient(data.id)
    if recipient then
        GameTooltip_AddNormalLine(tooltip, ns.L["inventory.marks.mailRecipient"]:format(recipient))
    end
end, { part = "mail" })
