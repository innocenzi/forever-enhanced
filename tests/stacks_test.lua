-- Item stacks: while Shift is held over an item, the bag and bank slots not
-- holding it are dimmed. The fake bag starts as: G1 G2 - GJUNK, the first bank
-- tab as: B1 - B2 -; world.itemIDs makes several GUIDs stacks of one item.

-- Whether our dimming shows over the button.
local function IsDimmed(world, button)
    for _, texture in ipairs(world.textures) do
        local owner = texture.owner
        if
            owner.parent == button
            and owner.shown
            and texture.color
            and texture.color[1] == 0
            and texture.color[4] == 0.8
        then
            return true
        end
    end
    return false
end

-- The dimmed slots of `buttons`: "2 3".
local function Dimmed(world, buttons)
    local slots = {}
    for slot, button in ipairs(buttons or world.buttons) do
        if IsDimmed(world, button) then
            table.insert(slots, slot)
        end
    end
    return table.concat(slots, " ")
end

-- Shift held over an item showing in the tooltip.
local function HoldShiftOver(world, itemID)
    world:ShowItemOn(GameTooltip, { id = itemID }, {})
    world:SetShift(true)
end

test("on by default, only while Shift is held over an item", function(world)
    world:ShowItemOn(GameTooltip, { id = "G1" }, {})
    world:NextFrame()
    equal(Dimmed(world), "", "no Shift")

    world:ShowItemOn(GameTooltip, nil)
    world:SetShift(true)
    world:NextFrame()
    equal(Dimmed(world), "", "no item tooltip")
end)

test("dims every slot but the item's stacks, empty ones included", function(world)
    world.bags[0][3] = "G3"
    world.itemIDs.G3 = "G1"
    world:BagsChanged(0)

    HoldShiftOver(world, "G1")
    equal(Dimmed(world), "2 4", "both G1 stacks lit")

    world:SetShift(false)
    equal(Dimmed(world), "", "Shift released")
end)

test("follows the tooltip while Shift is held", function(world)
    HoldShiftOver(world, "G1")
    equal(Dimmed(world), "2 3 4", "G1")

    world:ShowItemOn(GameTooltip, { id = "G2" }, {})
    world:NextFrame()
    equal(Dimmed(world), "1 3 4", "moved to G2")

    world:ShowItemOn(GameTooltip, { id = "EQUIPPED" }, {})
    world:NextFrame()
    equal(Dimmed(world), "1 2 3 4", "an item the bags don't hold")

    world:ShowItemOn(GameTooltip, nil)
    world:NextFrame()
    equal(Dimmed(world), "", "tooltip gone")
end)

test("a bag change while Shift is held dims the new items", function(world)
    HoldShiftOver(world, "G1")
    world.bags[0][3] = "G3"
    world.itemIDs.G3 = "G1"
    world.bags[0][1] = nil
    world:BagsChanged(0)
    equal(Dimmed(world), "1 2 4", "the moved stack stays lit")
end)

test("lights the item's stacks in the bank", function(world)
    world.itemIDs.B2 = "G1"
    world:OpenBank()
    HoldShiftOver(world, "G1")
    equal(Dimmed(world), "2 3 4", "bags")
    equal(Dimmed(world, world.bankButtons), "1 2 4", "bank")
end)

test("a secret item ID dims nothing", function(world)
    world.secretValues.G1 = true
    HoldShiftOver(world, "G1")
    world:NextFrame()
    equal(Dimmed(world), "", "nothing dimmed")
end)

test("turning it off undims and stops following Shift", function(world)
    HoldShiftOver(world, "G1")
    world:Setting("inventory.stacks.enabled"):SetValue(false)
    equal(Dimmed(world), "", "undimmed")

    world:SetShift(false)
    HoldShiftOver(world, "G2")
    world:NextFrame()
    equal(Dimmed(world), "", "off")
end)
