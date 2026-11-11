-- Professions, reagent uses: while Shift is held, item tooltips list the recipes
-- that use the item under each profession, known ones first. Uses the
-- generated data (modules/professions/reagents/data.lua) for Linen Cloth: First
-- Aid (2 bandages), Blacksmithing (3), Tailoring (Bolt of Linen Cloth) and
-- Engineering (6).

local LINEN_CLOTH = 2589
local LINEN_BANDAGE = 3275
local HEAVY_LINEN_BANDAGE = 3276
local BOLT_OF_LINEN_CLOTH = 2963

local FIRST_AID = 129
local BLACKSMITHING = 164
local TAILORING = 197
local ENGINEERING = 202

local NAMES = {
    enUS = { [129] = "First Aid", [164] = "Blacksmithing", [197] = "Tailoring", [202] = "Engineering" },
    frFR = { [129] = "Secourisme", [164] = "Forge", [197] = "Couture", [202] = "Ingénierie" },
}

local function Name(skillLine)
    return NAMES[TEST_LOCALE][skillLine]
end

local function Recipe(world, name, quantity)
    return world.L["professions.reagents.recipe"]:format(name, quantity)
end

local function Lines(world, itemID)
    return world:ItemTooltip({ id = itemID or LINEN_CLOTH })
end

-- The profession headers, in order.
local function Headers(lines)
    local headers = {}
    for _, line in ipairs(lines) do
        if not line:find("^ ") then
            table.insert(headers, line)
        end
    end
    return headers
end

-- The lines between the header of `skillLine` and the next header.
local function Section(lines, skillLine)
    local section
    for _, line in ipairs(lines) do
        if line == Name(skillLine) then
            section = {}
        elseif section then
            if not line:find("^ ") then
                break
            end
            table.insert(section, line)
        end
    end
    return section
end

local function Setup(world)
    world.recipeNames[LINEN_BANDAGE] = "Linen Bandage"
    world.recipeNames[HEAVY_LINEN_BANDAGE] = "Heavy Linen Bandage"
    world.recipeNames[BOLT_OF_LINEN_CLOTH] = "Bolt of Linen Cloth"
end

local function LearnFirstAidAndTailoring(world)
    world.professions = { { skillLine = TAILORING }, nil, { skillLine = FIRST_AID } }
end

