-- Bank transfers: Deposit / Withdraw, onto partial stacks or all matching items.
-- Every stackable item here stacks to 20. Each test sets its own bags (container 0) and
-- bank (tabs 6 and 7, of 4 and 2 slots), opens the bank, then uses the menus.

local function Transfers(world)
    return world.ns:GetFeature("inventory", "bank").Transfers
end

-- items: { guid = { itemID, count } }
local function Setup(world, bags, bank, tab2, items)
    world.maxStacks = { linen = 20, wool = 20, peacebloom = 20, potion = 20 }
    world.counts = {}
    for guid, item in pairs(items) do
        world.itemIDs[guid] = item[1]
        world.counts[guid] = item[2]
    end
    world.bags[0], world.bags[6], world.bags[7] = bags, bank, tab2
    world:OpenBank()
end

-- The entry of a mode in the Deposit or Withdraw menu, if listed.
local function Entry(world, direction, mode)
    return world:MenuEntry(world:TransferMenu(direction), world.L["inventory.bank.transfers." .. mode])
end

-- Picks a mode in the Deposit or Withdraw menu and lets the transfer finish.
local function Transfer(world, direction, mode)
    assert(Entry(world, direction, mode), mode .. " entry").callback()
    world:Elapse(5)
end

-- Marks the bag item at `slot` for the bank, from the item menu.
local function MarkForBank(world, slot)
    local menu = assert(world:AltRightClick(slot), "item menu opened")
    assert(world:MenuEntry(menu, world.L["inventory.marks.markForBank"]), "bank entry").select()
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
    world:NextFrame()
    expect(not world:TransferButton("deposit"):IsEnabled(), "nothing to deposit")
    Transfers(world):Run("deposit", "all")
    world:Elapse(5)
    equal(world:Slots(0), "L1(15) - - -", "locked stack stays")
    equal(world:Slots(6), "L3(12) - - -", "bank unchanged")
end)

test("locked stacks get filled and stay locked", function(world)
    Setup(world, { "P1" }, { "P2", "P3" }, {}, {
        P1 = { "potion", 1 },
        P2 = { "potion", 5 },
        P3 = { "potion", 20 },
    })
    world:AltClick(1)
    Transfer(world, "withdraw", "stacks")
    equal(world:Slots(0), "P1(20) - - -", "locked stack filled")
    equal(world:Slots(6), "- P3(6) - -", "bank")
    expect(world.ns:GetFeature("inventory", "locking"):IsGUIDLocked("P1"), "still locked")
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
    Entry(world, "deposit", "stacks").callback()
    expect(Transfers(world):IsRunning(), "running")
    world:CloseBank()
    expect(not Transfers(world):IsRunning(), "stopped")
    world:Elapse(5)
    equal(world.pickups, 0, "nothing moved")
end)

test("a transfer waits for the end of combat", function(world)
    Setup(world, { "L1" }, { "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
    })
    world.pickups = 0
    world.inCombat = true
    Entry(world, "deposit", "stacks").callback()
    world:Elapse(30)
    equal(world.pickups, 0, "nothing moved in combat")
    expect(Transfers(world):IsRunning(), "still running after a long fight")

    world.inCombat = false
    world:Fire("PLAYER_REGEN_ENABLED")
    world:Elapse(5)
    equal(world:Slots(6), "L3(20) - - -", "bank")
    equal(world:Slots(0), "L1(7) - - -", "bags")
end)

test("a blocked move puts the item back and stops the transfer", function(world)
    Setup(world, { "L1", "L2" }, { "L3" }, {}, {
        L1 = { "linen", 3 },
        L2 = { "linen", 4 },
        L3 = { "linen", 12 },
    })
    world.blockDrops = true
    Entry(world, "deposit", "stacks").callback()
    world:Elapse(0)
    expect(not CursorHasItem(), "nothing left on the cursor")
    expect(not Transfers(world):IsRunning(), "stopped")
    equal(world:Slots(0), "L1(3) L2(4) - -", "bags unchanged")
end)

test("Deposit lists all matching items first, Withdraw existing stacks first", function(world)
    Setup(world, { "L1" }, { "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
    })
    local deposit = world:TransferMenu("deposit")
    equal(deposit[1].text, world.L["inventory.bank.transfers.all"], "deposit first mode")
    equal(deposit[2].text, world.L["inventory.bank.transfers.stacks"], "deposit second mode")
    local withdraw = world:TransferMenu("withdraw")
    equal(withdraw[1].text, world.L["inventory.bank.transfers.stacks"], "withdraw first mode")
    equal(withdraw[2].text, world.L["inventory.bank.transfers.all"], "withdraw second mode")
end)

test("menu entries that would move nothing are disabled", function(world)
    Setup(world, { "L1", "W1" }, { "L3" }, {}, {
        L1 = { "linen", 20 },
        W1 = { "wool", 5 },
        L3 = { "linen", 20 },
    })
    expect(not Entry(world, "deposit", "stacks").enabled, "no partial bank stack to fill")
    expect(Entry(world, "deposit", "all").enabled, "linen can go to an empty bank slot")
    expect(not Entry(world, "withdraw", "stacks").enabled, "no partial bag stack to fill")
    expect(Entry(world, "withdraw", "all").enabled, "linen can go to an empty bag slot")
    expect(not Entry(world, "deposit", "marked").enabled, "nothing marked")

    MarkForBank(world, 2)
    expect(Entry(world, "deposit", "marked").enabled, "marked wool")

    Transfer(world, "deposit", "all")
    expect(not Entry(world, "deposit", "all").enabled, "every matching item deposited")
end)

