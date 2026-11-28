-- Diverted crates: the component lines of a Waylaid Crate's Use text get a
-- mark, from the bags and this character's saved bank, by item ID (the
-- generated data.lua). Waylaid Crate: Journeyman Textiles (248688) takes 20
-- Wool Cloth, 40 Silk Cloth or 20 Medium Leather.

local CRATE = 248688
local WOOL, SILK, LEATHER = 2592, 4306, 2319

-- The Use line as measured in game (frFR): one tooltip line, the components
-- after "\n", in the item quality color from the end of the description, with
-- a no-break space after the count. The enUS text is modelled the same way.
local DESCRIPTIONS = {
    enUS = "Use: Fill the crate with any bundle from the following list:",
    frFR = "Utiliser : Vous remplissez la caisse avec n’importe quel pack de la liste suivante :",
}
local COMPONENTS = {
    enUS = { "- 20\194\160Wool Cloth", "- 40\194\160Silk Cloth", "- 20\194\160Medium Leather" },
    frFR = {
        "- 20\194\160unités d’étoffe de laine",
        "- 40\194\160unités d’étoffe de soie",
        "- 20\194\160unités de cuir moyen",
    },
}

local function Marks(world)
    return world.ns:GetFeature("inventory", "crates").Tooltip.MARKS
end

-- The tooltip of item `id` showing the crate's text, components replaced by
-- `components` when given: its name, the Use line, the required level. Returns
-- the Use line's lines (the description, then the components) and the last line.
local function CrateTooltip(world, id, components)
    local useLine = DESCRIPTIONS[TEST_LOCALE]
        .. "|cnIQ1:\n"
        .. table.concat(components or COMPONENTS[TEST_LOCALE], "\n")
    local lines = world:ItemTooltip({
        id = id or CRATE,
        lines = { { leftText = "Waylaid Crate" }, { leftText = useLine }, { leftText = "Requires Level 10" } },
    })
    local useLines = {}
    for text in (lines[2] .. "\n"):gmatch("(.-)\n") do
        table.insert(useLines, text)
    end
    return useLines, lines[3]
end

-- The component `index` (1-3) after `mark`, or unmarked without one.
local function Component(world, index, mark)
    local text = COMPONENTS[TEST_LOCALE][index]
    return mark and Marks(world)[mark] .. " " .. text or text
end

-- Puts a stack of `count` of `itemID` in the bags' slot `slot`.
local function InBags(world, slot, itemID, count)
    local guid = "BAG" .. slot
    world.bags[0][slot] = guid
    world.itemIDs[guid], world.counts[guid] = itemID, count
end

-- Opens the bank holding these stacks ({ itemID, count }), lets the save run, closes it.
local function SaveBank(world, stacks)
    world.bags[6], world.bags[7] = {}, {}
    for index, stack in ipairs(stacks) do
        local guid = "BANK" .. index
        world.bags[6][index] = guid
        world.itemIDs[guid], world.counts[guid] = stack[1], stack[2]
    end
    world:OpenBank()
    world:NextFrame()
    world:CloseBank()
end

test("marks the components the bags hold enough of", function(world)
    world.bags[0] = {}
    InBags(world, 1, WOOL, 20)
    InBags(world, 2, SILK, 39)
    local useLines, last = CrateTooltip(world)
    equal(useLines[1], DESCRIPTIONS[TEST_LOCALE], "the description is untouched")
    equal(useLines[2], Component(world, 1, "bags"), "enough wool")
    equal(useLines[3], Component(world, 2, "missing"), "silk short by one")
    equal(useLines[4], Component(world, 3, "missing"), "no leather")
    equal(last, "Requires Level 10", "lines after the Use line are untouched")
end)

test("shows the banker when the saved bank makes up the difference", function(world)
    world.bags[0] = {}
    SaveBank(world, { { SILK, 30 }, { LEATHER, 5 } })
    InBags(world, 1, SILK, 10)
    InBags(world, 2, LEATHER, 10)
    local useLines = CrateTooltip(world)
    equal(useLines[3], Component(world, 2, "bank"), "10 in the bags + 30 in the bank")
    equal(useLines[4], Component(world, 3, "missing"), "10 + 5 leather is still short")

    SaveBank(world, { { WOOL, 20 } })
    equal(CrateTooltip(world)[2], Component(world, 1, "bank"), "all of it in the bank")
end)

test("ignores the bank while the saved bank is off", function(world)
    world.bags[0] = {}
    SaveBank(world, { { WOOL, 20 } })
    world:Setting("inventory.bank.enabled"):SetValue(false)
    equal(CrateTooltip(world)[2], Component(world, 1, "missing"), "saved bank off")
end)

test("leaves a line whose count differs from the data unmarked", function(world)
    world.bags[0] = {}
    InBags(world, 1, WOOL, 20)
    local components = { "- 25\194\160Wool Cloth", COMPONENTS[TEST_LOCALE][2], COMPONENTS[TEST_LOCALE][3] }
    local useLines = CrateTooltip(world, CRATE, components)
    equal(useLines[2], components[1], "a count changed since the data")
    equal(useLines[3], Component(world, 2, "missing"), "the next lines keep their place")
end)

test("leaves other items and the disabled feature alone", function(world)
    world.bags[0] = {}
    InBags(world, 1, WOOL, 20)
    equal(CrateTooltip(world, 6948)[2], Component(world, 1), "an item that isn't a crate")

    world:Setting("inventory.crates.enabled"):SetValue(false)
    equal(CrateTooltip(world)[2], Component(world, 1), "feature off")
end)
