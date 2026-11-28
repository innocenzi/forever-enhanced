-- Item marks: the auction house, bank and mail marks, their menu entries and icons;
-- junk excludes the other marks, auction house, bank and mail combine.
-- The fake bag starts as: G1 G2 - GJUNK (GJUNK is poor quality); items are their own IDs.

local TEXTS = {
    auction = "inventory.marks.markForAuction",
    bank = "inventory.marks.markForBank",
    junk = "inventory.marks.markAsJunk",
    mail = "inventory.marks.markForMail",
}

local function Entry(world, slot, mark)
    local menu = assert(world:AltRightClick(slot), "item menu opened")
    return world:MenuEntry(menu, world.L[TEXTS[mark]])
end

local MAIL_DIALOG = "FOREVER_ENHANCED_MAIL_RECIPIENT"

-- Marking for mail asks who the item goes to: answers "Alt".
local function AnswerRecipient(world)
    local dialog = world:Dialog()
    if dialog and dialog.which == MAIL_DIALOG then
        world:TypeInDialog("Alt")
        world:ClickDialogButton(1)
    end
end

local function Toggle(world, slot, mark)
    assert(Entry(world, slot, mark), mark .. " entry").select()
    AnswerRecipient(world)
end

local function IsMarked(world, slot, mark)
    return Entry(world, slot, mark).isSelected()
end

local function Icon(world, slot)
    local icon
    for _, texture in ipairs(world.textures) do
        local atlas = texture.atlas
        local isMark = atlas == "auctioneer" or atlas == "banker" or atlas == "mailbox"
        if isMark and texture.owner.parent == world.buttons[slot] then
            icon = texture
        end
    end
    return icon
end

for _, mark in ipairs({ "auction", "bank", "mail" }) do
    local Shown = ({ auction = "AuctionMark", bank = "BankMark", mail = "MailMark" })[mark]

    test(mark .. ": marks every copy of an item", function(world)
        world.itemIDs.G1, world.itemIDs.G2 = "CLOTH", "CLOTH"
        local entry = Entry(world, 1, mark)
        equal(entry.kind, "checkbox", "a checkbox")
        expect(entry.enabled, "entry enabled")
        expect(not entry.isSelected(), "not marked yet")
        expect(not world[Shown](world, 1), "no icon yet")

        entry.select()
        AnswerRecipient(world)
        expect(IsMarked(world, 2, mark), "the other copy is marked")
        expect(world[Shown](world, 1) and world[Shown](world, 2), "icon on both copies")
        expect(not world[Shown](world, 4), "no icon on other items")
        equal(Icon(world, 1).point, "TOPLEFT", "icon top-left, where the junk coin goes")
        equal(
            world.env.ForeverEnhancedCharacterDB.inventory.marks.destinations.CLOTH[mark],
            true,
            "saved per character"
        )

        Toggle(world, 2, mark)
        expect(not IsMarked(world, 1, mark), "unmarked")
        expect(not world[Shown](world, 1) and not world[Shown](world, 2), "icons hidden")
    end)

    test(mark .. ": locked items don't show the icon", function(world)
        Toggle(world, 1, mark)
        world:AltClick(1)
        expect(not world[Shown](world, 1), "hidden while locked")
        expect(IsMarked(world, 1, mark), "still marked")

        world:AltClick(1)
        expect(world[Shown](world, 1), "back once unlocked")
    end)
end

test("poor items can't be marked, bound items only for the bank", function(world)
    expect(not Entry(world, 4, "auction").enabled, "poor: no auction house")
    expect(not Entry(world, 4, "bank").enabled, "poor: no bank")

    expect(not Entry(world, 4, "mail").enabled, "poor: no mail")

    world.bound.G1 = true
    expect(not Entry(world, 1, "auction").enabled, "bound: no auction house")
    expect(not Entry(world, 1, "mail").enabled, "bound: no mail")
    expect(Entry(world, 1, "bank").enabled, "bound: bank")
end)

local function Marked(world, slot)
    local marked = {}
    for _, mark in ipairs({ "junk", "auction", "bank", "mail" }) do
        if IsMarked(world, slot, mark) then
            table.insert(marked, mark)
        end
    end
    return table.concat(marked, " ")
end

