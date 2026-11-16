-- Merchant search (the merchant feature's "search" part): dims the items that
-- don't match, shows the first page holding a match, lights the page arrows
-- toward other matches.
-- Merchant items are named after their item IDs.

-- Three pages: A1 to A10, B1 to B10, C1 to C3.
local function WithThreePages(world)
    for _, prefix in ipairs({ "A", "B", "C" }) do
        for number = 1, prefix == "C" and 3 or 10 do
            table.insert(world.merchantItems, prefix .. number)
        end
    end
end

local function Open(world, items)
    world.merchantItems = items or world.merchantItems
    world:OpenMerchant()
end

test("dims the items that don't match the search", function(world)
    Open(world, { "A1", "A2", "A3" })
    expect(world:MerchantSearchBox():IsShown(), "search box shown")
    equal(world:MerchantSlots(), "A1 A2 A3", "nothing dimmed before searching")

    world:SearchMerchant("a2")
    equal(world:MerchantSlots(), "~A1 A2 ~A3", "dimmed")

    world:SearchMerchant("")
    equal(world:MerchantSlots(), "A1 A2 A3", "search cleared")
end)

test("matches items by type and subtype", function(world)
    world.itemTypes.A3 = { "Trade Goods", "Reagent", "" }
    Open(world, { "A1", "A2", "A3" })
    world:SearchMerchant("Reagent")
    equal(world:MerchantSlots(), "~A1 ~A2 A3", "dimmed")
end)

test("shows the first page holding a match when the page shown has none", function(world)
    WithThreePages(world)
    Open(world)
    world:SearchMerchant("c2")
    equal(MerchantFrame.page, 3, "page")
    equal(world:MerchantSlots(), "~C1 C2 ~C3", "dimmed")
    equal(world:MerchantArrowGlows(), "", "no other matches")

    world:SearchMerchant("b")
    equal(MerchantFrame.page, 2, "first page with a match")
end)

test("stays on the page shown when it holds a match", function(world)
    WithThreePages(world)
    Open(world)
    world:TurnMerchantPage(1)
    world:SearchMerchant("1")
    equal(MerchantFrame.page, 2, "page")
    equal(world:MerchantSlots(), "B1 ~B2 ~B3 ~B4 ~B5 ~B6 ~B7 ~B8 ~B9 B10", "dimmed")
    equal(world:MerchantArrowGlows(), "prev next", "matches on both sides")
end)

test("follows page turns", function(world)
    WithThreePages(world)
    Open(world)
    world:SearchMerchant("a1")
    equal(world:MerchantArrowGlows(), "", "every match on the page")

    world:TurnMerchantPage(1)
    equal(world:MerchantSlots(), "~B1 ~B2 ~B3 ~B4 ~B5 ~B6 ~B7 ~B8 ~B9 ~B10", "nothing matches here")
    equal(world:MerchantArrowGlows(), "prev", "matches before")
end)

test("leaves the buyback tab alone", function(world)
    Open(world, { "A1", "A2", "A3" })
    world:SearchMerchant("a2")
    world:SelectMerchantTab(2)
    expect(not world:MerchantSearchBox():IsShown(), "search box hidden")
    equal(world:MerchantSlots(), "A1 A2 A3", "nothing dimmed")

    world:SelectMerchantTab(1)
    expect(world:MerchantSearchBox():IsShown(), "search box back")
    equal(world:MerchantSlots(), "~A1 A2 ~A3", "search kept")
end)

test("matches item names that load late", function(world)
    world.unloadedItems.A2 = true
    Open(world, { "A1", "A2", "A3" })
    world:SearchMerchant("a2")
    equal(world:MerchantSlots(), "~A1 ~A2 ~A3", "no name yet")

    world:LoadItem("A2")
    equal(world:MerchantSlots(), "~A1 A2 ~A3", "name loaded")
end)

test("starts each visit with an empty search", function(world)
    Open(world, { "A1", "A2", "A3" })
    world:SearchMerchant("a2")
    world:CloseMerchant()
    world:OpenMerchant()
    equal(world:MerchantSearchBox():GetText(), "", "search box cleared")
    equal(world:MerchantSlots(), "A1 A2 A3", "nothing dimmed")
end)

test("turning the search box off removes the search", function(world)
    WithThreePages(world)
    Open(world)
    world:SearchMerchant("1")
    world:Setting("inventory.merchant.search"):SetValue(false)
    expect(not world:MerchantSearchBox():IsShown(), "search box hidden")
    equal(world:MerchantSearchBox():GetText(), "", "search box cleared")
    equal(world:MerchantSlots(), "A1 A2 A3 A4 A5 A6 A7 A8 A9 A10", "nothing dimmed")
    equal(world:MerchantArrowGlows(), "", "no arrow lit")

    world:Setting("inventory.merchant.search"):SetValue(true)
    expect(world:MerchantSearchBox():IsShown(), "search box back")
end)

test("turning the merchant feature off removes the search", function(world)
    Open(world, { "A1", "A2", "A3" })
    world:SearchMerchant("a2")
    world:Setting("inventory.merchant.enabled"):SetValue(false)
    expect(not world:MerchantSearchBox():IsShown(), "search box hidden")
    equal(world:MerchantSlots(), "A1 A2 A3", "nothing dimmed")
end)
