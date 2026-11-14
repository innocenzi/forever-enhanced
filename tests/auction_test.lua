-- Auction house prices: the full scan, recorded browse and search results, and
-- the tooltip lines. The fake bag holds G1 G2 - GJUNK, the bank B1 - B2(20);
-- items are their own IDs. Prices are copper, shown as "120c".

local HOUR = 60 * 60

local function Auction(world)
    return world.ns:GetFeature("inventory", "auction")
end

local function PriceLine(world, price, age)
    if age then
        return world.L["inventory.auction.priceAge"]:format(age, price .. "c")
    end
    return world.L["inventory.auction.price"]:format(price .. "c")
end

local function StackLine(world, count, price)
    return world.L["inventory.auction.stackPrice"]:format(count, price .. "c")
end

-- Tooltip lines compared as one text.
local function same(lines, expected, message)
    equal(table.concat(lines, "\n"), table.concat(expected, "\n"), message)
end

local function Tooltip(world, guid)
    return world:ItemTooltip({ guid = guid, id = guid })
end

-- A chat link or the auction house list: no GUID.
local function LinkTooltip(world, itemID)
    return world:ItemTooltip({ id = itemID })
end

-- Opens the auction house and lets the full scan's list arrive and be read.
local function Scan(world)
    world:OpenAuctionHouse()
    world:Elapse(2)
end

-- Full scan ------------------------------------------------------------------------------------

test("opening the auction house scans every auction and keeps the lowest price per unit", function(world)
    world.auctions = { { "G1", 1, 500 }, { "G1", 1, 300 }, { "B2", 5, 600 }, { "B2", 10, 1000 } }
    Scan(world)
    equal(world.replicateRequests, 1, "one full scan")
    same(Tooltip(world, "G1"), { PriceLine(world, 300) }, "lowest buyout")
    same(Tooltip(world, "B2"), { PriceLine(world, 100) }, "per unit")
    same(Tooltip(world, "G2"), {}, "nothing for an item never listed")
end)

test("the full scan is read a slice per frame and saved once read", function(world)
    Auction(world).Scan.AUCTIONS_PER_FRAME = 2
    world.auctions = { { "G2", 1, 900 }, { "G2", 1, 800 }, { "G2", 1, 700 }, { "G1", 1, 50 }, { "G1", 1, 40 } }
    world:OpenAuctionHouse()
    world:Elapse(2)
    equal(world.replicateReads, 4, "first slice, and the second in the frame after the list arrived")
    same(Tooltip(world, "G1"), {}, "nothing saved before the end")
    world:NextFrame()
    equal(world.replicateReads, 5, "last slice")
    same(Tooltip(world, "G1"), { PriceLine(world, 40) }, "saved")
    same(Tooltip(world, "G2"), { PriceLine(world, 700) }, "saved")
end)

test("the full scan runs at most every 15 minutes", function(world)
    world.auctions = { { "G1", 1, 300 } }
    Scan(world)
    world:CloseAuctionHouse()
    world:Elapse(10 * 60)
    Scan(world)
    equal(world.replicateRequests, 1, "not again within 15 minutes")
    world:CloseAuctionHouse()
    world:Elapse(5 * 60)
    world.auctions = { { "G1", 1, 250 } }
    Scan(world)
    equal(world.replicateRequests, 2, "again after 15 minutes")
    same(Tooltip(world, "G1"), { PriceLine(world, 250) }, "newer price")
end)

test("closing the auction house during a full scan saves nothing", function(world)
    Auction(world).Scan.AUCTIONS_PER_FRAME = 1
    world.auctions = { { "G1", 1, 300 }, { "G1", 1, 200 }, { "G1", 1, 100 } }
    world:OpenAuctionHouse()
    world:Elapse(2)
    world:CloseAuctionHouse()
    world:NextFrame()
    world:NextFrame()
    same(Tooltip(world, "G1"), {}, "nothing saved")
end)

test("a full scan another addon asked for is read too", function(world)
    world:Setting("inventory.auction.scan"):SetValue(false)
    world:OpenAuctionHouse()
    equal(world.replicateRequests, 0, "no scan of ours")
    world:ReceiveReplicateList({ { "G1", 1, 300 } })
    same(Tooltip(world, "G1"), { PriceLine(world, 300) }, "read")
    world:ReceiveReplicateList({ { "G1", 1, 100 } })
    same(Tooltip(world, "G1"), { PriceLine(world, 300) }, "not read again within 15 minutes")
end)

test("the scan is opt-out", function(world)
    world:Setting("inventory.auction.scan"):SetValue(false)
    world.auctions = { { "G1", 1, 300 } }
    Scan(world)
    equal(world.replicateRequests, 0, "no full scan")
    same(Tooltip(world, "G1"), {}, "no price")
end)

-- Browse and search results -----------------------------------------------------------------

test("records the browse results, the lowest of each item ID", function(world)
    world:OpenAuctionHouse()
    world:ReceiveBrowseResults({
        { itemKey = { itemID = "G1", itemLevel = 10 }, minPrice = 400 },
        { itemKey = { itemID = "G1", itemLevel = 12 }, minPrice = 350 },
        { itemKey = { itemID = "G2" }, minPrice = 75 },
        { itemKey = { itemID = 82800, battlePetSpeciesID = 40 }, minPrice = 999 },
    })
    same(Tooltip(world, "G1"), { PriceLine(world, 350) }, "lowest of its item keys")
    same(Tooltip(world, "G2"), { PriceLine(world, 75) }, "G2")
    same(LinkTooltip(world, 82800), {}, "battle pets skipped")
end)

