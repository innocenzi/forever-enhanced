-- Keep locked items in place when sorting. The fake server applies a requested
-- sort when the test calls world:ApplySort(permutation), then the test fires the
-- bag update that the real server sends. Swaps are confirmed by the fake server.

local function Sort(world, permutation)
    C_Container.SortBags()
    world:ApplySort(permutation)
    world:Fire("BAG_UPDATE_DELAYED")
    world:Elapse(5)
end

test("puts locked items back after a sort", function(world)
    world:AltClick(1)
    world:AltClick(4)
    world.pickups = 0
    Sort(world, { 4, 3, 2, 1 }) -- GJUNK - G2 G1
    equal(world:Bag(), "G1 G2 - GJUNK", "bag (locked items home, G2 closes up)")
    equal(world.pickups, 4, "pickups (a swap and a move, one round)")
    equal(world.cursor, nil, "cursor")
end)

test("closes the gaps locked items leave going home", function(world)
    world.bags[0] = { "X1", "X2", nil, "G4" }
    world:AltClick(4)
    Sort(world, { 4, 1, 2, 3 }) -- G4 X1 X2 -
    equal(world:Bag(), "X1 X2 - G4", "bag")
end)

test("closes the gaps of a sort filling from the end", function(world)
    world.bags[0] = { "G1", nil, "X3", "X4" }
    world:AltClick(1)
    Sort(world, { 2, 4, 3, 1 }) -- - X4 X3 G1
    equal(world:Bag(), "G1 - X4 X3", "bag")
end)

test("leaves bags ignored by cleanups alone", function(world)
    world.bags[0] = { "X1", "X2", nil, "G4" }
    world.bagFlags[0] = { [Enum.BagSlotFlags.DisableAutoSort] = true }
    world:AltClick(4)
    Sort(world, { 4, 1, 2, 3 }) -- G4 X1 X2 -
    equal(world:Bag(), "- X1 X2 G4", "bag (only the locked item moves)")
end)

local function Reserve(world, slot)
    world.ns:RefreshItemButtons()
    local menu = world:AltRightClick(slot)
    world:MenuEntry(menu, world.L["inventory.slots.reserve"]).select()
    world:CloseContextMenu()
end

test("leaves reserved slots to their item", function(world)
    world.bags[0] = { "X1", nil, "F3", "G4" }
    world.itemIDs.F3 = "FOOD"
    Reserve(world, 3)
    world:AltClick(4)
    Sort(world, { 4, 1, 3, 2 }) -- G4 X1 F3 -
    equal(world:Bag(), "X1 - F3 G4", "bag")
end)

test("leaves the stack a reserved slot takes to it", function(world)
    world.bags[0] = { "F1", nil, "X3", "G4" }
    world.itemIDs.F1 = "FOOD"
    Reserve(world, 1)
    world:AltClick(4)
    Sort(world, { 3, 4, 1, 2 }) -- X3 G4 F1 -
    equal(world:Bag(), "F1 X3 - G4", "bag")
end)

test("fills the slot of a locked item of a reserved slot's item", function(world)
    world.bags[0] = { nil, "F2", "X3", "G4" }
    world.itemIDs.F2, world.itemIDs.G4 = "FOOD", "FOOD"
    Reserve(world, 2)
    world:AltClick(4)
    Sort(world, { 4, 2, 3, 1 }) -- G4 F2 X3 -
    equal(world:Bag(), "X3 F2 - G4", "bag")
end)

test("moves what the sort put in a locked item's reserved slot", function(world)
    world.bags[0] = { "G1", nil, "X3", "X4" }
    world.itemIDs.G1 = "FOOD"
    Reserve(world, 1)
    world:AltClick(1)
    Sort(world, { 3, 4, 1, 2 }) -- X3 X4 G1 -
    equal(world:Bag(), "G1 X3 X4 -", "bag")
end)

test("sends independent swaps together, on the sort's bag update", function(world)
    world.bags[0] = { "G1", "G2", "X3", "X4" }
    world:AltClick(1)
    world:AltClick(2)
    local sortedAt = world.now
    Sort(world, { 3, 4, 1, 2 }) -- X3 X4 G1 G2
    equal(world:Bag(), "G1 G2 X3 X4", "bag")
    equal(#world.swapTimes, 2, "swaps")
    equal(world.swapTimes[1], world.swapTimes[2], "second swap time (same round)")
    equal(world.swapTimes[1], sortedAt, "restore start (no added delay)")
end)

test("chains rounds on the server confirmation", function(world)
    world.bags[0] = { "G1", "X2", "X3", "GJUNK" }
    world:AltClick(1)
    world:AltClick(4)
    Sort(world, { 2, 4, 3, 1 }) -- X2 GJUNK X3 G1: both swaps need slot 1 or 4
    equal(world:Bag(), "G1 X2 X3 GJUNK", "bag")
    equal(#world.swapTimes, 2, "swaps")
    equal(world.swapTimes[2] - world.swapTimes[1], world.SERVER_CONFIRM_SECONDS, "gap between rounds")
end)

test("puts a chain of locked items back in two rounds", function(world)
    world.bags[0] = { "G1", "G2", "G3", "X4" }
    world:AltClick(1)
    world:AltClick(2)
    world:AltClick(3)
    -- X4 G1 G2 G3: each locked item's home holds the one before it, so one
    -- swap home per item needs a round per item.
    Sort(world, { 4, 1, 2, 3 })
    equal(world:Bag(), "G1 G2 G3 X4", "bag")
    equal(#world.swapTimes, 3, "swaps")
    equal(world.swapTimes[3] - world.swapTimes[1], world.SERVER_CONFIRM_SECONDS, "rounds (two)")
end)

test("puts locked items that took each other's slots back", function(world)
    world.bags[0] = { "G1", "G2", "G3", "X4" }
    world:AltClick(1)
    world:AltClick(2)
    world:AltClick(3)
    Sort(world, { 3, 1, 2, 4 }) -- G3 G1 G2 X4
    equal(world:Bag(), "G1 G2 G3 X4", "bag")
    equal(#world.swapTimes, 2, "swaps")
    equal(world.swapTimes[2] - world.swapTimes[1], world.SERVER_CONFIRM_SECONDS, "rounds (two)")
end)

test("waits for the bag update, not lock changes", function(world)
    world:AltClick(1)
    world.pickups = 0
    C_Container.SortBags()
    world:ApplySort({ 4, 3, 2, 1 })
    world:Fire("ITEM_LOCK_CHANGED", 0, 1) -- slots freed before positions update
    world:Elapse(0.29)
    equal(world.pickups, 0, "pickups before the bag update")
    world:Fire("BAG_UPDATE_DELAYED")
    world:Elapse(5)
    equal(world.bags[0][1], "G1", "G1 back home")
end)

test("ends quietly when the sort moved nothing", function(world)
    world:AltClick(1)
    world.pickups = 0
    C_Container.SortBags()
    world:ApplySort({ 1, 2, 3, 4 })
    world:Fire("ITEM_LOCK_CHANGED", 0, 1)
    world:Elapse(5)
    equal(world.pickups, 0, "pickups")
    equal(world:Bag(), "G1 G2 - GJUNK", "bag")
end)

test("leaves the sort alone when the option is off", function(world)
    world:AltClick(1)
    world:Setting("inventory.locking.keepInPlace"):SetValue(false)
    world.pickups = 0
    Sort(world, { 4, 3, 2, 1 })
    equal(world.pickups, 0, "pickups")
    equal(world:Bag(), "GJUNK - G2 G1", "bag")
end)
