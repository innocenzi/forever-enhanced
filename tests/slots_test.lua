-- Reserved slots: reserving from the item menu, the faded icon and menu of an
-- empty reserved slot, and reserved items going back to their slot.
-- The bag starts as: F1 G2 - GJUNK, F1 a food (item FOOD) reserved in slot 1;
-- F2 is more of that food. Moves are confirmed by the fake server.

local FOOD_ICON = 133950 -- a file ID, like the client's icons

local function Slots(world)
    return world.ns:GetFeature("inventory", "slots")
end

local function Reserve(world, slot)
    local menu = world:AltRightClick(slot)
    world:MenuEntry(menu, world.L["inventory.slots.reserve"]).select()
    world:CloseContextMenu()
end

local function WithFood(world)
    world.bags[0][1] = "F1"
    world.itemIDs.F1, world.itemIDs.F2 = "FOOD", "FOOD"
    world.itemIcons.FOOD = FOOD_ICON
    world.ns:RefreshItemButtons()
    Reserve(world, 1)
end

-- Items land in or leave the bag, and the server reports it.
local function Change(world, bagID, slots)
    for slot, guid in pairs(slots) do
        world.bags[bagID][slot] = guid or nil
    end
    world:BagsChanged(bagID)
    world:Elapse(5)
end

local function EatFood(world)
    Change(world, 0, { [1] = false })
end

-- The faded icon drawn over a bag button, if shown.
local function Ghost(world, slot)
    for _, texture in ipairs(world.textures) do
        local owner = texture.owner
        if texture.desaturated and owner.parent == world.buttons[slot] and owner.shown then
            return texture
        end
    end
end

test("reserves the slot from the item menu, per character", function(world)
    WithFood(world)
    equal(Slots(world):GetReservedItem(0, 1), "FOOD", "reserved item")
    equal(world.env.ForeverEnhancedCharacterDB.inventory.slots.reservations[0][1], "FOOD", "saved per character")
    local entry = world:MenuEntry(world:AltRightClick(1), world.L["inventory.slots.reserve"])
    expect(entry.isSelected(), "checked")
end)

test("an empty reserved slot shows its item, its tooltip and a menu freeing it", function(world)
    WithFood(world)
    expect(not Ghost(world, 1), "no icon while the item is there")
    EatFood(world)
    local ghost = Ghost(world, 1)
    expect(ghost, "faded icon")
    equal(ghost.texture, FOOD_ICON, "icon")

    world:SetAlt(true)
    expect(world:IsShielded(1), "shield with Alt")
    expect(not world:IsShielded(3), "no shield on other empty slots")
    local shield = world:Shield(1)
    shield.scripts.OnEnter(shield)
    equal(world.tooltip, "FOOD", "tooltip")
    world:SetAlt(false)

    local menu = world:AltRightClick(1)
    equal(menu[1].text, "FOOD", "title")
    equal(#menu, 2, "only the reservation entry")
    local entry = world:MenuEntry(menu, world.L["inventory.slots.reserve"])
    expect(entry.isSelected(), "checked")
    entry.select()
    equal(Slots(world):GetReservedItem(0, 1), nil, "freed")
    expect(not Ghost(world, 1), "icon hidden")
end)

test("Alt Left Click on an empty reserved slot does nothing", function(world)
    WithFood(world)
    EatFood(world)
    world:AltClick(1)
    equal(#world.errors, 0, "errors")
    equal(Slots(world):GetReservedItem(0, 1), "FOOD", "still reserved")
end)

test("the icon follows its setting", function(world)
    WithFood(world)
    EatFood(world)
    world:Setting("inventory.slots.showIcon"):SetValue(false)
    expect(not Ghost(world, 1), "icon hidden")
    world:SetAlt(true)
    expect(world:IsShielded(1), "the slot keeps its menu")
    world:SetAlt(false)
end)

test("the item coming back goes to its slot", function(world)
    WithFood(world)
    EatFood(world)
    Change(world, 0, { [3] = "F2" })
    equal(world:Bag(), "F2 G2 - GJUNK", "bag")
    expect(not Ghost(world, 1), "icon hidden")
end)

test("the item coming back swaps out what took its slot", function(world)
    WithFood(world)
    EatFood(world)
    Change(world, 0, { [1] = "X1" })
    Change(world, 0, { [3] = "F2" })
    equal(world:Bag(), "F2 G2 X1 GJUNK", "bag")
end)

test("moving the item out by hand is left alone", function(world)
    WithFood(world)
    C_Container.PickupContainerItem(0, 1)
    C_Container.PickupContainerItem(0, 3)
    world:Elapse(5)
    equal(world:Bag(), "- G2 F1 GJUNK", "bag")
end)

test("a locked item keeps the reserved slot", function(world)
    WithFood(world)
    EatFood(world)
    Change(world, 0, { [1] = "X1" })
    world:AltClick(1)
    Change(world, 0, { [3] = "F2" })
    equal(world:Bag(), "X1 G2 F2 GJUNK", "bag")
end)

test("a locked stack of the item stays where it is", function(world)
    world.bags[0][3] = "F2"
    WithFood(world)
    world:AltClick(3)
    EatFood(world)
    -- More of the food stacks onto the locked F2.
    world.counts.F2 = 2
    Change(world, 0, {})
    equal(world:Bag(), "- G2 F2 GJUNK", "bag")
end)

test("a cleanup puts reserved items back", function(world)
    WithFood(world)
    C_Container.SortBags()
    world:ApplySort({ 4, 3, 2, 1 }) -- GJUNK - G2 F1
    world:Fire("BAG_UPDATE_DELAYED")
    world:Elapse(5)
    equal(world:Bag(), "F1 - G2 GJUNK", "bag")
end)

test("a bank slot fills when the item is deposited, not from the bags", function(world)
    world.itemIDs.F1, world.itemIDs.F2 = "FOOD", "FOOD"
    world:OpenBank()
    Slots(world):ToggleReservation(ItemLocation:CreateFromBagAndSlot(6, 2), "FOOD")
    Change(world, 0, { [3] = "F2" })
    equal(world:Slots(6), "B1 - B2(20) -", "bank after looting")
    Change(world, 6, { [4] = "F1" })
    equal(world:Slots(6), "B1 F1 B2(20) -", "bank after depositing")
end)

test("disabling hides the icons and stops moving items", function(world)
    WithFood(world)
    EatFood(world)
    world:Setting("inventory.slots.enabled"):SetValue(false)
    expect(not Ghost(world, 1), "icon hidden")
    Change(world, 0, { [3] = "F2" })
    equal(world:Bag(), "- G2 F2 GJUNK", "bag")
end)