local function RecipientLine(world, itemID)
    local prefix = world.L["inventory.marks.mailRecipient"]:gsub("%%s.*", "")
    for _, line in ipairs(world:ItemTooltip({ guid = itemID, id = itemID })) do
        if line:sub(1, #prefix) == prefix then
            return line
        end
    end
end

test("mail: marking asks who the item goes to, shown in its tooltip", function(world)
    world.itemIDs.G1, world.itemIDs.G2 = "CLOTH", "CLOTH"
    Entry(world, 1, "mail").select()
    local dialog = assert(world:Dialog(), "dialog shown")
    equal(dialog.which, MAIL_DIALOG, "the recipient dialog")
    equal(
        dialog.text,
        world.L["inventory.marks.mailPrompt"]:format(C_Item.GetItemLink(ItemLocation:CreateFromBagAndSlot(0, 1))),
        "names the item"
    )
    equal(dialog:GetEditBox():GetText(), "", "empty the first time")
    equal(dialog.info.autoCompleteSource, C_AutoComplete.GetAutoCompleteResults, "completes names")
    equal(dialog.info.autoCompleteArgs[1], AUTOCOMPLETE_LIST.MAIL.include, "like the mail window")
    expect(not IsMarked(world, 1, "mail"), "not marked before answering")

    world:TypeInDialog("  Bank-Alt  ")
    world:PressEnterInDialog()
    expect(IsMarked(world, 1, "mail") and world:MailMark(2), "marked once answered")
    equal(RecipientLine(world, "CLOTH"), world.L["inventory.marks.mailRecipient"]:format("Bank-Alt"), "tooltip line")
    equal(
        world.env.ForeverEnhancedCharacterDB.inventory.marks.recipients.CLOTH,
        "Bank-Alt",
        "recipient saved per character"
    )

    Entry(world, 2, "mail").select()
    expect(not world:Dialog(), "unmarking asks nothing")
    expect(not IsMarked(world, 1, "mail"), "unmarked")
    equal(RecipientLine(world, "CLOTH"), nil, "no tooltip line")
    equal(world.env.ForeverEnhancedCharacterDB.inventory.marks.recipients.CLOTH, nil, "recipient forgotten")

    Entry(world, 2, "mail").select()
    equal(world:Dialog():GetEditBox():GetText(), "Bank-Alt", "pre-filled with the last recipient")
end)

test("mail: Cancel or a blank name leaves the item unmarked", function(world)
    Entry(world, 1, "mail").select()
    world:TypeInDialog("Alt")
    world:ClickDialogButton(2)
    expect(not IsMarked(world, 1, "mail"), "cancelled")

    Entry(world, 1, "mail").select()
    world:TypeInDialog("   ")
    world:ClickDialogButton(1)
    expect(not IsMarked(world, 1, "mail"), "blank")
end)

test("mail: junk replaces the mark and forgets the recipient", function(world)
    Toggle(world, 1, "mail")
    Toggle(world, 1, "junk")
    equal(Marked(world, 1), "junk", "junk replaces mail")
    equal(RecipientLine(world, "G1"), nil, "no tooltip line")
    equal(world.env.ForeverEnhancedCharacterDB.inventory.marks.recipients.G1, nil, "recipient forgotten")
end)

test("mail: turning the mark off hides its dialog, icon and tooltip line", function(world)
    Toggle(world, 2, "mail")
    Entry(world, 1, "mail").select()
    world:Setting("inventory.marks.mail"):SetValue(false)
    expect(not world:Dialog(), "dialog hidden")
    expect(not world:MailMark(2), "icon hidden")
    equal(RecipientLine(world, "G2"), nil, "no tooltip line")

    world:Setting("inventory.marks.mail"):SetValue(true)
    expect(world:MailMark(2), "icon back")
    equal(RecipientLine(world, "G2"), world.L["inventory.marks.mailRecipient"]:format("Alt"), "recipient kept")
end)

test("mail: marked items glow while trading with their recipient", function(world)
    Toggle(world, 1, "mail") -- for "Alt"
    Toggle(world, 2, "bank")

    world:OpenTrade("Someone")
    expect(not world:Glow(1), "no glow trading with someone else")
    world:CloseTrade()

    world:OpenTrade("alt")
    expect(world:Glow(1), "glows trading with the recipient, whatever the case")
    expect(not world:Glow(2), "items marked for elsewhere don't")
    world:CloseTrade()
    expect(not world:Glow(1), "gone once the trade closes")

    world:OpenTrade("Alt", "OtherRealm")
    expect(not world:Glow(1), "a namesake from another realm doesn't count")
    world:CloseTrade()

    Toggle(world, 1, "mail")
    Entry(world, 1, "mail").select()
    world:TypeInDialog("Alt-Other Realm")
    world:ClickDialogButton(1)
    world:OpenTrade("Alt", "OtherRealm")
    expect(world:Glow(1), "a recipient with a realm matches it, spaces aside")
    world:CloseTrade()
end)

test("mail: the trade glow follows its setting, and shows the mail icon", function(world)
    Toggle(world, 1, "mail")
    Toggle(world, 1, "bank")
    expect(world:BankMark(1), "bank icon first")

    world:OpenTrade("Alt")
    expect(world:MailMark(1) and not world:BankMark(1), "the mail icon while trading with the recipient")
    expect(world:Glow(1), "and its glow")

    world:Setting("inventory.marks.mailTradeGlow"):SetValue(false)
    expect(not world:Glow(1), "its toggle hides the glow")
    expect(world:MailMark(1), "the icon stays")
    world:CloseTrade()
end)

-- Marks the item in `slot` for mail to `recipient`.
local function MarkForMail(world, slot, recipient)
    Entry(world, slot, "mail").select()
    world:TypeInDialog(recipient)
    world:ClickDialogButton(1)
end

local function To()
    return SendMailNameEditBox:GetText()
end

test("mail: attaching marked items fills in their recipient", function(world)
    MarkForMail(world, 1, "Alt")
    world:OpenMailbox()

    world:AttachToMail(2)
    equal(To(), "", "an unmarked item fills in nothing")
    world:AttachToMail(1)
    equal(To(), "Alt", "a marked one fills in its recipient")
    world:RemoveMailAttachment(2)
    equal(To(), "", "cleared once it's removed")
    world:AttachToMail(1)
    equal(To(), "Alt", "back once attached again")

    world:SendMail()
    equal(To(), "", "the next mail starts empty")
    world:AttachToMail(1)
    equal(To(), "Alt", "and fills in again")
end)

test("mail: a name the player typed stays", function(world)
    MarkForMail(world, 1, "Alt")
    world:OpenMailbox()

    world:TypeMailRecipient("Someone")
    world:AttachToMail(1)
    equal(To(), "Someone", "typed before attaching")
    world:RemoveMailAttachment(1)
    equal(To(), "Someone", "kept once removed")

    world:TypeMailRecipient("")
    world:AttachToMail(1)
    equal(To(), "Alt", "filled in once the box is empty")
    world:TypeMailRecipient("Other")
    world:RemoveMailAttachment(1)
    equal(To(), "Other", "typed over ours, kept once removed")
end)

test("mail: items for different players fill in nothing", function(world)
    MarkForMail(world, 1, "Alt")
    MarkForMail(world, 2, "Other")
    world:OpenMailbox()

    world:AttachToMail(1)
    equal(To(), "Alt", "one recipient")
    world:AttachToMail(2)
    equal(To(), "", "two recipients: cleared")
    world:RemoveMailAttachment(1)
    equal(To(), "Other", "one recipient left")

    Entry(world, 1, "mail").select() -- unmarks
    MarkForMail(world, 1, "other")
    world:AttachToMail(1)
    equal(To(), "other", "the same recipient whatever the case, as the first attachment spells it")
end)

test("mail: filling in the recipient follows its setting and the mail mark", function(world)
    MarkForMail(world, 1, "Alt")
    world:OpenMailbox()

    world:Setting("inventory.marks.mailTo"):SetValue(false)
    world:AttachToMail(1)
    equal(To(), "", "its toggle off: nothing")
    world:RemoveMailAttachment(1)

    world:Setting("inventory.marks.mailTo"):SetValue(true)
    world:Setting("inventory.marks.mail"):SetValue(false)
    world:AttachToMail(1)
    equal(To(), "", "the mail mark off: nothing")
    world:RemoveMailAttachment(1)

    world:Setting("inventory.marks.mail"):SetValue(true)
    world:AttachToMail(1)
    equal(To(), "Alt", "both on")
end)

test("an item marked for auction house, bank and mail shows its next stop", function(world)
    Toggle(world, 1, "auction")
    Toggle(world, 1, "mail")
    expect(world:MailMark(1) and not world:AuctionMark(1), "bags: mail before auction house")

    Toggle(world, 1, "bank")
    expect(world:BankMark(1) and not world:MailMark(1), "bags: bank first")

    world:OpenMailbox()
    expect(world:MailMark(1) and not world:BankMark(1), "mailbox open: its icon")
    expect(world:Glow(1), "and its glow")
    world:CloseMailbox()
    expect(world:BankMark(1) and not world:MailMark(1), "the bank icon once closed")

    world:OpenAuctionHouse()
    expect(world:AuctionMark(1) and not world:MailMark(1), "auction house open: its icon")
    world:CloseAuctionHouse()
end)

test("junk excludes the other marks, auction house and bank combine", function(world)
    world:Setting("inventory.marks.junkCoin"):SetValue("always")
    world:Setting("inventory.merchant.enabled"):SetValue(true)

    Toggle(world, 1, "junk")
    Toggle(world, 1, "auction")
    equal(Marked(world, 1), "auction", "auction house replaces junk")
    expect(world:AuctionMark(1) and not world:JunkCoin(1), "icon instead of the coin")

    Toggle(world, 1, "bank")
    equal(Marked(world, 1), "auction bank", "bank joins auction house")

    Toggle(world, 1, "junk")
    equal(Marked(world, 1), "junk", "junk replaces both")
    expect(world:JunkCoin(1) and not world:AuctionMark(1) and not world:BankMark(1), "coin instead of the icons")

    Toggle(world, 1, "bank")
    equal(Marked(world, 1), "bank", "bank replaces junk")

    Toggle(world, 1, "auction")
    Toggle(world, 1, "bank")
    equal(Marked(world, 1), "auction", "unmarking bank keeps auction house")

    Toggle(world, 1, "auction")
    equal(Marked(world, 1), "", "unmarking leaves none")
    equal(world.env.ForeverEnhancedCharacterDB.inventory.marks.destinations.G1, nil, "nothing saved")
end)

test("an item marked for auction house and bank shows its next stop", function(world)
    Toggle(world, 1, "auction")
    Toggle(world, 1, "bank")
    expect(world:BankMark(1) and not world:AuctionMark(1), "bags: the bank icon")

    world:OpenAuctionHouse()
    expect(world:AuctionMark(1) and not world:BankMark(1), "auction house open: its icon")
    expect(world:Glow(1), "and its glow")

    world:CloseAuctionHouse()
    expect(world:BankMark(1) and not world:AuctionMark(1), "the bank icon once closed")

    world:OpenBank()
    expect(world:BankMark(1) and world:Glow(1), "bank open: its icon and glow")
    world:CloseBank()
    world:OpenBags() -- closing the bank closes the bags

    world:Setting("inventory.marks.bank"):SetValue(false)
    expect(world:AuctionMark(1) and not world:BankMark(1), "bank mark off: the auction house icon")
end)

test("older saves holding one destination still read", function(world)
    world.itemIDs.G1 = "CLOTH"
    world.env.ForeverEnhancedCharacterDB.inventory.marks.destinations = { CLOTH = "bank" }
    world.ns:RefreshItemButtons()
    expect(world:BankMark(1), "bank icon")
    equal(Marked(world, 1), "bank", "marked for the bank")

    Toggle(world, 1, "auction")
    equal(Marked(world, 1), "auction bank", "auction house joins it")
end)

test("disabling item marks hides the icons and the entries", function(world)
    Toggle(world, 1, "auction")
    Toggle(world, 2, "bank")
    world:Setting("inventory.marks.enabled"):SetValue(false)
    expect(not world:AuctionMark(1) and not world:BankMark(2), "icons hidden")
    expect(not Entry(world, 1, "auction") and not Entry(world, 1, "bank"), "no entries")

    world:Setting("inventory.marks.enabled"):SetValue(true)
    expect(world:AuctionMark(1) and world:BankMark(2), "icons back")
end)

-- Marks whose items glow while a window is open: the window, how the fake
-- client opens and closes it, and the other glowing mark.
local GLOWS = {
    {
        mark = "auction",
        other = "bank",
        name = "the auction house",
        open = "OpenAuctionHouse",
        close = "CloseAuctionHouse",
    },
    { mark = "bank", other = "auction", name = "the bank", open = "OpenBank", close = "CloseBank" },
    { mark = "mail", other = "auction", name = "the mailbox", open = "OpenMailbox", close = "CloseMailbox" },
}

for _, glow in ipairs(GLOWS) do
    local mark, other = glow.mark, glow.other

    test(mark .. " marks glow while " .. glow.name .. " is open", function(world)
        world.itemIDs.G1, world.itemIDs.G2 = "CLOTH", "CLOTH"
        Toggle(world, 1, mark)
        Toggle(world, 4, "junk")
        expect(not world:Glow(1), "no glow before " .. glow.name .. " opens")

        world[glow.open](world)
        expect(world:Glow(1) and world:Glow(2), "every marked copy glows")
        expect(not world:Glow(4), "no glow on other items")

        world[glow.close](world)
        world:OpenBags() -- closing the bank closes the bags
        expect(not world:Glow(1) and not world:Glow(2), "gone once closed")

        Toggle(world, 1, mark)
        Toggle(world, 1, other)
        world[glow.open](world)
        expect(not world:Glow(1), "items marked for " .. other .. " don't glow")
    end)

    test(mark .. " glow follows the mark, locking and its settings", function(world)
        Toggle(world, 1, mark)
        world[glow.open](world)
        expect(world:Glow(1), "glows")

        world:AltClick(1)
        expect(not world:Glow(1), "no glow while locked")
        world:AltClick(1)
        expect(world:Glow(1), "back once unlocked")

        world:Setting("inventory.marks." .. mark .. "Glow"):SetValue(false)
        expect(not world:Glow(1), "its toggle hides it")
        world:Setting("inventory.marks." .. mark .. "Glow"):SetValue(true)
        expect(world:Glow(1), "back with its toggle")

        world:Setting("inventory.marks." .. mark):SetValue(false)
        expect(not world:Glow(1), "the mark's toggle hides it")
        world:Setting("inventory.marks." .. mark):SetValue(true)

        world:Setting("inventory.marks.enabled"):SetValue(false)
        expect(not world:Glow(1), "disabling item marks hides it")
        world:Setting("inventory.marks.enabled"):SetValue(true)

        Toggle(world, 1, mark)
        expect(not world:Glow(1), "unmarking hides it")
    end)
end

for _, mark in ipairs({ "auction", "bank", "mail" }) do
    test("Alt Left Click can mark for " .. mark .. " instead of locking", function(world)
        world:Setting("inventory.marks.altClick"):SetValue(mark)
        world:AltClick(1)
        AnswerRecipient(world)
        expect(IsMarked(world, 1, mark), "marked")
        expect(not world.ns:GetFeature("inventory", "locking"):IsGUIDLocked("G1"), "not locked")

        world:AltClick(1)
        expect(not IsMarked(world, 1, mark), "unmarked")

        world:AltClick(4)
        expect(not IsMarked(world, 4, mark), "poor items can't take the mark")
    end)
end

test("Alt Left Click locks again when its mark is off", function(world)
    world:Setting("inventory.marks.altClick"):SetValue("bank")
    world:Setting("inventory.marks.bank"):SetValue(false)
    world:AltClick(1)
    expect(world.ns:GetFeature("inventory", "locking"):IsGUIDLocked("G1"), "locked")
end)

test("a locked item tells how to unlock it", function(world)
    world:AltClick(1)
    world:Setting("inventory.marks.altClick"):SetValue("junk")
    C_Container.PickupContainerItem(0, 2)
    world:NextFrame()
    local shield = world:Shield(1)
    shield.scripts.OnReceiveDrag(shield)
    equal(world.errors[#world.errors], world.L["inventory.locking.isLockedMenu"], "from the item menu")
end)

test("junk coins follow the bag's exclude from Sell All Junk option", function(world)
    world:Setting("inventory.marks.junkCoin"):SetValue("always")
    expect(world:JunkCoin(4), "coin on junk")
    world:ExcludeFromJunkSell(0, true)
    expect(not world:JunkCoin(4), "no coin in an excluded bag")
    world:ExcludeFromJunkSell(0, false)
    expect(world:JunkCoin(4), "coin back")
end)

test("Alt Left Click sits with the marks, and says it otherwise locks", function(world)
    local rows = {}
    for _, key in ipairs({ "mailTo", "altClick", "notes" }) do
        rows[world:Setting("inventory.marks." .. key)] = key
    end
    local order = {}
    for _, category in ipairs(world.categories) do
        for _, item in ipairs(category.items) do
            if rows[item.setting] then
                table.insert(order, rows[item.setting])
            end
        end
    end
    equal(table.concat(order, " "), "mailTo altClick notes", "after the marks, before notes")
    expect(
        world.L["inventory.marks.altClick.tooltip"]:find(world.L["inventory.locking.title"], 1, true),
        "names Item locking"
    )
end)
