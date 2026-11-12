-- Item marks and notes: notes and the Wowhead link in the item menu (Alt Right Click),
-- and the menu's order. The fake bag starts as G1 G2 - GJUNK; items are their
-- own IDs and names.

local function Marks(world)
    return world.ns:GetFeature("inventory", "marks")
end

-- Notes ------------------------------------------------------------------------

local function NoteEntry(world, menu)
    return world:MenuEntry(menu, world.L["inventory.marks.addNote"])
        or world:MenuEntry(menu, world.L["inventory.marks.editNote"])
end

local function OpenNote(world, slot)
    local menu = assert(world:AltRightClick(slot), "item menu opened")
    assert(NoteEntry(world, menu), "note entry").callback()
end

local function WriteNote(world, slot, text)
    OpenNote(world, slot)
    world:TypeInDialog(text)
    world:ClickDialogButton(1)
end

local function NoteLines(world, guid)
    return world:ItemTooltip({ guid = guid, id = guid })
end

test("the note entry reads Add note, then Edit note", function(world)
    local menu = world:AltRightClick(1)
    expect(world:MenuEntry(menu, world.L["inventory.marks.addNote"]), "add note")
    WriteNote(world, 1, "For my alt")
    menu = world:AltRightClick(1)
    expect(world:MenuEntry(menu, world.L["inventory.marks.editNote"]), "edit note once written")
    expect(not world:MenuEntry(menu, world.L["inventory.marks.addNote"]), "no add note")
end)

