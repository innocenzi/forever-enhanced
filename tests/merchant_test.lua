-- Merchant: auto sell junk and auto repair when a merchant opens.
-- The fake bag starts as: G1 G2 - GJUNK (GJUNK is poor quality).

-- Auto sell junk and auto repair are opt-in.
local function Enable(world)
    world:Setting("inventory.merchant.autoSellJunk"):SetValue(true)
    world:Setting("inventory.merchant.autoRepair"):SetValue(true)
end

-- Bag G1 JUNK - GJUNK: two junk items worth 10 and 5 copper.
local function WithJunk(world)
    world.bags[0][2] = "JUNK"
    world.quality.JUNK = 0
    world.sellPrices.JUNK = 10
    world.sellPrices.GJUNK = 5
end

-- The last chat message is the locale string `key` formatted with `...`.
local function ExpectAnnounced(world, key, ...)
    local message = world.L[key]:format(...)
    expect(world.prints[#world.prints]:find(message, 1, true), "chat message " .. key)
end

test("neither sells nor repairs by default", function(world)
    WithJunk(world)
    world.money, world.repairCost = 100, 30
    world:OpenMerchant()
    equal(#world.sold, 0, "sold")
    equal(#world.repairs, 0, "repairs")
end)

test("sells all junk with Blizzard's Sell All Junk and announces it", function(world)
    Enable(world)
    WithJunk(world)
    world:OpenMerchant()
    equal(world.sellAllJunkCalls, 1, "Sell All Junk calls")
    equal(world:Bag(), "G1 - - -", "bag")
    ExpectAnnounced(world, "inventory.merchant.sold", 2, GetMoneyString(15, true))

    world:Elapse(1)
    equal(world.money, 15, "money credited")
end)

test("keeps locked junk and sells the rest", function(world)
    Enable(world)
    WithJunk(world)
    world:AltClick(4)
    world:OpenMerchant()
    equal(world.sellAllJunkCalls, 0, "Sell All Junk calls")
    equal(table.concat(world.sold, " "), "JUNK", "sold")
    equal(world:Bag(), "G1 - - GJUNK", "bag")
end)

test("sells nothing when all junk is locked or excluded", function(world)
    Enable(world)
    world:AltClick(4)
    world:OpenMerchant()
    world:CloseMerchant()
    world:AltClick(4)
    world.excludedFromJunkSell[0] = true
    world:OpenMerchant()
    equal(#world.sold, 0, "sold")
    equal(world.sellAllJunkCalls, 0, "Sell All Junk calls")
    equal(#world.prints, 0, "chat messages")
end)

test("stays quiet when announcing is off", function(world)
    Enable(world)
    WithJunk(world)
    world.money, world.repairCost = 100, 30
    world:Setting("inventory.merchant.announce"):SetValue(false)
    world:OpenMerchant()
    equal(#world.sold, 2, "sold")
    equal(#world.repairs, 1, "repairs")
    equal(#world.prints, 0, "chat messages")
end)

test("repairs with the player's gold", function(world)
    Enable(world)
    world.money, world.repairCost = 100, 30
    world:OpenMerchant()
    equal(table.concat(world.repairs, ","), "player 30", "repairs")
    equal(world.money, 70, "money")
    ExpectAnnounced(world, "inventory.merchant.repaired", GetMoneyString(30, true))
end)

test("skips merchants that can't repair and gear in full repair", function(world)
    Enable(world)
    world.money, world.repairCost = 100, 0
    world:OpenMerchant()
    world:CloseMerchant()
    world.repairCost, world.merchantCanRepair = 30, false
    world:OpenMerchant()
    equal(#world.repairs, 0, "repairs")
    equal(#world.errors, 0, "errors")
end)

test("uses guild funds first when chosen and allowed", function(world)
    Enable(world)
    world.money, world.repairCost = 100, 30
    world:Setting("inventory.merchant.guildFunds"):SetValue(true)
    world.guildRepair = { allowed = true, withdrawLimit = -1 }
    world:OpenMerchant()
    equal(table.concat(world.repairs, ","), "guild 30", "unlimited withdrawals")
    ExpectAnnounced(world, "inventory.merchant.repairedGuild", GetMoneyString(30, true))
    world:CloseMerchant()

    world.repairCost, world.guildRepair.withdrawLimit = 30, 20
    world:OpenMerchant()
    equal(table.concat(world.repairs, ","), "guild 30,player 30", "over the withdraw limit")
    world:CloseMerchant()

    world.repairCost, world.guildRepair = 30, { allowed = false, withdrawLimit = -1 }
    world:OpenMerchant()
    equal(table.concat(world.repairs, ","), "guild 30,player 30,player 30", "guild repair not allowed")
end)

test("ignores guild funds with the player's gold chosen", function(world)
    Enable(world)
    world.money, world.repairCost = 100, 30
    world.guildRepair = { allowed = true, withdrawLimit = -1 }
    world:OpenMerchant()
    equal(table.concat(world.repairs, ","), "player 30", "repairs")
end)

test("waits for the junk money to repair", function(world)
    Enable(world)
    WithJunk(world)
    world.money, world.repairCost = 10, 20
    world:OpenMerchant()
    equal(#world.repairs, 0, "repairs before the sale lands")
    equal(#world.errors, 0, "errors")

    world:Elapse(1)
    equal(table.concat(world.repairs, ","), "player 20", "repairs")
    equal(world.money, 5, "money")
end)

test("doesn't repair once the merchant closes", function(world)
    Enable(world)
    WithJunk(world)
    world.money, world.repairCost = 10, 20
    world:OpenMerchant()
    world:CloseMerchant()
    world:Elapse(1)
    equal(#world.repairs, 0, "repairs")
end)

test("says so when the gold doesn't cover the repair", function(world)
    Enable(world)
    WithJunk(world)
    world.money, world.repairCost = 10, 100
    world:OpenMerchant()
    equal(#world.repairs, 0, "repairs")
    equal(world.errors[#world.errors], world.L["inventory.merchant.notEnoughMoney"], "error")
    world:Elapse(1)
    equal(#world.repairs, 0, "repairs after the sale")
    equal(#world.errors, 1, "errors")
end)

test("each action has its own setting", function(world)
    Enable(world)
    WithJunk(world)
    world.money, world.repairCost = 100, 30
    world:Setting("inventory.merchant.autoSellJunk"):SetValue(false)
    world:OpenMerchant()
    equal(#world.sold, 0, "sold with selling off")
    equal(#world.repairs, 1, "repaired")
    world:CloseMerchant()

    world.repairCost = 30
    world:Setting("inventory.merchant.autoSellJunk"):SetValue(true)
    world:Setting("inventory.merchant.autoRepair"):SetValue(false)
    world:OpenMerchant()
    equal(#world.sold, 2, "sold")
    equal(#world.repairs, 1, "repairs with repairing off")
end)

test("turning the feature off stops it", function(world)
    Enable(world)
    WithJunk(world)
    world.money, world.repairCost = 100, 30
    world:Setting("inventory.merchant.enabled"):SetValue(false)
    world:OpenMerchant()
    equal(#world.sold, 0, "sold")
    equal(#world.repairs, 0, "repairs")
end)

test("sells item by item when Sell All Junk is unavailable", function(world)
    Enable(world)
    WithJunk(world)
    world.sellAllJunkEnabled = false
    world:OpenMerchant()
    equal(world.sellAllJunkCalls, 0, "Sell All Junk calls")
    equal(table.concat(world.sold, " "), "JUNK GJUNK", "sold")
end)

test("drops a waiting repair when Auto Repair is turned off", function(world)
    Enable(world)
    WithJunk(world)
    world.money, world.repairCost = 10, 20
    world:OpenMerchant()
    world:Setting("inventory.merchant.autoRepair"):SetValue(false)
    world:Elapse(1)
    equal(#world.repairs, 0, "repairs")
end)

-- Repair All glow: the default threshold is 50%.

-- Equips a full item in slot 1 and one at `current` / 100 in slot 5, with gear to repair.
local function WithWornGear(world, current)
    world.durability[1] = { 100, 100 }
    world.durability[5] = { current, 100 }
    world.money, world.repairCost = 100, 30
end

test("glows on Repair All once an item's durability reaches the threshold", function(world)
    WithWornGear(world, 51)
    world:OpenMerchant()
    expect(not world:IsRepairAllGlowing(), "no glow above the threshold")
    world:CloseMerchant()

    world.durability[5][1] = 50
    world:OpenMerchant()
    expect(world:IsRepairAllGlowing(), "glow at the threshold")
end)

test("follows durability and threshold changes at the merchant", function(world)
    WithWornGear(world, 40)
    world:OpenMerchant()
    expect(world:IsRepairAllGlowing(), "glow")

    world:Setting("inventory.merchant.repairGlowThreshold"):SetValue(30)
    expect(not world:IsRepairAllGlowing(), "no glow under a lower threshold")

    world.durability[5][1] = 20
    world:Fire("UPDATE_INVENTORY_DURABILITY")
    expect(world:IsRepairAllGlowing(), "glow once worn further")
end)

test("stops glowing when the glow or the feature is turned off", function(world)
    WithWornGear(world, 10)
    world:OpenMerchant()
    world:Setting("inventory.merchant.repairGlow"):SetValue(false)
    expect(not world:IsRepairAllGlowing(), "no glow with the setting off")
    world:Setting("inventory.merchant.repairGlow"):SetValue(true)
    expect(world:IsRepairAllGlowing(), "glow back")
    world:Setting("inventory.merchant.enabled"):SetValue(false)
    expect(not world:IsRepairAllGlowing(), "no glow with the feature off")
end)
