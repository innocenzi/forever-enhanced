-- Professions, skill-up chance: the tooltip of a yellow or green recipe's
-- skill-up arrow shows the chance of gaining skill, from the generated
-- thresholds (modules/professions/skillups/data.lua): Smelt Copper turns
-- yellow at 25 and grey at 70, Linen Bandage yellow at 30 and grey at 60.

local SMELT_COPPER = 2657
local LINEN_BANDAGE = 3275
local HEARTHSTONE = 8690 -- not a recipe

local function Chance(world, percent)
    return world.L["professions.skillups.chance"]:format(percent)
end

local function Hover(world, recipeID, difficulty)
    return world:HoverSkillUpArrow({
        recipeID = recipeID,
        relativeDifficulty = Enum.TradeskillRelativeDifficulty[difficulty],
        learned = true,
    })
end

test("shows the chance of a yellow recipe under Blizzard's line", function(world)
    world.professionSkill = { level = 40, modifier = 0 }
    local lines = Hover(world, SMELT_COPPER, "Medium")
    equal(#lines, 2, "lines")
    equal(lines[1], "High chance of gaining skill", "Blizzard's line first")
    equal(lines[2], Chance(world, 67), "(70 - 40) / (70 - 25)")
end)

test("gives an even chance where a recipe turns green", function(world)
    world.professionSkill = { level = 45, modifier = 0 }
    equal(Hover(world, LINEN_BANDAGE, "Easy")[2], Chance(world, 50), "halfway from yellow to grey")
    world.professionSkill = { level = 57, modifier = 0 }
    equal(Hover(world, LINEN_BANDAGE, "Easy")[2], Chance(world, 10), "near grey")
end)

test("counts skill bonuses", function(world)
    world.professionSkill = { level = 30, modifier = 15 }
    equal(Hover(world, LINEN_BANDAGE, "Easy")[2], Chance(world, 50), "30 + 15")
end)

test("adds nothing to orange and grey recipes", function(world)
    world.professionSkill = { level = 10, modifier = 0 }
    equal(#Hover(world, SMELT_COPPER, "Optimal"), 1, "orange: Blizzard's line says it all")
    world.professionSkill = { level = 80, modifier = 0 }
    equal(#Hover(world, SMELT_COPPER, "Trivial"), 1, "grey")
end)

test("adds nothing for recipes missing from the data", function(world)
    equal(#Hover(world, HEARTHSTONE, "Medium"), 1, "lines")
end)

test("adds nothing to tooltips the arrow doesn't own", function(world)
    world:LoadProfessions()
    world.tooltipLines = {}
    GameTooltip.owner = CreateFrame("Button")
    GameTooltip_AddNormalLine(GameTooltip, "Some line")
    equal(#world.tooltipLines, 1, "lines")
end)

test("adds nothing while disabled", function(world)
    world.professionSkill = { level = 40, modifier = 0 }
    world:Setting("professions.skillups.enabled"):SetValue(false)
    equal(#Hover(world, SMELT_COPPER, "Medium"), 1, "disabled")
    world:Setting("professions.skillups.enabled"):SetValue(true)
    equal(#Hover(world, SMELT_COPPER, "Medium"), 2, "enabled again")
end)
