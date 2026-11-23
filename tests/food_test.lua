-- Food on action bars: an action slot holding food or drink gets the best one of
-- its kind in the bags (the generated data.lua), out of combat and with an
-- empty cursor. The player is level 12.

local TOUGH_JERKY = 117 -- food 17, level 1, 1 copper
local SHINY_RED_APPLE = 4536 -- food 17, level 1, 1 copper
local DALARAN_SHARP = 414 -- food 58, level 5, 6 copper
local DWARVEN_MILD = 422 -- food 115, level 15
local CONJURED_MUFFIN = 5349 -- food 17, level 1, conjured
local DRY_PORK_RIBS = 2687 -- food 58, level 5, Well Fed
local REFRESHING_SPRING_WATER = 159 -- drink 42, level 1
local ICE_COLD_MILK = 1179 -- drink 104, level 5
local SENGGIN_ROOT = 3448 -- food 70 and drink 70, level 0
local BACKSTAB = 53

local function Enable(world)
    world:Setting("inventory.food.enabled"):SetValue(true)
    world:NextFrame()
end

-- The backpack holds only `items` (item ID -> count), then the update runs.
local function Carry(world, items)
    local itemIDs = {}
    for itemID in pairs(items) do
        table.insert(itemIDs, itemID)
    end
    table.sort(itemIDs)
    world.bags[0] = {}
    for slot, itemID in ipairs(itemIDs) do
        local guid = "F" .. itemID
        world.itemIDs[guid] = itemID
        world.counts[guid] = items[itemID]
        world.bags[0][slot] = guid
    end
    world:BagsChanged(0)
    world:NextFrame()
end

local function Place(world, slot, itemID)
    world:PlaceItem(slot, itemID)
    world:NextFrame()
end

test("off by default", function(world)
    Carry(world, { [DALARAN_SHARP] = 3 })
    Place(world, 1, TOUGH_JERKY)
    equal(world:ActionItem(1), TOUGH_JERKY)
end)

test("puts the best food in the bags on a slot holding food", function(world)
    Enable(world)
    Carry(world, { [TOUGH_JERKY] = 5, [DALARAN_SHARP] = 3 })
    Place(world, 1, TOUGH_JERKY)
    equal(world:ActionItem(1), DALARAN_SHARP)
    equal(world.cursorAction, nil, "cursor emptied")
    equal(world:ActionItem(2), nil, "other slots untouched")
end)

test("keeps food slots on food and drink slots on drink", function(world)
    Enable(world)
    Place(world, 1, TOUGH_JERKY)
    Place(world, 2, REFRESHING_SPRING_WATER)
    Carry(world, { [DALARAN_SHARP] = 1, [ICE_COLD_MILK] = 1 })
    equal(world:ActionItem(1), DALARAN_SHARP)
    equal(world:ActionItem(2), ICE_COLD_MILK)
end)

test("fills every slot of a kind", function(world)
    Enable(world)
    Place(world, 1, TOUGH_JERKY)
    Place(world, 61, SHINY_RED_APPLE)
    Carry(world, { [DALARAN_SHARP] = 1 })
    equal(world:ActionItem(1), DALARAN_SHARP)
    equal(world:ActionItem(61), DALARAN_SHARP)
end)

test("waits for the player's level", function(world)
    Enable(world)
    Place(world, 1, TOUGH_JERKY)
    Carry(world, { [TOUGH_JERKY] = 1, [DWARVEN_MILD] = 1 })
    equal(world:ActionItem(1), TOUGH_JERKY, "level 15 food at level 12")
    world:LevelUp(15)
    world:NextFrame()
    equal(world:ActionItem(1), DWARVEN_MILD)
end)

test("puts conjured food first", function(world)
    Enable(world)
    Place(world, 1, TOUGH_JERKY)
    Carry(world, { [DALARAN_SHARP] = 1, [CONJURED_MUFFIN] = 1 })
    equal(world:ActionItem(1), CONJURED_MUFFIN)
end)