test("writes a note shown in the tooltip", function(world)
    OpenNote(world, 2)
    local dialog = assert(world:Dialog(), "dialog shown")
    equal(
        dialog.text,
        world.L["inventory.marks.notePrompt"]:format(C_Item.GetItemLink(ItemLocation:CreateFromBagAndSlot(0, 2))),
        "prompt names the item"
    )
    equal(dialog:GetEditBox():GetText(), "", "empty without a note")

    world:TypeInDialog("  Quest item  ")
    world:PressEnterInDialog()
    expect(not world:Dialog(), "Enter closes the dialog")
    local lines = NoteLines(world, "G2")
    equal(#lines, 2, "tooltip lines")
    equal(lines[1], " ", "empty line before the note")
    equal(lines[2], world.L["inventory.marks.noteLine"]:format("Quest item"), "trimmed, quoted note")

    OpenNote(world, 2)
    equal(world:Dialog():GetEditBox():GetText(), "Quest item", "pre-filled with the note")
end)

test("a note doesn't lock its item, and unlocking keeps it", function(world)
    local Locking = world.ns:GetFeature("inventory", "locking")
    WriteNote(world, 2, "Quest item")
    expect(not Locking:IsGUIDLocked("G2"), "not locked")
    world:AltClick(2)
    world:AltClick(2)
    equal(Marks(world):GetGUIDNote("G2"), "Quest item", "note kept after unlocking")
end)

test("the note goes under the locked line", function(world)
    world:AltClick(1)
    WriteNote(world, 1, "For my alt")
    local lines = NoteLines(world, "G1")
    equal(#lines, 3, "tooltip lines")
    expect(lines[1]:find(world.L["inventory.locking.tooltipLine"], 1, true), "locked line first")
    equal(lines[3], world.L["inventory.marks.noteLine"]:format("For my alt"), "then the note")
end)

test("cancelling or a blank note writes nothing", function(world)
    OpenNote(world, 2)
    world:TypeInDialog("Quest item")
    world:ClickDialogButton(2)
    WriteNote(world, 2, "   ")
    equal(Marks(world):GetGUIDNote("G2"), nil, "no note")
    equal(#NoteLines(world, "G2"), 0, "tooltip lines")
end)

test("a blank note removes the note", function(world)
    WriteNote(world, 1, "For my alt")
    WriteNote(world, 1, "")
    equal(Marks(world):GetGUIDNote("G1"), nil, "note")
    equal(#NoteLines(world, "G1"), 0, "tooltip lines")
end)

test("a note follows its item, even when it moves while the dialog is open", function(world)
    OpenNote(world, 1)
    world.bags[0][1], world.bags[0][3] = nil, "G1"
    world:Fire("BAG_UPDATE_DELAYED")
    world:TypeInDialog("Moved")
    world:ClickDialogButton(1)
    equal(Marks(world):GetGUIDNote("G1"), "Moved", "note on the moved item")
end)

test("the note entry ignores an item that left its slot", function(world)
    local menu = world:AltRightClick(1)
    world.bags[0][1], world.bags[0][3] = nil, "G1"
    NoteEntry(world, menu).callback()
    expect(not world:Dialog(), "no dialog")
end)

for _, setting in ipairs({ "inventory.marks.notes", "inventory.marks.enabled" }) do
    test("turning off " .. setting .. " hides notes and the note dialog", function(world)
        WriteNote(world, 1, "For my alt")
        OpenNote(world, 1)
        world:Setting(setting):SetValue(false)
        expect(not world:Dialog(), "dialog hidden")
        equal(#NoteLines(world, "G1"), 0, "tooltip lines")
        expect(not NoteEntry(world, world:AltRightClick(1) or {}), "no note entry")

        world:Setting(setting):SetValue(true)
        equal(Marks(world):GetGUIDNote("G1"), "For my alt", "note kept")
    end)
end

-- Item locking showed a note only on a locked item: those move to Item marks.
test("notes saved by Item locking move to Item marks", function(world)
    equal(Marks(world):GetGUIDNote("G1"), "For my alt", "note of a locked item moved")
    equal(Marks(world):GetGUIDNote("G2"), nil, "note of an unlocked item dropped")
    local db = world.env.ForeverEnhancedCharacterDB.inventory
    equal(db.locking.notes, nil, "removed from Item locking")
    expect(db.locking.locks.G1, "locks kept")
end, {
    characterSavedVariables = function()
        return {
            inventory = {
                locking = { locks = { G1 = true }, notes = { G1 = "For my alt", G2 = "Stale" } },
            },
        }
    end,
})

-- Wowhead link -----------------------------------------------------------------

local function EnableWowhead(world)
    world:Setting("inventory.marks.wowhead"):SetValue(true)
end

local function WowheadEntry(world, slot)
    local menu = assert(world:AltRightClick(slot), "item menu opened")
    return world:MenuEntry(menu, world.L["inventory.marks.wowheadLink"])
end

local function URL(world, itemID)
    return world.L["inventory.marks.wowheadURL"]:format(itemID)
end

test("Wowhead link is off by default", function(world)
    expect(not WowheadEntry(world, 1), "no entry")
end)

test("Wowhead link shows the item's address, selected", function(world)
    EnableWowhead(world)
    world.itemIDs.G2 = "CLOTH"
    local entry = assert(WowheadEntry(world, 2), "menu entry")
    equal(entry.kind, "button", "a button")
    entry.callback()
    local dialog = assert(world:Dialog(), "dialog shown")
    equal(dialog:GetEditBox():GetText(), URL(world, "CLOTH"), "address of the item")
    expect(URL(world, "CLOTH"):find("wowhead.com/forever/", 1, true), "Forever's pages")
end)

test("the Wowhead address can't be edited, and Enter closes it", function(world)
    EnableWowhead(world)
    WowheadEntry(world, 1).callback()
    local dialog = world:Dialog()
    world:TypeInDialog("oops")
    dialog.info.EditBoxOnTextChanged(dialog:GetEditBox(), dialog.data)
    equal(dialog:GetEditBox():GetText(), URL(world, "G1"), "address restored")
    world:PressEnterInDialog()
    equal(world:Dialog(), nil, "closed")
end)

test("turning Wowhead link off removes the entry and closes its dialog", function(world)
    EnableWowhead(world)
    WowheadEntry(world, 1).callback()
    world:Setting("inventory.marks.wowhead"):SetValue(false)
    equal(world:Dialog(), nil, "dialog closed")
    expect(not WowheadEntry(world, 1), "no entry")
end)

-- Order ------------------------------------------------------------------------

test("the item menu lists the checkboxes, then Wowhead link, the note last", function(world)
    world:Setting("inventory.merchant.enabled"):SetValue(true)
    EnableWowhead(world)
    local menu = world:AltRightClick(1)
    equal(menu[2].text, world.L["inventory.locking.lock"], "lock second")
    equal(menu[3].text, world.L["inventory.marks.markAsJunk"], "junk third")
    equal(menu[#menu - 1].text, world.L["inventory.marks.wowheadLink"], "Wowhead link before the note")
    equal(menu[#menu].text, world.L["inventory.marks.addNote"], "note last")
end)