test("a button with nothing to move is disabled, its tooltip saying so", function(world)
    Setup(world, { "W1" }, { "L3" }, {}, {
        W1 = { "wool", 5 },
        L3 = { "linen", 20 },
    })
    local deposit, withdraw = world:TransferButton("deposit"), world:TransferButton("withdraw")
    expect(not deposit:IsEnabled() and not withdraw:IsEnabled(), "nothing to move either way")
    local text, lines = world:TransferTooltip("deposit")
    equal(text, world.L["inventory.bank.transfers.deposit.tooltip"], "tooltip on a disabled button")
    equal(lines[1], world.L["inventory.bank.transfers.deposit.nothing"], "deposit says why")
    lines = select(2, world:TransferTooltip("withdraw"))
    equal(lines[1], world.L["inventory.bank.transfers.withdraw.nothing"], "withdraw says why")

    MarkForBank(world, 1)
    world:NextFrame()
    expect(deposit:IsEnabled(), "a marked item to deposit")
    lines = select(2, world:TransferTooltip("deposit"))
    equal(#lines, 0, "no reason once enabled")

    world:AltClick(1)
    world:NextFrame()
    expect(not deposit:IsEnabled(), "locked items don't move")
    world:AltClick(1)
    world:NextFrame()
    expect(deposit:IsEnabled(), "unlocked")

    Transfer(world, "deposit", "marked")
    expect(not deposit:IsEnabled(), "disabled once deposited")
end)

test("menus are disabled while a transfer runs", function(world)
    Setup(world, { "L1" }, { "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
    })
    local menu = world:TransferMenu("withdraw")
    expect(menu[1].enabled and menu[2].enabled, "enabled")

    menu[1].callback()
    menu = world:TransferMenu("deposit")
    expect(not menu[1].enabled and not menu[2].enabled, "disabled while running")
    world:Elapse(5)
    expect(world:TransferMenu("deposit")[1].enabled, "enabled again")
end)

test("deposit marked items moves the items marked for the bank", function(world)
    Setup(world, { "L1", "W1", "P1", "L2" }, { "L3", nil, "L4" }, {}, {
        L1 = { "linen", 15 },
        W1 = { "wool", 5 },
        P1 = { "potion", 3 },
        L2 = { "linen", 4 },
        L3 = { "linen", 12 },
        L4 = { "linen", 20 },
    })
    MarkForBank(world, 1)
    MarkForBank(world, 2)
    Transfer(world, "deposit", "marked")
    equal(world:Slots(6), "L3(16) L1(15) L4(20) W1(5)", "smallest stack onto the partial one, then empty slots")
    equal(world:Slots(0), "- - P1(3) -", "unmarked items stay")
end)

test("deposit marked items leaves locked items", function(world)
    Setup(world, { "W1", "W2" }, {}, {}, {
        W1 = { "wool", 5 },
        W2 = { "wool", 6 },
    })
    MarkForBank(world, 1)
    world:AltClick(2)
    Transfer(world, "deposit", "marked")
    equal(world:Slots(0), "- W2(6) - -", "locked stack stays")
    equal(world:Slots(6), "W1(5) - - -", "bank")
end)

test("marked items are only offered by Deposit, while the bank mark is on", function(world)
    Setup(world, { "L1" }, { "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
    })
    local marked = world.L["inventory.bank.transfers.marked"]
    equal(world:TransferMenu("deposit")[3].text, marked, "third deposit entry")
    expect(not world:MenuEntry(world:TransferMenu("withdraw"), marked), "not in withdraw")

    world:Setting("inventory.marks.bank"):SetValue(false)
    expect(not world:MenuEntry(world:TransferMenu("deposit"), marked), "gone with the bank mark")
end)

test("does nothing away from the bank", function(world)
    Transfers(world):Run("deposit", "all")
    expect(not Transfers(world):IsRunning(), "not started")
end)

test("turning transfers off hides the buttons and stops a transfer", function(world)
    Setup(world, { "L1" }, { "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
    })
    expect(world:TransferButton("deposit").shown, "shown")
    Entry(world, "deposit", "stacks").callback()
    world:Setting("inventory.bank.transfers"):SetValue(false)
    expect(not Transfers(world):IsRunning(), "stopped")
    expect(not world:TransferButton("deposit").shown, "deposit hidden")
    expect(not world:TransferButton("withdraw").shown, "withdraw hidden")

    world:Setting("inventory.bank.transfers"):SetValue(true)
    expect(world:TransferButton("withdraw").shown, "back")
end)

test("turning the bank feature off hides the buttons too", function(world)
    Setup(world, { "L1" }, { "L3" }, {}, {
        L1 = { "linen", 15 },
        L3 = { "linen", 12 },
    })
    world:Setting("inventory.bank.enabled"):SetValue(false)
    expect(not world:TransferButton("deposit").shown, "hidden")
    world:Setting("inventory.bank.enabled"):SetValue(true)
    expect(world:TransferButton("deposit").shown, "back")
end)