test("prefers what the setting picks", function(world)
    Enable(world)
    Place(world, 1, TOUGH_JERKY)
    Carry(world, { [TOUGH_JERKY] = 10, [DALARAN_SHARP] = 2 })
    equal(world:ActionItem(1), DALARAN_SHARP, "highest level")

    world:Setting("inventory.food.pick"):SetValue("cheapest")
    world:NextFrame()
    equal(world:ActionItem(1), TOUGH_JERKY, "cheapest")

    world:Setting("inventory.food.pick"):SetValue("smallest")
    world:NextFrame()
    equal(world:ActionItem(1), DALARAN_SHARP, "smallest stack")

    world:Setting("inventory.food.pick"):SetValue("largest")
    world:NextFrame()
    equal(world:ActionItem(1), TOUGH_JERKY, "largest stack")
end)

test("keeps the last item once the bags run out", function(world)
    Enable(world)
    Carry(world, { [DALARAN_SHARP] = 1 })
    Place(world, 1, TOUGH_JERKY)
    Carry(world, {})
    equal(world:ActionItem(1), DALARAN_SHARP)

    Carry(world, { [TOUGH_JERKY] = 4 })
    equal(world:ActionItem(1), TOUGH_JERKY, "refilled")
end)

test("leaves buff food alone unless it counts", function(world)
    Enable(world)
    Place(world, 1, DRY_PORK_RIBS)
    Place(world, 2, TOUGH_JERKY)
    Carry(world, { [TOUGH_JERKY] = 1, [DALARAN_SHARP] = 1, [DRY_PORK_RIBS] = 1 })
    equal(world:ActionItem(1), DRY_PORK_RIBS, "buff food slot left alone")
    equal(world:ActionItem(2), DALARAN_SHARP, "buff food never picked")

    Carry(world, { [TOUGH_JERKY] = 1, [DRY_PORK_RIBS] = 1 })
    world:Setting("inventory.food.buffFood"):SetValue(true)
    world:NextFrame()
    equal(world:ActionItem(1), DRY_PORK_RIBS)
    equal(world:ActionItem(2), DRY_PORK_RIBS, "buff food picked")
end)

test("waits for combat to end", function(world)
    Enable(world)
    Place(world, 1, TOUGH_JERKY)
    world:EnterCombat()
    Carry(world, { [DALARAN_SHARP] = 1 })
    equal(world:ActionItem(1), TOUGH_JERKY)
    world:LeaveCombat()
    world:NextFrame()
    equal(world:ActionItem(1), DALARAN_SHARP)
end)

test("waits for the cursor to be empty", function(world)
    Enable(world)
    Place(world, 1, TOUGH_JERKY)
    world:PickupSpell(BACKSTAB)
    Carry(world, { [DALARAN_SHARP] = 1 })
    equal(world:ActionItem(1), TOUGH_JERKY)
    equal(world.cursorAction, BACKSTAB, "the player's spell still on the cursor")
    ClearCursor()
    world:NextFrame()
    equal(world:ActionItem(1), DALARAN_SHARP)
end)

test("moves with the food", function(world)
    Enable(world)
    Carry(world, { [TOUGH_JERKY] = 1, [DALARAN_SHARP] = 1 })
    Place(world, 1, DALARAN_SHARP)
    PickupAction(1)
    PlaceAction(5)
    world:NextFrame()
    equal(world:ActionItem(1), nil, "no longer a food slot")
    equal(world:ActionItem(5), DALARAN_SHARP)

    world:PickupSpell(BACKSTAB)
    PlaceAction(5)
    world:NextFrame()
    equal(world.cursorAction, DALARAN_SHARP, "the food picked off the bar")
    ClearCursor()
    world:NextFrame()
    equal(world.actions[5], BACKSTAB)
    equal(world:ActionItem(1), nil, "nothing filled back in")
end)

test("a slot holding food and drink keeps its kind", function(world)
    Enable(world)
    Place(world, 2, REFRESHING_SPRING_WATER)
    Carry(world, { [REFRESHING_SPRING_WATER] = 1, [SENGGIN_ROOT] = 1 })
    equal(world:ActionItem(2), SENGGIN_ROOT, "best drink")

    Carry(world, { [DALARAN_SHARP] = 1, [ICE_COLD_MILK] = 1 })
    equal(world:ActionItem(2), ICE_COLD_MILK, "still a drink slot")
end)

test("leaves the bars alone while disabled", function(world)
    Enable(world)
    Place(world, 1, TOUGH_JERKY)
    world:Setting("inventory.food.enabled"):SetValue(false)
    world:NextFrame()
    Carry(world, { [DALARAN_SHARP] = 1 })
    equal(world:ActionItem(1), TOUGH_JERKY)
end)
