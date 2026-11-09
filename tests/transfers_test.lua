-- Bank Transfers: Deposit / Withdraw, onto partial stacks or all matching items.
-- Linen and wool stack to 20. Each test sets its own bags (container 0) and
-- bank (tabs 6 and 7, of 4 and 2 slots), opens the bank, then uses the menus.

local function Transfers(world)
    return world.ns:GetFeature("inventory", "transfers")
end

-- items: { guid = { itemID, count } }
local function Setup(world, bags, bank, tab2, items)
    world.maxStacks = { linen = 20, wool = 20, peacebloom = 20 }
    world.counts = {}
    for guid, item in pairs(items) do
        world.itemIDs[guid] = item[1]
        world.counts[guid] = item[2]
    end
    world.bags[0], world.bags[6], world.bags[7] = bags, bank, tab2
    world:OpenBank()
end

-- Picks a mode in the Deposit or Withdraw menu and lets the transfer finish.
local function Transfer(world, direction, mode)
    local menu = world:TransferMenu(direction)
    menu[mode == "stacks" and 1 or 2].callback()
    world:Elapse(5)
end

test("deposit onto existing stacks only tops off the bank's partial stacks", function(world)
    Setup(world, { "L1", "W1", "G1" }, { "L3", nil, "L4" }, {}, {
        L1 = { "linen", 15 },
        W1 = { "wool", 5 },
        L3 = { "linen", 12 },
        L4 = { "linen", 20 },
    })
    Transfer(world, "deposit", "stacks")
    equal(world:Slots(6), "L3(20) - L4(20) -", "bank partial stack filled")
    equal(world:Slots(0), "L1(7) W1(5) G1 -", "remainder kept, other items stay")
    equal(world:Slots(7), "- -", "no empty slot used")
end)

test("deposit all matching items fills partial stacks, then empty slots", function(world)
    Setup(world, { "L1", "W1", "G1" }, { "L3", nil, "L4" }, {}, {
        L1 = { "linen", 15 },
        W1 = { "wool", 5 },
        L3 = { "linen", 12 },
        L4 = { "linen", 20 },
    })
    Transfer(world, "deposit", "all")
    equal(world:Slots(6), "L3(20) L1(7) L4(20) -", "bank")
    equal(world:Slots(0), "- W1(5) G1 -", "items the bank doesn't hold stay")
end)

test("withdraw tops off the bags from the smallest bank stacks", function(world)
    Setup(world, { "L1" }, { "L4", "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
        L4 = { "linen", 20 },
    })
    Transfer(world, "withdraw", "stacks")
    equal(world:Slots(0), "L1(20) - - -", "bags")
    equal(world:Slots(6), "L4(20) L3(7) - -", "bank")
end)

test("several stacks fill one partial stack over rounds", function(world)
    Setup(world, { "L1", "L2" }, { "L3" }, {}, {
        L1 = { "linen", 3 },
        L2 = { "linen", 4 },
        L3 = { "linen", 12 },
    })
    world.pickups = 0
    Transfer(world, "deposit", "stacks")
    equal(world:Slots(6), "L3(19) - - -", "bank")
    equal(world:Slots(0), "- - - -", "bags")
    equal(world.pickups, 4, "two moves")
end)

test("locked items never move", function(world)
    Setup(world, { "L1" }, { "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
    })
    world:AltClick(1)
    Transfer(world, "deposit", "all")
    equal(world:Slots(0), "L1(15) - - -", "locked stack stays")
    equal(world:Slots(6), "L3(12) - - -", "bank unchanged")
end)

test("special bags only receive the items they hold", function(world)
    Setup(world, { "L1", "H1" }, { "L3", "Z1", "Z2", "Z3" }, { "H2" }, {
        L1 = { "linen", 7 },
        H1 = { "peacebloom", 5 },
        L3 = { "linen", 20 },
        H2 = { "peacebloom", 20 },
    })
    world.itemFamilies.peacebloom = 32
    world.bagFamilies[7] = 32 -- an herb bag
    Transfer(world, "deposit", "all")
    equal(world:Slots(7), "H2(20) H1(5)", "herbs in the herb bag")
    equal(world:Slots(0), "L1(7) - - -", "linen stays out of the herb bag")
end)

test("closing the bank stops a transfer", function(world)
    Setup(world, { "L1" }, { "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
    })
    world.pickups = 0
    world:TransferMenu("deposit")[1].callback()
    expect(Transfers(world):IsRunning(), "running")
    world:CloseBank()
    expect(not Transfers(world):IsRunning(), "stopped")
    world:Elapse(5)
    equal(world.pickups, 0, "nothing moved")
end)

test("menus offer both modes, disabled while a transfer runs", function(world)
    Setup(world, { "L1" }, { "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
    })
    local menu = world:TransferMenu("withdraw")
    equal(menu[1].text, world.L["inventory.transfers.stacks"], "first mode")
    equal(menu[2].text, world.L["inventory.transfers.all"], "second mode")
    expect(menu[1].enabled and menu[2].enabled, "enabled")

    menu[1].callback()
    menu = world:TransferMenu("deposit")
    expect(not menu[1].enabled and not menu[2].enabled, "disabled while running")
    world:Elapse(5)
    expect(world:TransferMenu("deposit")[1].enabled, "enabled again")
end)

test("does nothing away from the bank", function(world)
    Transfers(world):Run("deposit", "all")
    expect(not Transfers(world):IsRunning(), "not started")
end)

test("turning the feature off hides the buttons and stops a transfer", function(world)
    Setup(world, { "L1" }, { "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
    })
    expect(world:TransferButton("deposit").shown, "shown")
    world:TransferMenu("deposit")[1].callback()
    world:Setting("inventory.transfers.enabled"):SetValue(false)
    expect(not Transfers(world):IsRunning(), "stopped")
    expect(not world:TransferButton("deposit").shown, "deposit hidden")
    expect(not world:TransferButton("withdraw").shown, "withdraw hidden")

    world:Setting("inventory.transfers.enabled"):SetValue(true)
    expect(world:TransferButton("withdraw").shown, "back")
end)
