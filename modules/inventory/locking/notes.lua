-- Item notes: "Add note" in the item menu (Alt Right Click) writes a short
-- note, shown in the item's tooltip (tooltip.lua). Saving a note on an
-- unlocked item locks it.
--
-- Blizzard's GENERIC_INPUT_BOX can't be pre-filled and refuses blank text,
-- which is how a note is removed, so we register our own dialog. Disabling the
-- feature hides it, so it never saves while the feature is inactive.

local _, ns = ...

local Locking = ns:GetFeature("inventory", "locking")

local Notes = {}
Locking.Notes = Notes

local DIALOG = "FOREVER_ENHANCED_ITEM_NOTE"
local MAX_LETTERS = 255

local function Save(editBox, data)
    Locking:SetNote(data.guid, editBox:GetText())
end

-- The text is set when shown: strings are in the player's language only after
-- the addon has loaded.
StaticPopupDialogs[DIALOG] = {
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    OnShow = function(dialog, data)
        local editBox = dialog:GetEditBox()
        editBox:SetMaxLetters(MAX_LETTERS)
        editBox:SetText(data.note or "")
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

-- `guid`: the item the menu was opened on, ignored if it has left `itemLocation`
-- since. Keyed by the GUID: the item may move while the popup is up.
function Locking:EditNote(itemLocation, guid)
    if not guid or self:GetItemGUID(itemLocation) ~= guid then
        return
    end
    local link = C_Item.GetItemLink(itemLocation)
    StaticPopupDialogs[DIALOG].text = ns.L["inventory.locking.notePrompt"]
    StaticPopup_Show(DIALOG, link, nil, { guid = guid, note = self:GetGUIDNote(guid) })
end

function Notes:Disable()
    StaticPopup_Hide(DIALOG)
end
