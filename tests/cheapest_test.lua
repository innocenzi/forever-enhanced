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
    SetPrices(world, { G1 = 10, G2 = 20, G3 = 30, GJUNK = 50 })
    world.bags[0][3] = "G3"
    world.bags[1], world.bagSizes[1], world.bagFamilies[1] = {}, 2, 1
    Enable(world, true)
    equal(Marked(world), "1", "full despite the quiver's free slots")

    world.bagFamilies[1] = 0
    BagsChanged(world)
    equal(Marked(world), "", "a regular bag's free slots count")
end)

-- The reagent bag (container 5) holds R1 (1c) and a free slot; the backpack is full.
local function WithReagentBag(world)
    SetPrices(world, { G1 = 10, G2 = 20, G3 = 30, GJUNK = 50, R1 = 1 })
    world.bags[0][3] = "G3"
    world.bags[5], world.bagSizes[5] = { "R1" }, 2
end

local function Collect(world)
    local guids = {}
    for guid in pairs(world.ns:GetFeature("inventory", "cheapest").Value:Collect()) do
        table.insert(guids, guid)
    end
    table.sort(guids)
    return table.concat(guids, " ")
end

test("the reagent bag counts like the other bags when not excluded", function(world)
    WithReagentBag(world)
    Enable(world, true)
    equal(Marked(world), "1", "full despite its free slot, its cheaper item skipped")
    equal(Collect(world), "G1", "only bag items")
    world:Setting("inventory.cheapest.excludeReagentBag"):SetValue(false)
    equal(Marked(world), "", "its free slot counts")

    world.bags[5][2] = "R2"
    world.sellPrices.R2 = 5
    BagsChanged(world)
    equal(Collect(world), "R1", "its items count")
    equal(Marked(world), "", "nothing in the backpack")
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

test("an item is valued once its data loads", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    world.unloadedItems.G1 = true
    Enable(world, false)
    equal(Marked(world), "2", "the cheapest item with its data loaded")

    world:LoadItem("G1")
    world:NextFrame()
    equal(Marked(world), "1", "the item whose data loaded")
end)

test("Blizzard redrawing unchanged bags doesn't look for the lowest value items again", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    local Value = world.ns:GetFeature("inventory", "cheapest").Value
    local collect, collects = Value.Collect, 0
    Value.Collect = function(...)
        collects = collects + 1
        return collect(...)
    end

    world:Fire("UNIT_QUEST_LOG_CHANGED", "player")
    world:Fire("CURSOR_CHANGED")
    equal(collects, 0, "no scan")
    equal(Marked(world), "1", "still marked")

    world.bags[0][3] = "G3"
    world:BagsChanged(0)
    world:NextFrame()
    equal(collects, 1, "one scan for a bag change")
end)

-- Ignored items: Tough Jerky (food, inventory.food's data) and Linen Cloth (a
-- reagent of Linen Bandage, First Aid) in the backpack's free slot, worth 1c.
local TOUGH_JERKY = 117
local LINEN_CLOTH = 2589
local LINEN_BANDAGE = 3275
local FIRST_AID = 129

local function Carry(world, itemID)
    world.itemIDs.G3 = itemID
    world.sellPrices[itemID] = 1
    world.bags[0][3] = "G3"
    BagsChanged(world)
end

-- Checks or unchecks an option of the "ignore" dropdown.
local function Ignore(world, option, checked)
    world:CheckSettingOption("inventory.cheapest.ignore", world.L["inventory.cheapest.ignore." .. option], checked)
end

local function LearnLinenBandage(world)
    world.professions = { nil, nil, { skillLine = FIRST_AID } }
    world.learnedRecipes[LINEN_BANDAGE] = true
    world:ShowTradeSkillList({ LINEN_BANDAGE })
end

test("food is ignored with the food feature off", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    world:Setting("inventory.food.enabled"):SetValue(false)
    Enable(world, false)
    Carry(world, TOUGH_JERKY)
    equal(Marked(world), "1", "still ignored")
end)

test("reagents of known recipes are ignored by default", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    Carry(world, LINEN_CLOTH)
    equal(Marked(world), "3", "no recipe known: marked")

    LearnLinenBandage(world)
    BagsChanged(world)
    equal(Marked(world), "1", "a known recipe uses it")

    Ignore(world, "reagents", false)
    equal(Marked(world), "3", "counts once not ignored")
end)

test("learning a recipe or dropping its profession updates the marks", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    Carry(world, LINEN_CLOTH)
    world.professions = { nil, nil, { skillLine = FIRST_AID } }
    world:Fire("NEW_RECIPE_LEARNED", LINEN_BANDAGE)
    world:NextFrame()
    equal(Marked(world), "1", "learned")

    world.professions = {}
    world:Fire("SKILL_LINES_CHANGED")
    world:NextFrame()
    equal(Marked(world), "3", "profession dropped")
end)

test("reagents count while reagent uses is off", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    Carry(world, LINEN_CLOTH)
    LearnLinenBandage(world)
    world:Setting("professions.reagents.enabled"):SetValue(false)
    BagsChanged(world)
    equal(Marked(world), "3", "no known recipes without the feature")
end)

-- Each of the other "ignore" options, checked by default: the item in slot 3
-- (worth 1c) is left unmarked until its option is unchecked.
local function ExpectIgnored(world, key, setup)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    setup()
    BagsChanged(world)
    world:NextFrame()
    equal(Marked(world), "1", key .. ": ignored")
    Ignore(world, key, false)
    equal(Marked(world), "3", key .. ": marked once not ignored")
end

local MINING_PICK = 2901
local RUNE_OF_TELEPORTATION = 17031 -- a mage reagent (the player is a mage)
local ANKH = 17030 -- a shaman reagent

test("profession tools are ignored", function(world)
    ExpectIgnored(world, "tools", function()
        Carry(world, MINING_PICK)
    end)
end)

test("fishing poles are tools", function(world)
    world.weaponSubclasses.POLE = Enum.ItemWeaponSubclass.Fishingpole
    ExpectIgnored(world, "tools", function()
        Carry(world, "POLE")
    end)
end)

test("reagents of the player's class spells are ignored", function(world)
    ExpectIgnored(world, "classReagents", function()
        Carry(world, RUNE_OF_TELEPORTATION)
    end)
end)

test("ammo is ignored with class reagents", function(world)
    world.itemClasses.ARROW = Enum.ItemClass.Projectile
    ExpectIgnored(world, "classReagents", function()
        Carry(world, "ARROW")
    end)
end)

test("reagents of other classes' spells are marked", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    Carry(world, ANKH)
    equal(Marked(world), "3", "a shaman's Ankh")
end)

test("items on the action bars are ignored", function(world)
    ExpectIgnored(world, "actionBars", function()
        Carry(world, "POTION")
        world:PlaceItem(1, "POTION")
    end)
end)

test("placing an item on the action bars updates the marks", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    Carry(world, "POTION")
    equal(Marked(world), "3", "not on a bar")
    world:PlaceItem(1, "POTION")
    world:NextFrame()
    equal(Marked(world), "1", "placed")
end)

test("items a quest asks for are ignored", function(world)
    ExpectIgnored(world, "questItems", function()
        Carry(world, "WING")
        world.questLog = { { questID = 1, title = "Bat Wings", objectives = { world:Objective("G3", 10, 3) } } }
        world:Fire("QUEST_LOG_UPDATE")
    end)
end)

test("a quest entering the log updates the marks", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    Carry(world, "WING")
    equal(Marked(world), "3", "no quest")
    world.questLog = { { questID = 1, title = "Bat Wings", objectives = { world:Objective("G3", 10, 3) } } }
    world:Fire("QUEST_LOG_UPDATE")
    world:NextFrame()
    equal(Marked(world), "1", "a quest asks for it")
end)

test("quest items count while quest objectives are off", function(world)
    world:Setting("quests.helpers.enabled"):SetValue(false)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    Carry(world, "WING")
    world.questLog = { { questID = 1, title = "Bat Wings", objectives = { world:Objective("G3", 10, 3) } } }
    world:Fire("QUEST_LOG_UPDATE")
    BagsChanged(world)
    equal(Marked(world), "3", "no quest index without quest helpers")
end)

test("items marked for the auction house, bank or mail are ignored", function(world)
    local Marks = world.ns:GetFeature("inventory", "marks")
    for _, destination in ipairs({ "auction", "bank", "mail" }) do
        ExpectIgnored(world, "marks", function()
            Carry(world, "LOOT")
            Marks:ToggleDestination("LOOT", destination)
        end)
        Marks:ToggleDestination("LOOT", destination)
        Ignore(world, "marks", true)
    end
end)

test("items marked as junk are marked", function(world)
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    Carry(world, "LOOT")
    world.ns:GetFeature("inventory", "marks"):ToggleDestination("LOOT", "junk")
    equal(Marked(world), "3", "junk")
end)

test("items with a note are ignored", function(world)
    ExpectIgnored(world, "notes", function()
        Carry(world, "LOOT")
        world.ns:GetFeature("inventory", "marks"):SetNote("G3", "keep")
    end)
end)

test("writing or erasing a note updates the marks", function(world)
    local Marks = world.ns:GetFeature("inventory", "marks")
    SetPrices(world, { G1 = 10, G2 = 20, GJUNK = 50 })
    Enable(world, false)
    Carry(world, "LOOT")
    Marks:SetNote("G3", "keep")
    equal(Marked(world), "1", "written")
    Marks:SetNote("G3", " ")
    equal(Marked(world), "3", "erased")
end)
