-- Junk marking: the item menu entry, the junk coin, Sell All Junk and auto selling.
-- The fake bag starts as: G1 G2 - GJUNK (GJUNK is poor quality); items are their own IDs.

local function MarkEntry(world, slot)
    local menu = assert(world:AltRightClick(slot), "item menu opened")
    return world:MenuEntry(menu, world.L["inventory.junk.mark"])
end

local function ToggleMark(world, slot)
    assert(MarkEntry(world, slot), "mark entry").select()
end

test("marks every copy of an item as junk", function(world)
    world.itemIDs.G1, world.itemIDs.G2 = "CLOTH", "CLOTH"
    local entry = MarkEntry(world, 1)
    expect(entry.enabled, "entry enabled")
    expect(not entry.isSelected(), "not marked yet")

    entry.select()
    expect(MarkEntry(world, 2).isSelected(), "the other copy is marked")
    expect(world:JunkCoin(1) and world:JunkCoin(2), "coin on both copies")
    expect(not world:JunkCoin(4), "no coin on poor items")
    equal(world.env.ForeverEnhancedCharacterDB.inventory.junk.items.CLOTH, true, "saved per character")

    ToggleMark(world, 2)
    expect(not MarkEntry(world, 1).isSelected(), "unmarked")
    expect(not world:JunkCoin(1) and not world:JunkCoin(2), "coins hidden")
end)

test("poor and unsellable items can't be marked", function(world)
    local poor = MarkEntry(world, 4)
    expect(poor.isSelected(), "poor items show as junk")
    expect(not poor.enabled, "poor entry disabled")

    world.noValue.G2 = true
    expect(not MarkEntry(world, 2).enabled, "unsellable entry disabled")
end)

test("Sell All Junk sells marked items with the poor ones", function(world)
    ToggleMark(world, 1)
    world:OpenMerchant()
    world:ClickSellAllJunk()
    equal(world.hiddenPopups[1], "GENERIC_CONFIRMATION", "Blizzard's confirmation replaced")

    local popup = assert(world.popups[1], "our confirmation shown")
    equal(popup.text, world.L["core.junk.sellConfirm"], "text")
    equal(popup.text_arg1, 2, "junk items to sell")
    popup.callback()
    equal(table.concat(world.sold, " "), "G1 GJUNK", "sold")
    equal(world:Bag(), "- G2 - -", "bag")
end)

test("keeps locked copies of marked items", function(world)
    world.itemIDs.G1, world.itemIDs.G2 = "CLOTH", "CLOTH"
    ToggleMark(world, 1)
    world:AltClick(1)
    expect(not world:JunkCoin(1), "no coin on the locked copy")
    expect(world:JunkCoin(2), "coin on the other copy")

    world:OpenMerchant()
    world:ClickSellAllJunk()
    local popup = assert(world.popups[1], "our confirmation shown")
    equal(popup.text, world.L["core.junk.sellConfirmKept"], "text")
    equal(popup.text_arg1, 2, "junk items to sell")
    equal(popup.text_arg2, 1, "locked junk kept")
    popup.callback()
    equal(table.concat(world.sold, " "), "G2 GJUNK", "sold")
end)

test("enables Sell All Junk with only marked junk", function(world)
    world.bags[0][4] = nil
    world:OpenMerchant()
    expect(not world:IsSellAllJunkEnabled(), "disabled without junk")

    ToggleMark(world, 1)
    expect(world:IsSellAllJunkEnabled(), "enabled once an item is marked")
    ToggleMark(world, 1)
    expect(not world:IsSellAllJunkEnabled(), "disabled once unmarked")

    world:CloseMerchant()
    ToggleMark(world, 1)
    world:OpenMerchant()
    expect(world:IsSellAllJunkEnabled(), "enabled when the merchant opens")
end)

test("leaves junk in bags excluded from Sell All Junk", function(world)
    ToggleMark(world, 1)
    world.excludedFromJunkSell[0] = true
    world:OpenMerchant()
    world:ClickSellAllJunk()
    equal(#world.hiddenPopups, 0, "Blizzard's confirmation hidden")
    equal(#world.popups, 0, "our confirmations shown")
end)

test("auto selling sells marked items", function(world)
    world:Setting("inventory.merchant.enabled"):SetValue(true)
    world.sellPrices.G1, world.sellPrices.GJUNK = 10, 5
    ToggleMark(world, 1)
    world:OpenMerchant()
    equal(world.sellAllJunkCalls, 0, "Blizzard's Sell All Junk calls")
    equal(table.concat(world.sold, " "), "G1 GJUNK", "sold")
    local message = world.L["inventory.merchant.sold"]:format(2, GetMoneyString(15, true))
    expect(world.prints[#world.prints]:find(message, 1, true), "announced")
end)

test("turning the feature off hides coins and stops selling, and keeps marks", function(world)
    ToggleMark(world, 1)
    world:Setting("inventory.junk.enabled"):SetValue(false)
    expect(not world:JunkCoin(1), "coin hidden")
    equal(MarkEntry(world, 1), nil, "no menu entry")

    world:OpenMerchant()
    world:ClickSellAllJunk()
    equal(#world.hiddenPopups, 0, "Sell All Junk left to Blizzard")

    world:Setting("inventory.junk.enabled"):SetValue(true)
    expect(world:JunkCoin(1), "mark kept")
end)
