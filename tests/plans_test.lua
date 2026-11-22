-- Planned recipes: the plan button on the recipe icon, and the
-- withdrawal of the planned reagents at the next bank visit. Reagents stack to
-- 20; the bags are container 0, the bank tabs 6 and 7.

local POTION = { recipeID = 101, name = "Potion", learned = true }
local ELIXIR = { recipeID = 102, name = "Elixir", learned = true }

local function Plans(world)
    return world.ns:GetFeature("professions", "plans")
end

-- Fills the bags and the bank; items: { guid = { itemID, count } }. The potion
-- takes 1 vial and 3 spices, the elixir 1 vial and 2 herbs.
local function Stock(world, bags, bank, items)
    world.maxStacks = { vial = 20, spice = 20, herb = 20 }
    world.counts = {}
    for guid, item in pairs(items) do
        world.itemIDs[guid] = item[1]
        world.counts[guid] = item[2]
    end
    world.bags[0], world.bags[6], world.bags[7] = bags, bank, {}
    world.recipeSchematics[POTION.recipeID] = { world:Reagent("vial", 1), world:Reagent("spice", 3) }
    world.recipeSchematics[ELIXIR.recipeID] = { world:Reagent("vial", 1), world:Reagent("herb", 2) }
end

-- Plans `crafts` crafts of the recipe from the button's dialog.
local function Plan(world, recipe, crafts)
    world:SelectRecipe(recipe)
    world:ClickPlanButton()
    world:TypeInDialog(tostring(crafts))
    world:PressEnterInDialog()
end

local function VisitBank(world)
    world:OpenBank()
    world:Elapse(5)
    world:CloseBank()
end

local function Item(world, itemID, count)
    return world.L["professions.plans.item"]:format(itemID, count)
end

