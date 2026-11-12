-- Item marks: the auction house and bank marks, their menu entries and icons,
-- and one destination per item (junk included).
-- The fake bag starts as: G1 G2 - GJUNK (GJUNK is poor quality); items are their own IDs.

local TEXTS = {
    auction = "inventory.marks.markForAuction",
    bank = "inventory.marks.markForBank",
    junk = "inventory.marks.markAsJunk",
}

local function Entry(world, slot, mark)
    local menu = assert(world:AltRightClick(slot), "item menu opened")
    return world:MenuEntry(menu, world.L[TEXTS[mark]])
end

local function Toggle(world, slot, mark)
    assert(Entry(world, slot, mark), mark .. " entry").select()
end

local function IsMarked(world, slot, mark)
    return Entry(world, slot, mark).isSelected()
end

local function Icon(world, slot)
    local icon
    for _, texture in ipairs(world.textures) do
        local atlas = texture.atlas
        if (atlas == "auctioneer" or atlas == "banker") and texture.owner.parent == world.buttons[slot] then
            icon = texture
        end
    end
    return icon
end

for _, mark in ipairs({ "auction", "bank" }) do
    local Shown = mark == "auction" and "AuctionMark" or "BankMark"

    test(mark .. ": marks every copy of an item", function(world)
        world.itemIDs.G1, world.itemIDs.G2 = "CLOTH", "CLOTH"
        local entry = Entry(world, 1, mark)
        equal(entry.kind, "checkbox", "a checkbox")
        expect(entry.enabled, "entry enabled")
        expect(not entry.isSelected(), "not marked yet")
        expect(not world[Shown](world, 1), "no icon yet")

        entry.select()
        expect(IsMarked(world, 2, mark), "the other copy is marked")
        expect(world[Shown](world, 1) and world[Shown](world, 2), "icon on both copies")
        expect(not world[Shown](world, 4), "no icon on other items")
        equal(world.env.ForeverEnhancedCharacterDB.inventory.marks.destinations.CLOTH, mark, "saved per character")

        Toggle(world, 2, mark)
        expect(not IsMarked(world, 1, mark), "unmarked")
        expect(not world[Shown](world, 1) and not world[Shown](world, 2), "icons hidden")
    end)

    test(mark .. ": the icon sits top-left, where the junk coin goes", function(world)
        Toggle(world, 1, mark)
        equal(assert(Icon(world, 1), "icon drawn").point, "TOPLEFT", "top-left")
    end)

    test(mark .. ": locked items don't show the icon", function(world)
        Toggle(world, 1, mark)
        world:AltClick(1)
        expect(not world[Shown](world, 1), "hidden while locked")
        expect(IsMarked(world, 1, mark), "still marked")

        world:AltClick(1)
        expect(world[Shown](world, 1), "back once unlocked")
    end)

    test(mark .. ": its toggle hides its icons and entry, and keeps the marks", function(world)
        Toggle(world, 1, mark)
        world:Setting("inventory.marks." .. mark):SetValue(false)
        expect(not world[Shown](world, 1), "icon hidden")
        expect(not Entry(world, 1, mark), "no entry")

        world:Setting("inventory.marks." .. mark):SetValue(true)
        expect(world[Shown](world, 1), "icon back")
    end)
end

test("poor items can't be marked, bound items only for the bank", function(world)
    expect(not Entry(world, 4, "auction").enabled, "poor: no auction house")
    expect(not Entry(world, 4, "bank").enabled, "poor: no bank")

    world.bound.G1 = true
    expect(not Entry(world, 1, "auction").enabled, "bound: no auction house")
    expect(Entry(world, 1, "bank").enabled, "bound: bank")
end)

test("an item has one destination: junk, auction house or bank", function(world)
    world:Setting("inventory.marks.junkCoin"):SetValue("always")
    world:Setting("inventory.merchant.enabled"):SetValue(true)
    local function Marked()
        local marked = {}
        for _, mark in ipairs({ "junk", "auction", "bank" }) do
            if IsMarked(world, 1, mark) then
                table.insert(marked, mark)
            end
        end
        return table.concat(marked, " ")
    end

    Toggle(world, 1, "junk")
    Toggle(world, 1, "auction")
    equal(Marked(), "auction", "auction house replaces junk")
    expect(world:AuctionMark(1) and not world:JunkCoin(1), "icon instead of the coin")

    Toggle(world, 1, "bank")
    equal(Marked(), "bank", "bank replaces auction house")
    expect(world:BankMark(1) and not world:AuctionMark(1), "bank icon only")

    Toggle(world, 1, "auction")
    equal(Marked(), "auction", "auction house replaces bank")

    Toggle(world, 1, "junk")
    equal(Marked(), "junk", "junk replaces auction house")
    expect(world:JunkCoin(1) and not world:AuctionMark(1), "coin instead of the icon")

    Toggle(world, 1, "bank")
    equal(Marked(), "bank", "bank replaces junk")

    Toggle(world, 1, "bank")
    equal(Marked(), "", "unmarking leaves none")
end)

test("disabling item marks hides the icons and the entries", function(world)
    Toggle(world, 1, "auction")
    Toggle(world, 2, "bank")
    world:Setting("inventory.marks.enabled"):SetValue(false)
    expect(not world:AuctionMark(1) and not world:BankMark(2), "icons hidden")
    expect(not Entry(world, 1, "auction") and not Entry(world, 1, "bank"), "no entries")

    world:Setting("inventory.marks.enabled"):SetValue(true)
    expect(world:AuctionMark(1) and world:BankMark(2), "icons back")
end)

test("the item menu lists junk, then the auction house, then the bank", function(world)
    world:Setting("inventory.merchant.enabled"):SetValue(true)
    local menu = world:AltRightClick(1)
    equal(menu[4].text, world.L[TEXTS.junk], "junk fourth")
    equal(menu[5].text, world.L[TEXTS.auction], "auction house fifth")
    equal(menu[6].text, world.L[TEXTS.bank], "bank last")
end)

test("Alt Left Click locks by default", function(world)
    world:AltClick(1)
    expect(world.ns:GetFeature("inventory", "locking"):IsGUIDLocked("G1"), "locked")
    expect(not IsMarked(world, 1, "junk"), "not marked")
end)

for _, mark in ipairs({ "junk", "auction", "bank" }) do
    test("Alt Left Click can mark for " .. mark .. " instead of locking", function(world)
        world:Setting("inventory.marks.altClick"):SetValue(mark)
        world:AltClick(1)
        expect(IsMarked(world, 1, mark), "marked")
        expect(not world.ns:GetFeature("inventory", "locking"):IsGUIDLocked("G1"), "not locked")

        world:AltClick(1)
        expect(not IsMarked(world, 1, mark), "unmarked")

        world:AltClick(4)
        expect(not IsMarked(world, 4, mark) or mark == "junk", "poor items can't take the mark")
    end)
end

test("Alt Left Click locks again when its mark is off", function(world)
    world:Setting("inventory.marks.altClick"):SetValue("bank")
    world:Setting("inventory.marks.bank"):SetValue(false)
    world:AltClick(1)
    expect(world.ns:GetFeature("inventory", "locking"):IsGUIDLocked("G1"), "locked")
end)

test("a locked item tells how to unlock it", function(world)
    world:AltClick(1)
    world:Setting("inventory.marks.altClick"):SetValue("junk")
    C_Container.PickupContainerItem(0, 2)
    world:NextFrame()
    local shield = world:Shield(1)
    shield.scripts.OnReceiveDrag(shield)
    equal(world.errors[#world.errors], world.L["inventory.locking.isLockedMenu"], "from the item menu")
end)
