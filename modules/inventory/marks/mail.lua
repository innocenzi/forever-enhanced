-- Mail mark (the "mail" part): marking an item for mail asks who it goes to,
-- pre-filled with the last recipient entered; the recipient shows in the
-- tooltip of every copy. Blank text or Cancel leaves the item unmarked.
-- With "mailTo" on, attaching marked items on the Send Mail tab fills in their
-- recipient, unless the player typed a name or the attachments go to
-- different players; removing them clears it.
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

-- The To box ("mailTo"), filled in like Blizzard fills in the subject
-- (SendMailFrame_Update): only while it's empty or still holds what we put
-- there. Its OnTextChanged then runs from our code, which is harmless:
-- autocomplete ignores text set from code, and SendMail isn't protected.

-- The name we last put in the To box ("" for none).
local filled = ""

-- The recipient every attachment marked for mail goes to, or nil.
local function GetAttachmentsRecipient()
    local recipient
    for index = 1, ATTACHMENTS_MAX_SEND do
        if HasSendMailItem(index) then
            local _, itemID = GetSendMailItem(index)
            local other = Marks:GetRecipient(itemID)
            if other then
                if recipient and recipient:lower() ~= other:lower() then
                    return nil
                end
                recipient = recipient or other
            end
        end
    end
    return recipient
end

local function FillRecipient()
    local text = SendMailNameEditBox:GetText()
    if text ~= "" and text ~= filled then
        return
    end
    local recipient = GetAttachmentsRecipient() or ""
    if recipient ~= text then
        SendMailNameEditBox:SetText(recipient)
    end
    filled = recipient
end

local listener = ns:CreateEventListener({
    MAIL_SEND_INFO_UPDATE = FillRecipient,
})

-- Fills in the To box while the mail mark and "mailTo" are on.
function Mail:SyncAutofill()
    if Marks:IsPartActive("mail") and Marks:GetSetting("mailTo") then
        listener:Start()
    else
        listener:Stop()
        filled = ""
    end
end
