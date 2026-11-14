-- Lowest value items: which bag items are marked, when, and how.
-- The fake bag starts as: G1 G2 - GJUNK (GJUNK is poor quality); items are
-- their own IDs, sell prices in copper (world.sellPrices).

local GLOW_ATLAS = "bags-glow-white"
local ICON_ATLASES = { ["common-icon-redx"] = "cross", ["coin-copper"] = "coin" }

-- The mark a bag button shows: "glow", "cross", "coin", or nil.
local function Mark(world, slot)
    for _, texture in ipairs(world.textures) do
        local owner = texture.owner
        if owner.parent == world.buttons[slot] and owner.shown and texture.shown then
            if texture.atlas == GLOW_ATLAS and owner.animationGroups[1].playing then
                return "glow"
            elseif ICON_ATLASES[texture.atlas] then
                return ICON_ATLASES[texture.atlas]
            end
        end
    end
end

-- The marked bag slots: "1 4".
local function Marked(world)
    local slots = {}
    for slot = 1, #world.buttons do
        if Mark(world, slot) then
            table.insert(slots, slot)
        end
    end
    return table.concat(slots, " ")
end

local function Enable(world, onlyWhenFull)
    world:Setting("inventory.cheapest.onlyWhenFull"):SetValue(onlyWhenFull)
    world:Setting("inventory.cheapest.enabled"):SetValue(true)
end

local function BagsChanged(world)
    world:Fire("BAG_UPDATE_DELAYED")
end

local function SetPrices(world, prices)
    for itemID, price in pairs(prices) do
        world.sellPrices[itemID] = price
    end
end

test("off by default", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 5 })
    world.bags[0][3] = "G3"
    BagsChanged(world)
    equal(Marked(world), "", "nothing marked")
end)

test("marks the lowest value item only while the bags are full", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, G3 = 30, GJUNK = 5 })
    Enable(world, true)
    equal(Marked(world), "", "a slot is free")

    world.bags[0][3] = "G3"
    BagsChanged(world)
    equal(Marked(world), "4", "full: the cheapest item")

    world.bags[0][2] = nil
    BagsChanged(world)
    equal(Marked(world), "", "a slot freed")
end)

test("marks with free slots when not only when full", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    equal(Marked(world), "1", "the cheapest item")

    world:Setting("inventory.cheapest.onlyWhenFull"):SetValue(true)
    equal(Marked(world), "", "hidden once only when full")
end)

test("a stack is worth its count", function(world)
    SetPrices(world, { G1 = 10, G2 = 3, GJUNK = 50 })
    world.counts.G2 = 5
    Enable(world, false)
    equal(Marked(world), "1", "10 is less than 5 x 3")
end)

test("the auction price counts for unbound items", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    world.ns:GetFeature("inventory", "auction").Store:SetPrices({ G1 = 100 })
    Enable(world, false)
    equal(Marked(world), "2", "G1 is worth its auction price")

    world.bound.G1 = true
    BagsChanged(world)
    equal(Marked(world), "1", "bound: the sell price only")

    world.bound.G1 = nil
    world:Setting("inventory.auction.enabled"):SetValue(false)
    BagsChanged(world)
    equal(Marked(world), "1", "auction prices off: the sell price only")
end)

test("every item tied for the lowest value is marked", function(world)
    SetPrices(world, { G1 = 10, G2 = 10, GJUNK = 50 })
    Enable(world, false)
    equal(Marked(world), "1 2", "both")
end)

test("locked items and items without value are left out", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    world:AltClick(1)
    equal(Marked(world), "2", "locked item skipped")

    world.noValue.G2 = true
    BagsChanged(world)
    equal(Marked(world), "4", "no sell price skipped")
end)

test("bank items are left out", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50, B1 = 1 })
    Enable(world, false)
    world:OpenBank()
    equal(Marked(world), "1", "the cheapest bag item")
end)

test("free slots of special bags don't count", function(world)
    -- The fake client's only bag stands in for a quiver.
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    world.bagFamilies[0] = 1
    Enable(world, true)
    equal(Marked(world), "1", "full despite the quiver's free slot")

    world.bagFamilies[0] = 0
    BagsChanged(world)
    equal(Marked(world), "", "a regular bag's free slots count")
end)

test("the glow is red by default, the other indicators are bottom-left icons", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    equal(Mark(world, 1), "glow", "glow by default")
    for _, texture in ipairs(world.textures) do
        if texture.atlas == GLOW_ATLAS and texture.owner.parent == world.buttons[1] then
            local r, g = unpack(texture.tint)
            expect(r == 1 and g < 0.5, "tinted red")
        end
    end

    for _, indicator in ipairs({ "cross", "coin" }) do
        world:Setting("inventory.cheapest.indicator"):SetValue(indicator)
        equal(Mark(world, 1), indicator, indicator)
        for _, texture in ipairs(world.textures) do
            if ICON_ATLASES[texture.atlas] and texture.owner.parent == world.buttons[1] then
                equal(texture.point, "BOTTOMLEFT", indicator .. " bottom-left")
            end
        end
    end
end)

test("disabling the feature hides the marks", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    world:Setting("inventory.cheapest.enabled"):SetValue(false)
    equal(Marked(world), "", "hidden")

    world:Setting("inventory.cheapest.enabled"):SetValue(true)
    equal(Marked(world), "1", "back")
end)
