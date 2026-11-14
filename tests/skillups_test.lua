-- Professions, skill-up chance: the tooltip of a yellow or green recipe's
-- skill-up arrow shows the chance of gaining skill after Blizzard's line, from
-- the generated thresholds (modules/professions/skillups/data.lua): Smelt
-- Copper turns yellow at 25 and grey at 70, Linen Bandage yellow at 30 and grey
-- at 60.

local SMELT_COPPER = 2657
local LINEN_BANDAGE = 3275
local HEARTHSTONE = 8690 -- not a recipe

local ARROW_LINE = "High chance of gaining skill"

local function Chance(world, line, percent)
    return world.L["professions.skillups.chance"]:format(line, percent)
end

local function Hover(world, recipeID, difficulty)
    return world:HoverSkillUpArrow({
        recipeID = recipeID,
        relativeDifficulty = Enum.TradeskillRelativeDifficulty[difficulty],
        learned = true,
    })
end

test("shows the chance of a yellow recipe after Blizzard's line", function(world)
    world.professionSkill = { level = 40, modifier = 0 }
    local lines = Hover(world, SMELT_COPPER, "Medium")
    equal(#lines, 1, "lines")
    equal(lines[1], Chance(world, ARROW_LINE, 67), "(70 - 40) / (70 - 25)")
end)

test("gives an even chance where a recipe turns green", function(world)
    world.professionSkill = { level = 45, modifier = 0 }
    equal(Hover(world, LINEN_BANDAGE, "Easy")[1], Chance(world, ARROW_LINE, 50), "halfway from yellow to grey")
    world.professionSkill = { level = 57, modifier = 0 }
    equal(Hover(world, LINEN_BANDAGE, "Easy")[1], Chance(world, ARROW_LINE, 10), "near grey")
end)

test("counts skill bonuses", function(world)
    world.professionSkill = { level = 30, modifier = 15 }
    equal(Hover(world, LINEN_BANDAGE, "Easy")[1], Chance(world, ARROW_LINE, 50), "30 + 15")
end)

test("adds nothing to orange and grey recipes", function(world)
    world.professionSkill = { level = 10, modifier = 0 }
    equal(Hover(world, SMELT_COPPER, "Optimal")[1], ARROW_LINE, "orange: Blizzard's line says it all")
    world.professionSkill = { level = 80, modifier = 0 }
    equal(Hover(world, SMELT_COPPER, "Trivial")[1], ARROW_LINE, "grey")
end)

test("adds nothing for recipes missing from the data", function(world)
    equal(Hover(world, HEARTHSTONE, "Medium")[1], ARROW_LINE, "line")
end)

test("adds nothing to tooltips the arrow doesn't own", function(world)
    world:LoadProfessions()
    world.tooltipLines = {}
    GameTooltip.owner = CreateFrame("Button")
    GameTooltip_AddNormalLine(GameTooltip, "Some line")
    equal(world.tooltipLines[1], "Some line", "line")
end)

test("adds nothing while disabled", function(world)
    world.professionSkill = { level = 40, modifier = 0 }
    world:Setting("professions.skillups.enabled"):SetValue(false)
    equal(Hover(world, SMELT_COPPER, "Medium")[1], ARROW_LINE, "disabled")
    world:Setting("professions.skillups.enabled"):SetValue(true)
    equal(Hover(world, SMELT_COPPER, "Medium")[1], Chance(world, ARROW_LINE, 67), "enabled again")
end)

-- Herbs and ore nodes: their world tooltip shows the chance of a yellow or
-- green node after the profession (modules/professions/skillups/nodes.lua).
-- Tin Vein requires 65 Mining: yellow at 90, grey at 165; Silverleaf requires 1
-- Herbalism: yellow at 26, grey at 101.

local MINING, HERBALISM, TAILORING = 186, 182, 197

local NODES = {
    tin = { enUS = "Tin Vein", frFR = "Filon d'étain" },
    silverleaf = { enUS = "Silverleaf", frFR = "Feuillargent" },
}

local function HoverNode(world, node)
    return world:ObjectTooltip(NODES[node][TEST_LOCALE], "Profession")
end

test("shows the chance of a yellow or green node after its profession", function(world)
    world.professions = { { skillLine = TAILORING }, { skillLine = MINING, rank = 120 } }
    local lines = HoverNode(world, "tin")
    equal(#lines, 2, "lines")
    equal(lines[1], NODES.tin[TEST_LOCALE], "the name")
    equal(lines[2], Chance(world, "Profession", 60), "(165 - 120) / (165 - 90)")
    world.professions = { { skillLine = HERBALISM, rank = 64 } }
    equal(HoverNode(world, "silverleaf")[2], Chance(world, "Profession", 49), "(101 - 64) / (101 - 26)")
end)

test("counts gathering skill bonuses", function(world)
    world.professions = { { skillLine = HERBALISM, rank = 50, modifier = 14 } }
    equal(HoverNode(world, "silverleaf")[2], Chance(world, "Profession", 49), "50 + 14")
end)

test("adds nothing to orange and grey nodes", function(world)
    world.professions = { { skillLine = MINING, rank = 89 } }
    equal(HoverNode(world, "tin")[2], "Profession", "orange")
    world.professions = { { skillLine = MINING, rank = 90 } }
    equal(HoverNode(world, "tin")[2], Chance(world, "Profession", 100), "just turned yellow")
    world.professions = { { skillLine = MINING, rank = 165 } }
    equal(HoverNode(world, "tin")[2], "Profession", "grey")
end)

test("adds nothing to nodes of a profession the player lacks", function(world)
    world.professions = { { skillLine = MINING, rank = 120 } }
    equal(HoverNode(world, "silverleaf")[2], "Profession", "no Herbalism")
end)

test("adds nothing to other world objects", function(world)
    world.professions = { { skillLine = MINING, rank = 120 } }
    local lines = world:ObjectTooltip("Mailbox")
    equal(#lines, 1, "lines")
    equal(lines[1], "Mailbox", "the name")
end)

test("adds nothing to nodes whose name or profession is secret", function(world)
    world.professions = { { skillLine = MINING, rank = 120 } }
    local name = NODES.tin[TEST_LOCALE]
    equal(world:ObjectTooltip(world:Secret(name), "Profession")[2], "Profession", "secret name")
    local secret = world:Secret("Profession")
    equal(world:ObjectTooltip(name, secret)[2], secret, "secret profession")
end)

test("adds nothing to nodes while disabled", function(world)
    world.professions = { { skillLine = MINING, rank = 120 } }
    world:Setting("professions.skillups.enabled"):SetValue(false)
    equal(HoverNode(world, "tin")[2], "Profession", "disabled")
    world:Setting("professions.skillups.enabled"):SetValue(true)
    equal(HoverNode(world, "tin")[2], Chance(world, "Profession", 60), "enabled again")
end)
