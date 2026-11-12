-- Junk marking (Item marks' junk part): the item menu entry, the junk coin,
-- Sell All Junk and auto selling. Merchant is on, coins always shown, auto
-- selling off unless a test turns it on.
-- The fake bag starts as: G1 G2 - GJUNK (GJUNK is poor quality); items are their own IDs.

local function Enable(world)
    world:Setting("inventory.merchant.autoSellJunk"):SetValue(false)
    world:Setting("inventory.marks.junkCoin"):SetValue("always")
    world:Setting("inventory.merchant.enabled"):SetValue(true)
end

local function MarkEntry(world, slot)
    local menu = assert(world:AltRightClick(slot), "item menu opened")
    return world:MenuEntry(menu, world.L["inventory.marks.markAsJunk"])
end

local function ToggleMark(world, slot)
    assert(MarkEntry(world, slot), "mark entry").select()
end

test("marks every copy of an item as junk", function(world)
    Enable(world)
    world.itemIDs.G1, world.itemIDs.G2 = "CLOTH", "CLOTH"
    local entry = MarkEntry(world, 1)
    expect(entry.enabled, "entry enabled")
    expect(not entry.isSelected(), "not marked yet")

    entry.select()
    expect(MarkEntry(world, 2).isSelected(), "the other copy is marked")
    expect(world:JunkCoin(1) and world:JunkCoin(2), "coin on both copies")
    equal(world.env.ForeverEnhancedCharacterDB.inventory.marks.destinations.CLOTH, "junk", "saved per character")

    ToggleMark(world, 2)
    expect(not MarkEntry(world, 1).isSelected(), "unmarked")
    expect(not world:JunkCoin(1) and not world:JunkCoin(2), "coins hidden")
end)

test("the junk coin shows on the junk Sell All Junk would sell", function(world)
    Enable(world)
    world.bags[0][3] = "GREY"
    world.quality.GREY = 0
    world.noValue.GREY = true
    expect(world:JunkCoin(4), "coin on poor items")
    expect(not world:JunkCoin(3), "no coin on unsellable poor items")
    expect(not world:JunkCoin(1), "no coin on other items")

    world:AltClick(4)
    expect(not world:JunkCoin(4), "no coin on locked poor items")

    ToggleMark(world, 1)
    world.excludedFromJunkSell[0] = true
    world:Fire("BAG_UPDATE_DELAYED")
    expect(not world:JunkCoin(1), "no coin in bags excluded from Sell All Junk")
end)

test("the junk coin shows only at merchants by default, like Blizzard's", function(world)
    Enable(world)
    world:Setting("inventory.marks.junkCoin"):SetValue("merchant")
    ToggleMark(world, 1)
    expect(not world:JunkCoin(1), "no coin away from merchants")

    world:OpenMerchant()
    expect(world:JunkCoin(1), "coin on marked items at a merchant")
    expect(not world:JunkCoin(4), "poor items left to Blizzard's coin")

    world:CloseMerchant()
    expect(not world:JunkCoin(1), "coin hidden once the merchant closes")

    world:Setting("inventory.marks.junkCoin"):SetValue("always")
    expect(world:JunkCoin(1) and world:JunkCoin(4), "coins once always shown")
end)

test("poor and unsellable items can't be marked", function(world)
    Enable(world)
    local poor = MarkEntry(world, 4)
    expect(poor.isSelected(), "poor items show as junk")
    expect(not poor.enabled, "poor entry disabled")

    world.noValue.G2 = true
    expect(not MarkEntry(world, 2).enabled, "unsellable entry disabled")
end)

test("Sell All Junk sells marked items with the poor ones", function(world)
    Enable(world)
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
    Enable(world)
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
    Enable(world)
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
    Enable(world)
    ToggleMark(world, 1)
    world.excludedFromJunkSell[0] = true
    world:OpenMerchant()
    world:ClickSellAllJunk()
    equal(#world.hiddenPopups, 0, "Blizzard's confirmation hidden")
    equal(#world.popups, 0, "our confirmations shown")
end)

test("auto selling sells marked items", function(world)
    Enable(world)
    world:Setting("inventory.merchant.autoSellJunk"):SetValue(true)
    world.sellPrices.G1, world.sellPrices.GJUNK = 10, 5
    ToggleMark(world, 1)
    world:OpenMerchant()
    equal(world.sellAllJunkCalls, 0, "Blizzard's Sell All Junk calls")
    equal(table.concat(world.sold, " "), "G1 GJUNK", "sold")
    local message = world.L["inventory.merchant.sold"]:format(2, GetMoneyString(15, true))
    expect(world.prints[#world.prints]:find(message, 1, true), "announced")
end)

for _, key in ipairs({ "inventory.marks.junk", "inventory.marks.enabled" }) do
    test("turning " .. key .. " off hides coins and stops selling, and keeps marks", function(world)
        Enable(world)
        ToggleMark(world, 1)
        world:Setting(key):SetValue(false)
        expect(not world:JunkCoin(1), "coin hidden")
        equal(MarkEntry(world, 1), nil, "no menu entry")

        world:OpenMerchant()
        world.hiddenPopups = {} -- turning the feature off closes its own dialogs
        world:ClickSellAllJunk()
        equal(#world.hiddenPopups, 0, "Sell All Junk left to Blizzard")

        world:Setting(key):SetValue(true)
        expect(world:JunkCoin(1), "mark kept")
    end)
end