test("the next bank visit moves the reagents the bags lack, once", function(world)
    Stock(world, { "V1" }, { "V2", "S1" }, {
        V1 = { "vial", 1 },
        V2 = { "vial", 5 },
        S1 = { "spice", 20 },
    })
    Plan(world, POTION, 2)
    VisitBank(world)
    equal(world:Slots(0), "V1(2) S1'(6) - -", "1 vial onto the bags' stack, 6 spices")
    equal(world:Slots(6), "V2(4) S1(14) - -", "bank")
    equal(
        world.prints[#world.prints],
        world.L["professions.plans.withdrawn"]:format(Item(world, "spice", 6) .. ", " .. Item(world, "vial", 1)),
        "announced"
    )
    equal(Plans(world):GetPlannedCount(POTION.recipeID), nil, "plan forgotten")

    local prints = #world.prints
    VisitBank(world)
    equal(world:Slots(0), "V1(2) S1'(6) - -", "nothing more")
    equal(#world.prints, prints, "nothing announced")
end)

test("plans add up per reagent", function(world)
    Stock(world, {}, { "V2", "S1", "H1" }, {
        V2 = { "vial", 10 },
        S1 = { "spice", 20 },
        H1 = { "herb", 20 },
    })
    Plan(world, POTION, 1)
    Plan(world, ELIXIR, 2)
    VisitBank(world)
    equal(world:Slots(0), "H1'(4) S1'(3) V2'(3) -", "bags")
end)

test("what the bank lacks is announced, and the plan still forgotten", function(world)
    Stock(world, {}, { "S1" }, {
        S1 = { "spice", 2 },
    })
    Plan(world, POTION, 1)
    VisitBank(world)
    equal(world:Slots(0), "S1(2) - - -", "bags")
    local missing = Item(world, "spice", 1) .. ", " .. Item(world, "vial", 1)
    equal(world.prints[#world.prints], world.L["professions.plans.missing"]:format(missing), "missing announced")
    equal(Plans(world):GetPlannedCount(POTION.recipeID), nil, "plan forgotten")
end)

test("nothing is announced with the option off", function(world)
    Stock(world, {}, { "S1", "V2" }, {
        S1 = { "spice", 20 },
        V2 = { "vial", 20 },
    })
    world:Setting("professions.plans.announce"):SetValue(false)
    Plan(world, POTION, 1)
    local prints = #world.prints
    VisitBank(world)
    equal(world:Slots(0), "S1'(3) V2' - -", "withdrawn")
    equal(#world.prints, prints, "nothing announced")
end)

test("the plan button sits on the recipe icon, lit while the recipe is planned", function(world)
    Stock(world, {}, {}, {})
    world:SelectRecipe(POTION)
    local button = assert(world:PlanButton(), "button")
    expect(button:IsVisible(), "shown")
    local _, relativeTo = button:GetPoint(1)
    equal(relativeTo, ProfessionsFrame.CraftingPage.SchematicForm.OutputIcon, "on the recipe icon")
    local icon
    for _, texture in ipairs(world.textures) do
        if texture.owner == button then
            icon = texture
        end
    end
    expect(icon.desaturated, "dim")
    local _, lines = world:PlanButtonTooltip()
    expect(not tContains(lines, world.L["professions.plans.rightClick"]), "nothing to cancel")

    Plan(world, POTION, 2)
    expect(not icon.desaturated, "lit")
    _, lines = world:PlanButtonTooltip()
    expect(tContains(lines, world.L["professions.plans.planned"]:format(2)), "planned count")

    world:SelectRecipe(ELIXIR)
    expect(icon.desaturated, "another recipe")
    world:SelectRecipe(POTION)
    expect(not icon.desaturated, "back")

    world:SelectRecipe({ recipeID = 103, name = "Flask", learned = false })
    expect(not button:IsVisible(), "hidden with the star")
end)

test("the dialog starts from the planned count, else the craft count", function(world)
    Stock(world, {}, {}, {})
    world:SelectRecipe(POTION)
    world:ClickPlanButton()
    equal(world:Dialog():GetEditBox():GetText(), "1", "at least one")
    world.craftCount = 4
    world:ClickPlanButton()
    equal(world:Dialog():GetEditBox():GetText(), "4", "the craft count")
    Plan(world, POTION, 2)
    world:ClickPlanButton()
    equal(world:Dialog():GetEditBox():GetText(), "2", "the planned count")
end)

test("0 crafts or Right Click cancels the plan", function(world)
    Stock(world, {}, {}, {})
    Plan(world, POTION, 2)
    Plan(world, POTION, 0)
    equal(Plans(world):GetPlannedCount(POTION.recipeID), nil, "0 crafts")
    Plan(world, POTION, 2)
    world:ClickPlanButton("RightButton")
    equal(Plans(world):GetPlannedCount(POTION.recipeID), nil, "Right Click")
end)

test("turning the feature off hides the button and keeps the plans for later", function(world)
    Stock(world, {}, { "S1", "V2" }, {
        S1 = { "spice", 20 },
        V2 = { "vial", 20 },
    })
    Plan(world, POTION, 1)
    world:Setting("professions.plans.enabled"):SetValue(false)
    expect(not world:PlanButton():IsVisible(), "hidden")
    VisitBank(world)
    equal(world:Slots(0), "- - - -", "nothing withdrawn")

    world:Setting("professions.plans.enabled"):SetValue(true)
    expect(world:PlanButton():IsVisible(), "back")
    VisitBank(world)
    equal(world:Slots(0), "S1'(3) V2' - -", "withdrawn")
end)

test("plans wait for the bank feature", function(world)
    Stock(world, {}, { "S1", "V2" }, {
        S1 = { "spice", 20 },
        V2 = { "vial", 20 },
    })
    Plan(world, POTION, 1)
    world:Setting("inventory.bank.enabled"):SetValue(false)
    VisitBank(world)
    equal(world:Slots(0), "- - - -", "nothing withdrawn")
    equal(Plans(world):GetPlannedCount(POTION.recipeID), 1, "still planned")
end)
