-- Item notes (the "notes" part): "Add note" (or "Edit note") in the item menu
-- writes a short note on that exact item, keyed by GUID so it follows the item
-- wherever it moves (GUIDs are never reused, so a note left behind by a sold
-- or destroyed item never matches another). The note shows in the item's
-- tooltip, set apart by an empty line and quoted like item flavor text.
--
-- Blizzard's GENERIC_INPUT_BOX can't be pre-filled and refuses blank text,
-- which is how a note is removed, so we register our own dialog. Turning the
-- part off hides it, so it never saves while the part is off.

local _, ns = ...

local Marks = ns:GetFeature("inventory", "marks")

local Notes = {}
Marks.Notes = Notes

local DIALOG = "FOREVER_ENHANCED_ITEM_NOTE"
local MAX_LETTERS = 255
local MENU_ORDER = 40
local NOTE_COLOR = CreateColor(0.69, 0.88, 1)

-- The character store: notes[guid] = text.
local function GetStore()
    local store = Marks:GetCharacterStore()
    store.notes = store.notes or {}
    return store
end

local function GetItemGUID(itemLocation)
    if itemLocation and itemLocation:IsValid() and C_Item.DoesItemExist(itemLocation) then
        return C_Item.GetItemGUID(itemLocation)
    end
end

-- Public API: the player's note on an item, or nil (always nil while the part is off).
function Marks:GetGUIDNote(guid)
    if self:IsPartActive("notes") and guid then
        return GetStore().notes[guid]
    end
end

-- Blank text removes the note.
function Marks:SetNote(guid, text)
    local note = strtrim(text)
    GetStore().notes[guid] = note ~= "" and note or nil
end

local function Save(editBox, data)
    Marks:SetNote(data.guid, editBox:GetText())
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
-- since. Keyed by the GUID: the item may move while the dialog is up.
local function EditNote(itemLocation, guid)
    if not guid or GetItemGUID(itemLocation) ~= guid then
        return
    end
    StaticPopupDialogs[DIALOG].text = ns.L["inventory.marks.notePrompt"]
    StaticPopup_Show(DIALOG, C_Item.GetItemLink(itemLocation), nil, { guid = guid, note = Marks:GetGUIDNote(guid) })
end

ns:AddItemButtonHandler(Marks, {
    part = "notes",
    menuOrder = MENU_ORDER,
    AddMenuEntries = function(rootDescription, itemLocation, guid)
        local key = Marks:GetGUIDNote(guid) and "inventory.marks.editNote" or "inventory.marks.addNote"
        rootDescription:CreateButton(ns.L[key], function()
            EditNote(itemLocation, guid)
        end)
    end,
})

ns:AddItemTooltipHandler(Marks, function(tooltip, data)
    local note = Marks:GetGUIDNote(data.guid)
    if note then
        local r, g, b = NOTE_COLOR:GetRGB()
        tooltip:AddLine(" ")
        tooltip:AddLine(ns.L["inventory.marks.noteLine"]:format(note), r, g, b, true)
    end
end)

-- The click shield takes Alt clicks only while some feature adds menu entries.
function Notes:Enable()
    ns:RefreshItemButtons()
end

function Notes:Disable()
    StaticPopup_Hide(DIALOG)
    ns:RefreshItemButtons()
end