test("records a commodity's search results", function(world)
    world:OpenAuctionHouse()
    world:ReceiveCommodityResults("B2", { { unitPrice = 30, quantity = 50 }, { unitPrice = 35, quantity = 5 } })
    same(Tooltip(world, "B2"), { PriceLine(world, 30) }, "lowest unit price")
end)

test("records an item's search results, per unit", function(world)
    world:OpenAuctionHouse()
    world:ReceiveItemResults({ itemID = "G1" }, {
        { buyoutAmount = 1000, quantity = 4 },
        { buyoutAmount = 300, quantity = 1 },
        { bidAmount = 10, quantity = 1 },
    })
    same(Tooltip(world, "G1"), { PriceLine(world, 250) }, "lowest buyout per unit, bids ignored")
end)

test("newer results replace an older, lower price", function(world)
    world.auctions = { { "G1", 1, 100 } }
    Scan(world)
    world:ReceiveBrowseResults({ { itemKey = { itemID = "G1" }, minPrice = 180 } })
    same(Tooltip(world, "G1"), { PriceLine(world, 180) }, "replaced")
end)

-- Tooltip ----------------------------------------------------------------------------------------

test("shows how old the price is once it is over an hour old", function(world)
    world:OpenAuctionHouse()
    world:ReceiveBrowseResults({ { itemKey = { itemID = "G1" }, minPrice = 120 } })
    world:CloseAuctionHouse()
    world:Elapse(HOUR - 1)
    same(Tooltip(world, "G1"), { PriceLine(world, 120) }, "no age within the hour")
    world:Elapse(2 * HOUR + 1)
    same(Tooltip(world, "G1"), { PriceLine(world, 120, world.L["inventory.auction.hoursAgo"]:format(3)) }, "hours")
    world:Elapse(2 * 24 * HOUR)
    same(Tooltip(world, "G1"), { PriceLine(world, 120, world.L["inventory.auction.daysAgo"]:format(2)) }, "days")
    world:Setting("inventory.auction.age"):SetValue(false)
    same(Tooltip(world, "G1"), { PriceLine(world, 120) }, "no age when disabled")
end)

test("the stack price shows while Shift is held, for stacks only, and can be turned off", function(world)
    world:OpenAuctionHouse()
    world:ReceiveBrowseResults({
        { itemKey = { itemID = "B2" }, minPrice = 10 },
        { itemKey = { itemID = "G1" }, minPrice = 50 },
    })
    same(Tooltip(world, "B2"), { PriceLine(world, 10) }, "unit price only without Shift")
    world:SetShift(true)
    same(Tooltip(world, "B2"), { PriceLine(world, 10), StackLine(world, 20, 200) }, "and the stack with Shift")
    same(Tooltip(world, "G1"), { PriceLine(world, 50) }, "no stack for a single item")
    same(LinkTooltip(world, "B2"), { PriceLine(world, 10) }, "no stack outside bags and bank")
    world:Setting("inventory.auction.stack"):SetValue(false)
    same(Tooltip(world, "B2"), { PriceLine(world, 10) }, "unit price only when disabled")
end)

test("bound items show no price", function(world)
    world:OpenAuctionHouse()
    world:ReceiveBrowseResults({ { itemKey = { itemID = "G1" }, minPrice = 10 } })
    world.bound.G1 = true
    same(Tooltip(world, "G1"), {}, "bound copy")
    same(LinkTooltip(world, "G1"), { PriceLine(world, 10) }, "the link still shows it")
end)

test("prices belong to the realm and faction they were seen in", function(world)
    world:OpenAuctionHouse()
    world:ReceiveBrowseResults({ { itemKey = { itemID = "G1" }, minPrice = 10 } })
    world.player.faction = "Alliance"
    same(Tooltip(world, "G1"), {}, "other faction")
    world.player.faction = "Horde"
    world.player.realm = "Hardcore"
    same(Tooltip(world, "G1"), {}, "other realm")
    world.player.realm = "Forever"
    same(Tooltip(world, "G1"), { PriceLine(world, 10) }, "back")
end)

test("disabling stops the scan, the recording and the tooltip lines", function(world)
    world:OpenAuctionHouse()
    world:ReceiveBrowseResults({ { itemKey = { itemID = "G1" }, minPrice = 10 } })
    world:CloseAuctionHouse()
    world:Setting("inventory.auction.enabled"):SetValue(false)
    same(Tooltip(world, "G1"), {}, "no line")
    world:Elapse(Auction(world).Scan.INTERVAL)
    local requests = world.replicateRequests
    world.auctions = { { "G2", 1, 300 } }
    Scan(world)
    world:ReceiveBrowseResults({ { itemKey = { itemID = "G2" }, minPrice = 20 } })
    equal(world.replicateRequests, requests, "no scan")
    world:CloseAuctionHouse()
    world:Setting("inventory.auction.enabled"):SetValue(true)
    same(Tooltip(world, "G1"), { PriceLine(world, 10) }, "saved price back")
    same(Tooltip(world, "G2"), {}, "nothing recorded while disabled")
end)

test("the price lines come right under the sell price, before other features' lines", function(world)
    world:OpenBank()
    world:NextFrame()
    world:CloseBank()
    world:OpenAuctionHouse()
    world:ReceiveBrowseResults({ { itemKey = { itemID = "B1" }, minPrice = 10 } })
    same(
        Tooltip(world, "B1"),
        { PriceLine(world, 10), world.L["inventory.bank.countLine"]:format(1) },
        "price, then the bank count"
    )
end)
