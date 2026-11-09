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
    equal(world:Bag(), "G1 - G2 GJUNK", "bag (locked items home, G2 keeps its sorted slot)")
    equal(world.pickups, 2, "pickups (a single swap)")
    equal(world.cursor, nil, "cursor")
end)

test("moves the displaced item to the locked item's sorted slot", function(world)
    world:AltClick(1)
    Sort(world, { 4, 2, 3, 1 }) -- GJUNK G2 - G1
    equal(world:Bag(), "G1 G2 - GJUNK", "bag")
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
