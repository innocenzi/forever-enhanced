-- Item Locking: toggling, click shield, guards, tooltip, indicators, lifecycle.
-- The fake bag starts as: G1 G2 - GJUNK (GJUNK is poor quality).

local function Locking(world)
    return world.ns:GetFeature("inventory", "locking")
end

test("alt shows a shield over items only", function(world)
    world:SetAlt(true)
    expect(world:IsShielded(1), "shield over an item")
    expect(not world:IsShielded(3), "no shield over an empty slot")
    world:SetAlt(false)
    expect(not world:IsShielded(1), "shield dropped when alt is released")
end)

test("alt+click locks and unlocks", function(world)
    world:AltClick(1)
    expect(Locking(world):IsGUIDLocked("G1"), "locked")
    equal(world.env.ForeverEnhancedCharacterDB.inventory.locking.locks.G1, true, "saved per character")
    equal(#world.prints, 0, "nothing in chat")

    world:AltClick(1)
    expect(not Locking(world):IsGUIDLocked("G1"), "unlocked")
end)

test("returns a picked-up locked item on the next frame", function(world)
    world:AltClick(1)
    C_Container.PickupContainerItem(0, 1)
    expect(world.cursor ~= nil, "not cleared inside the pickup (that leaves the slot stuck)")
    world:NextFrame()
    equal(world.cursor, nil, "cursor")
    equal(#world.errors, 1, "errors shown")
end)

test("lets unlocked items be picked up", function(world)
    C_Container.PickupContainerItem(0, 2)
    world:NextFrame()
    expect(world.cursor ~= nil, "still on the cursor")
    equal(#world.errors, 0, "errors shown")
end)

test("blocks dropping onto a locked slot", function(world)
    world:AltClick(1)
    C_Container.PickupContainerItem(0, 2)
    world:NextFrame()
    expect(world:IsShielded(1), "locked slot shielded while the cursor holds an item")
    local shield = world:Shield(1)
    shield.scripts.OnReceiveDrag(shield)
    equal(world.errors[#world.errors], world.L["inventory.locking.isLocked"], "error")
    equal(world:Bag(), "G1 G2 - GJUNK", "bag unchanged")
end)

test("blocks selling a locked item at a merchant", function(world)
    world:AltClick(1)
    MerchantFrame.shown = true
    world:Fire("MERCHANT_SHOW")
    expect(world:IsShielded(1), "locked item shielded at the merchant")
    expect(not world:IsShielded(2), "unlocked item not shielded")
    world:ClickShield(1, "RightButton")
    equal(world.errors[#world.errors], world.L["inventory.locking.cannotSell"], "error")
end)

-- Sell All Junk. Junk = poor quality with a sell price; the bag becomes G1 JUNK - GJUNK.
local function WithTwoJunkItems(world)
    world.bags[0][2] = "JUNK"
    world.quality.JUNK = 0
    world:OpenMerchant()
end

test("leaves Sell All Junk to Blizzard when no junk is locked", function(world)
    WithTwoJunkItems(world)
    world:AltClick(1) -- a locked item that isn't junk doesn't matter
    world:ClickSellAllJunk()
    equal(#world.hiddenPopups, 0, "Blizzard's confirmation hidden")
    equal(#world.popups, 0, "our confirmations shown")
end)

test("sells unlocked junk and keeps locked junk", function(world)
    WithTwoJunkItems(world)
    world:AltClick(4)
    world:ClickSellAllJunk()
    equal(world.hiddenPopups[1], "GENERIC_CONFIRMATION", "Blizzard's confirmation replaced")

    local popup = assert(world.popups[1], "our confirmation shown")
    equal(popup.text, world.L["core.junk.sellConfirmKept"], "text")
    equal(popup.text_arg1, 1, "junk items to sell")
    equal(popup.text_arg2, 1, "locked junk kept")
    equal(#world.sold, 0, "nothing sold before accepting")

    popup.callback()
    equal(table.concat(world.sold, " "), "JUNK", "sold")
    equal(world:Bag(), "G1 - - GJUNK", "bag")
end)

test("rechecks junk when the sale is accepted", function(world)
    WithTwoJunkItems(world)
    world:AltClick(4)
    world:ClickSellAllJunk()
    world:AltClick(2) -- locked while the confirmation was up
    world.popups[1].callback()
    equal(#world.sold, 0, "sold")

    world:AltClick(2) -- unlocked again: one junk item to sell
    world:ClickSellAllJunk()
    MerchantFrame.shown = false -- merchant closed before accepting
    assert(world.popups[2], "second confirmation shown").callback()
    equal(#world.sold, 0, "sold after the merchant closed")
end)

test("says so when all junk is locked", function(world)
    world:OpenMerchant()
    world:AltClick(4)
    world:ClickSellAllJunk()
    equal(world.hiddenPopups[1], "GENERIC_CONFIRMATION", "Blizzard's confirmation hidden")
    equal(#world.popups, 0, "our confirmations shown")
    equal(world.errors[#world.errors], world.L["core.junk.allKept"], "error")
end)

test("cancels Sell All Junk instead when selling unlocked junk is off", function(world)
    WithTwoJunkItems(world)
    world:AltClick(4)
    world:Setting("inventory.locking.sellUnlockedJunk"):SetValue(false)
    world:ClickSellAllJunk()
    equal(world.hiddenPopups[1], "GENERIC_CONFIRMATION", "Blizzard's confirmation hidden")
    equal(#world.popups, 0, "our confirmations shown")
    equal(world.errors[#world.errors], world.L["core.junk.sellBlocked"], "error")
end)

test("ignores junk in bags excluded from Sell All Junk", function(world)
    WithTwoJunkItems(world)
    world:AltClick(4)
    world.excludedFromJunkSell[0] = true -- Blizzard wouldn't sell any of it
    world:ClickSellAllJunk()
    equal(#world.hiddenPopups, 0, "Blizzard's confirmation hidden")
    equal(#world.popups, 0, "our confirmations shown")
end)

test("adds a tooltip line to locked items only", function(world)
    world:AltClick(1)
    local lines = world:ItemTooltip({ guid = "G1", id = "G1" })
    equal(#lines, 1, "locked item lines")
    expect(lines[1]:find(world.L["inventory.locking.tooltipLine"], 1, true), "line text")
    equal(#world:ItemTooltip({ guid = "G2", id = "G2" }), 0, "unlocked item lines")
end)

test("alt+right-click opens the item menu, titled with the item", function(world)
    local menu = world:AltRightClick(1)
    equal(menu[1].kind, "title", "title first")
    equal(menu[1].text, "G1", "item name")
    equal(menu[1].color, nil, "Blizzard's default title color")
end)

test("the item menu locks and unlocks", function(world)
    local lock = world:MenuEntry(world:AltRightClick(1), world.L["inventory.locking.lock"])
    equal(lock.kind, "checkbox", "a checkbox")
    expect(not lock.isSelected(), "unchecked while unlocked")

    lock.select()
    expect(Locking(world):IsGUIDLocked("G1"), "locked")
    lock = world:MenuEntry(world:AltRightClick(1), world.L["inventory.locking.lock"])
    expect(lock.isSelected(), "checked while locked")

    lock.select()
    expect(not Locking(world):IsGUIDLocked("G1"), "unlocked")
end)

test("the lock entry ignores an item that left its slot", function(world)
    local lock = world:MenuEntry(world:AltRightClick(1), world.L["inventory.locking.lock"])
    world.bags[0][1], world.bags[0][3] = nil, "G1"
    lock.select()
    expect(not Locking(world):IsGUIDLocked("G1"), "not locked")
end)

test("no item menu without a feature or part adding entries", function(world)
    world:Setting("inventory.locking.enabled"):SetValue(false)
    for _, mark in ipairs({ "junk", "auction", "bank" }) do
        world:Setting("inventory.marks." .. mark):SetValue(false)
    end
    world:Setting("inventory.marks.notes"):SetValue(false)
    world:SetAlt(true)
    expect(not world:IsShielded(1), "no shield")
    world:SetAlt(false)
end)

test("the item menu stays open once Alt is released", function(world)
    world:AltRightClick(1)
    expect(world:IsContextMenuOpen(), "menu open")
    expect(world:IsShielded(1), "its shield kept")
    expect(not world:IsShielded(2), "other shields dropped")

    world:CloseContextMenu()
    expect(not world:IsShielded(1), "shield dropped once the menu closes")
end)

test("the item menu's shield ignores plain clicks", function(world)
    world:AltClick(1)
    world:AltRightClick(1)
    world:ClickShield(1, "LeftButton")
    world:ClickShield(1, "RightButton")
    equal(#world.errors, 0, "no locked item error")
end)

test("opening the item menu on another item moves its shield", function(world)
    world:AltRightClick(1)
    world:AltRightClick(2)
    expect(world:IsContextMenuOpen(), "menu open")
    expect(not world:IsShielded(1), "first shield dropped")
    expect(world:IsShielded(2), "second shield kept")
end)

test("closing the bags closes the item menu", function(world)
    world:AltRightClick(1)
    world:CloseBags()
    expect(not world:IsContextMenuOpen(), "menu closed")
    world:OpenBags()
    expect(not world:IsShielded(1), "no shield left")
end)

test("draws the chosen indicator style", function(world)
    world:AltClick(1)
    local indicator = world:Setting("inventory.locking.indicator")

    equal(world:Indicator(1), "QuestSharing-Padlock 13x16 BOTTOMLEFT+shadow", "padlock")
    equal(world:Indicator(2), "", "unlocked item")
    indicator:SetValue("center")
    equal(world:Indicator(1), "bankslot-icon-lock 24x24 CENTER", "center")
    indicator:SetValue("corner")
    equal(world:Indicator(1), "bankslot-icon-lock 20x20 TOPRIGHT", "corner")
    indicator:SetValue("none")
    equal(world:Indicator(1), "hidden", "none")
    indicator:SetValue("padlock")
    equal(world:Indicator(1), "QuestSharing-Padlock 13x16 BOTTOMLEFT+shadow", "back to padlock")
end)

test("turning the feature off undoes everything and keeps locks", function(world)
    world:AltClick(1)
    world:AltClick(4)
    MerchantFrame.shown = true
    world:Fire("MERCHANT_SHOW")

    world:Setting("inventory.locking.enabled"):SetValue(false)
    expect(not world:IsShielded(1), "shield removed")
    equal(world:Indicator(1), "hidden", "indicator")
    expect(not Locking(world):IsGUIDLocked("G1"), "public API reports unlocked while inactive")
    world:ClickSellAllJunk()
    equal(#world.popups, 0, "locked junk left to Blizzard's Sell All Junk")
    equal(#world.errors, 0, "errors")
    C_Container.PickupContainerItem(0, 1)
    world:NextFrame()
    expect(world.cursor ~= nil, "cursor guard off")
    ClearCursor()

    world:Setting("inventory.locking.enabled"):SetValue(true)
    expect(Locking(world):IsGUIDLocked("G1"), "lock kept")
    expect(world:IsShielded(1), "shield back at the merchant")
end)