test("adds nothing without Shift", function(world)
    equal(#Lines(world), 0, "lines")
end)

test("adds nothing to items no recipe uses", function(world)
    world.shift = true
    equal(#Lines(world, 6948), 0, "Hearthstone")
end)

test("lists the recipes under each profession while Shift is held, after a blank line", function(world)
    Setup(world)
    world.shift = true
    local lines = Lines(world)
    equal(lines[1], " ", "blank line")
    local headers = Headers(lines)
    equal(#headers, 4, "headers")
    equal(headers[1], Name(FIRST_AID), "fixed order")
    equal(headers[2], Name(BLACKSMITHING), "fixed order")
    equal(headers[3], Name(TAILORING), "fixed order")
    equal(headers[4], Name(ENGINEERING), "fixed order")
    local firstAid = Section(lines, FIRST_AID)
    equal(#firstAid, 2, "first aid recipes")
    equal(firstAid[1], Recipe(world, "Heavy Linen Bandage", 2), "by name")
    equal(firstAid[2], Recipe(world, "Linen Bandage", 1), "by name")
    equal(#Section(lines, TAILORING), 1, "tailoring recipes")
    equal(Section(lines, TAILORING)[1], Recipe(world, "Bolt of Linen Cloth", 2), "tailoring")
    equal(#Section(lines, ENGINEERING), 6, "engineering recipes")
end)

test("lists only the player's professions when asked", function(world)
    world:Setting("professions.reagents.professions"):SetValue("mine")
    world.shift = true
    equal(#Lines(world), 0, "no profession: nothing")
    LearnFirstAidAndTailoring(world)
    local headers = Headers(Lines(world))
    equal(#headers, 2, "headers")
    equal(headers[1], Name(FIRST_AID), "first aid")
    equal(headers[2], Name(TAILORING), "tailoring")
end)

test("caps the recipes of a profession", function(world)
    world.shift = true
    local uses = world.ns:GetFeature("professions", "reagents").Data[2996] -- Bolt of Linen Cloth
    local tailoring = 0
    for _, use in ipairs(uses) do
        if use[2] == TAILORING then
            tailoring = tailoring + 1
        end
    end
    expect(tailoring > 8, "Bolt of Linen Cloth has many Tailoring recipes")
    local section = Section(Lines(world, 2996), TAILORING)
    equal(#section, 9, "8 recipes and the rest")
    equal(section[9], world.L["professions.reagents.more"]:format(tailoring - 8), "more")
end)

test("lists the recipes the profession window shows as learned first", function(world)
    Setup(world)
    LearnFirstAidAndTailoring(world)
    world.learnedRecipes[LINEN_BANDAGE] = true
    world:ShowTradeSkillList({ LINEN_BANDAGE, HEAVY_LINEN_BANDAGE })
    world.shift = true
    local firstAid = Section(Lines(world), FIRST_AID)
    equal(firstAid[1], Recipe(world, "Linen Bandage", 1), "known first")
    equal(firstAid[2], Recipe(world, "Heavy Linen Bandage", 2), "then the others")
end)

test("records recipes learned with the window closed", function(world)
    Setup(world)
    LearnFirstAidAndTailoring(world)
    world:Fire("NEW_RECIPE_LEARNED", LINEN_BANDAGE)
    world.shift = true
    equal(Section(Lines(world), FIRST_AID)[1], Recipe(world, "Linen Bandage", 1), "known first")
end)

test("forgets recipes the window shows as not learned", function(world)
    Setup(world)
    LearnFirstAidAndTailoring(world)
    world:Fire("NEW_RECIPE_LEARNED", LINEN_BANDAGE)
    world:ShowTradeSkillList({ LINEN_BANDAGE })
    world.shift = true
    equal(Section(Lines(world), FIRST_AID)[1], Recipe(world, "Heavy Linen Bandage", 2), "by name again")
end)

test("recipes of a dropped profession aren't known", function(world)
    Setup(world)
    LearnFirstAidAndTailoring(world)
    world:Fire("NEW_RECIPE_LEARNED", LINEN_BANDAGE)
    world.professions = { { skillLine = TAILORING } }
    world.shift = true
    equal(Section(Lines(world), FIRST_AID)[1], Recipe(world, "Heavy Linen Bandage", 2), "by name")
end)

test("rebuilds a reagent tooltip nothing else rebuilds when Shift changes", function(world)
    world:ShowItemOn(GameTooltip, { id = LINEN_CLOTH }, {})
    world:SetShift(true)
    equal(GameTooltip.refreshes, 1, "pressed")
    world:SetShift(false)
    equal(GameTooltip.refreshes, 2, "released")

    world:ShowItemOn(ItemRefTooltip, { id = LINEN_CLOTH }, nil)
    world:SetShift(true)
    equal(ItemRefTooltip.refreshes, 1, "chat link")
end)

test("leaves alone tooltips their owner rebuilds, other items, and combat", function(world)
    world:ShowItemOn(GameTooltip, { id = LINEN_CLOTH }, { UpdateTooltip = function() end })
    world:SetShift(true)
    world:ShowItemOn(GameTooltip, { id = 6948 }, {})
    world:SetShift(false)
    world:ShowItemOn(GameTooltip, { id = LINEN_CLOTH }, {})
    world:EnterCombat()
    world:SetShift(true)
    equal(GameTooltip.refreshes, 0, "refreshes")
end)

test("adds nothing once disabled", function(world)
    world:Setting("professions.reagents.enabled"):SetValue(false)
    world.shift = true
    equal(#Lines(world), 0, "tooltip")
    world:ShowItemOn(GameTooltip, { id = LINEN_CLOTH }, {})
    world:SetShift(true)
    equal(GameTooltip.refreshes, 0, "refreshes")
end)
