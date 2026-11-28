-- Tracked crafts: the number of crafts asked when a recipe is tracked, the
-- reagents for that many in Blizzard's recipe tracker, the count down on
-- crafting, and the bags topped up at every bank visit. Reagents stack to 20;
-- the bags are container 0, the bank tabs 6 and 7.

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
    world.recipeNames[POTION.recipeID] = POTION.name
    world.recipeNames[ELIXIR.recipeID] = ELIXIR.name
end

-- Tracks the recipe from its row in the list, for `crafts` crafts, and lets the tracker update.
local function Track(world, recipe, crafts)
    world:ShiftClickRecipe(recipe)
    world:TypeInCountPicker(tostring(crafts))
    world:ClickCountPicker("OkayButton")
    world:NextFrame()
end

local function VisitBank(world)
    world:OpenBank()
    world:Elapse(5)
    world:CloseBank()
end

local function Item(world, itemID, count)
    return world.L["professions.plans.item"]:format(itemID, count)
end

local function Header(world, recipe, count)
    return world.L["professions.plans.header"]:format(recipe.name, count)
end

local function Lines(world, recipe)
    return table.concat(assert(world:RecipeTrackerBlock(recipe.recipeID), "block").lines, ", ")
end

test("tracking a recipe from its row asks for the number of crafts the tracker shows", function(world)
    Stock(world, { "V1", "S1" }, {}, {
        V1 = { "vial", 1 },
        S1 = { "spice", 2 },
    })
    local row = world:ShiftClickRecipe(POTION)
    local picker = assert(world:CountPicker(), "picker")
    local _, relativeTo = picker:GetPoint(1)
    equal(relativeTo, row, "on the row")
    equal(picker.Count:GetText(), "1", "at least one")
    expect(not picker.LeftButton:IsEnabled(), "nothing below one")

    world:NextFrame()
    equal(world:RecipeTrackerBlock(POTION.recipeID).header, POTION.name, "tracked, Blizzard's header meanwhile")
    equal(Lines(world, POTION), "1/1 vial [check] [done], - 2/3 spice", "one craft meanwhile")

    world:TypeInCountPicker("4")
    world:ClickCountPicker("OkayButton")
    expect(not world:CountPicker(), "closed")
    equal(Plans(world):GetCount(POTION.recipeID), 4, "counted")
    equal(world:RecipeTrackerBlock(POTION.recipeID).header, Header(world, POTION, 4), "header at once")
    equal(Lines(world, POTION), "- 1/4 vial, - 2/12 spice", "lines at once")

    world:NextFrame()
    world:Fire("BAG_UPDATE_DELAYED")
    world:NextFrame()
    equal(Lines(world, POTION), "- 1/4 vial, - 2/12 spice", "after Blizzard's next update")
end)

test("the arrows and the wheel step the count", function(world)
    Stock(world, {}, {}, {})
    world:ShiftClickRecipe(POTION)
    local picker = world:CountPicker()
    world:ClickCountPicker("RightButton")
    world:ClickCountPicker("RightButton")
    equal(picker.Count:GetText(), "3", "right arrow")
    world:ClickCountPicker("LeftButton")
    equal(picker.Count:GetText(), "2", "left arrow")
    picker:RunScript("OnMouseWheel", -1)
    equal(picker.Count:GetText(), "1", "wheel")
    expect(not picker.LeftButton:IsEnabled(), "at one")
    world:TypeInCountPicker("999")
    expect(not picker.RightButton:IsEnabled(), "at the most")
end)

test("Cancel leaves Blizzard's plain tracking", function(world)
    Stock(world, { "V1" }, {}, {
        V1 = { "vial", 1 },
    })
    world:ShiftClickRecipe(POTION)
    world:ClickCountPicker("CancelButton")
    world:NextFrame()
    expect(C_TradeSkillUI.IsRecipeTracked(POTION.recipeID, false), "tracked")
    equal(Plans(world):GetCount(POTION.recipeID), nil, "no count")
    equal(world:RecipeTrackerBlock(POTION.recipeID).header, POTION.name, "Blizzard's header")
    equal(Lines(world, POTION), "1/1 vial [check] [done], - 0/3 spice", "Blizzard's lines")
end)

test("the checkbox asks too, from the window's craft count", function(world)
    Stock(world, {}, {}, {})
    world:SelectRecipe(POTION)
    world.craftCount = 3
    world:ClickTrackCheckbox()
    local picker = assert(world:CountPicker(), "picker")
    local _, relativeTo = picker:GetPoint(1)
    equal(relativeTo, ProfessionsFrame.CraftingPage.SchematicForm.TrackRecipeCheckbox, "on the checkbox")
    equal(picker.Count:GetText(), "3", "the craft count")
    world:ClickCountPicker("OkayButton")
    equal(Plans(world):GetCount(POTION.recipeID), 3, "counted")
end)

test("tracking from elsewhere doesn't ask", function(world)
    Stock(world, {}, {}, {})
    world:SelectRecipe(POTION)
    world.mouseFoci = {}
    C_TradeSkillUI.SetRecipeTracked(ELIXIR.recipeID, true, false)
    expect(not world:CountPicker(), "not under the mouse")

    world:ShiftClickRecipe(POTION)
    ProfessionsFrame:Hide()
    world:NextFrame()
    expect(not world:CountPicker(), "closed with the window")
end)

test("the tracker's menu sets the number of crafts", function(world)
    Stock(world, {}, {}, {})
    world:ShiftClickRecipe(POTION)
    world:ClickCountPicker("CancelButton")
    world:NextFrame()

    local entries = world:OpenRecipeTrackerMenu(POTION.recipeID)
    local entry
    for _, each in ipairs(entries) do
        if each.text == world.L["professions.plans.setCount"] then
            entry = each
        end
    end
    assert(entry, "menu entry")
    world:ClickMenuEntry(entry)
    local picker = assert(world:CountPicker(), "picker")
    local _, relativeTo = picker:GetPoint(1)
    equal(relativeTo, ProfessionsRecipeTracker:GetExistingBlock(POTION.recipeID), "on the recipe")
    equal(picker.Count:GetText(), "1", "from one")
    world:TypeInCountPicker("2")
    world:ClickCountPicker("OkayButton")
    equal(Lines(world, POTION), "- 0/2 vial, - 0/6 spice", "at once")

    world:ClickMenuEntry(entry)
    equal(world:CountPicker().Count:GetText(), "2", "from the count")
    world:TypeInCountPicker("0")
    world:ClickCountPicker("OkayButton")
    equal(Plans(world):GetCount(POTION.recipeID), nil, "0 forgets the count")
    equal(Lines(world, POTION), "- 0/1 vial, - 0/3 spice", "Blizzard's lines back")
end)

test("each craft counts one down, and the last one untracks the recipe", function(world)
    Stock(world, {}, {}, {})
    Track(world, POTION, 2)
    world:ShiftClickRecipe(ELIXIR)
    world:ClickCountPicker("CancelButton")
    world:NextFrame()

    world:Craft(POTION.recipeID)
    equal(Plans(world):GetCount(POTION.recipeID), 1, "one left")
    equal(world:RecipeTrackerBlock(POTION.recipeID).header, Header(world, POTION, 1), "header")

    local events = #world.recipeTrackerEvents
    world:Craft(POTION.recipeID)
    equal(Plans(world):GetCount(POTION.recipeID), nil, "done")
    expect(not C_TradeSkillUI.IsRecipeTracked(POTION.recipeID, false), "untracked")
    for i = events + 1, #world.recipeTrackerEvents do
        expect(world.recipeTrackerEvents[i] ~= "TRACKED_RECIPE_UPDATE", "kept from the tracker")
    end
    equal(world:RecipeTrackerBlock(POTION.recipeID), nil, "gone after the bags' update")

    world:Craft(ELIXIR.recipeID)
    expect(C_TradeSkillUI.IsRecipeTracked(ELIXIR.recipeID, false), "plain tracking kept")
end)

test("untracking forgets the count, even while the feature is off", function(world)
    Stock(world, {}, {}, {})
    Track(world, POTION, 2)
    world:ShiftClickRecipe(POTION)
    expect(not C_TradeSkillUI.IsRecipeTracked(POTION.recipeID, false), "untracked")
    equal(Plans(world):GetCount(POTION.recipeID), nil, "forgotten")

    Track(world, POTION, 3)
    world:Setting("professions.plans.enabled"):SetValue(false)
    C_TradeSkillUI.SetRecipeTracked(POTION.recipeID, false, false)
    world:Setting("professions.plans.enabled"):SetValue(true)
    equal(Plans(world):GetCount(POTION.recipeID), nil, "pruned")
end)

test("lines drawn for several crafts go back to the pool as Blizzard drew them", function(world)
    Stock(world, { "V1" }, {}, {
        V1 = { "vial", 1 },
    })
    Track(world, POTION, 2)
    equal(Lines(world, POTION), "- 1/2 vial, - 0/6 spice", "counted")
    world:ShiftClickRecipe(POTION)
    world:NextFrame()
    equal(world:RecipeTrackerBlock(POTION.recipeID), nil, "freed")
    expect(#world.trackerLinePool == 2, "pooled")
    for _, line in ipairs(world.trackerLinePool) do
        equal(line.Dash.shown, line.dashStyle == OBJECTIVE_DASH_STYLE_SHOW, "dash as Blizzard drew it")
        equal(line.Text.textColor.r, line.Text.colorStyle.r, "color as Blizzard drew it")
    end
end)

test("every bank visit tops the bags up for the tracked crafts", function(world)
    Stock(world, { "V1" }, { "V2", "S1" }, {
        V1 = { "vial", 1 },
        V2 = { "vial", 5 },
        S1 = { "spice", 20 },
    })
    Track(world, POTION, 2)
    VisitBank(world)
    equal(world:Slots(0), "V1(2) S1'(6) - -", "1 vial onto the bags' stack, 6 spices")
    equal(world:Slots(6), "V2(4) S1(14) - -", "bank")
    equal(
        world.prints[#world.prints],
        world.L["professions.plans.withdrawn"]:format(Item(world, "spice", 6) .. ", " .. Item(world, "vial", 1)),
        "announced"
    )
    equal(Plans(world):GetCount(POTION.recipeID), 2, "count kept")

    local prints = #world.prints
    VisitBank(world)
    equal(world:Slots(0), "V1(2) S1'(6) - -", "nothing more")
    equal(#world.prints, prints, "nothing announced")
end)

test("tracked crafts add up per reagent", function(world)
    Stock(world, {}, { "V2", "S1", "H1" }, {
        V2 = { "vial", 10 },
        S1 = { "spice", 20 },
        H1 = { "herb", 20 },
    })
    Track(world, POTION, 1)
    Track(world, ELIXIR, 2)
    VisitBank(world)
    equal(world:Slots(0), "H1'(4) S1'(3) V2'(3) -", "bags")
end)

test("what the bank lacks is announced with what came out", function(world)
    Stock(world, {}, { "S1" }, {
        S1 = { "spice", 2 },
    })
    Track(world, POTION, 1)
    VisitBank(world)
    equal(world:Slots(0), "S1(2) - - -", "bags")
    equal(
        world.prints[#world.prints - 1],
        world.L["professions.plans.withdrawn"]:format(Item(world, "spice", 2)),
        "withdrawn announced"
    )
    local missing = Item(world, "spice", 1) .. ", " .. Item(world, "vial", 1)
    equal(world.prints[#world.prints], world.L["professions.plans.missing"]:format(missing), "missing announced")

    local prints = #world.prints
    VisitBank(world)
    equal(#world.prints, prints, "nothing came out: nothing announced")
end)

test("nothing is announced with the option off", function(world)
    Stock(world, {}, { "S1", "V2" }, {
        S1 = { "spice", 20 },
        V2 = { "vial", 20 },
    })
    world:Setting("professions.plans.announce"):SetValue(false)
    Track(world, POTION, 1)
    local prints = #world.prints
    VisitBank(world)
    equal(world:Slots(0), "S1'(3) V2' - -", "withdrawn")
    equal(#world.prints, prints, "nothing announced")
end)

test("nothing is taken from the bank with the option off", function(world)
    Stock(world, {}, { "S1", "V2" }, {
        S1 = { "spice", 20 },
        V2 = { "vial", 20 },
    })
    world:Setting("professions.plans.withdraw"):SetValue(false)
    Track(world, POTION, 1)
    VisitBank(world)
    equal(world:Slots(0), "- - - -", "nothing withdrawn")
end)

test("turning the feature off gives Blizzard's tracking back and keeps the counts", function(world)
    Stock(world, {}, { "S1", "V2" }, {
        S1 = { "spice", 20 },
        V2 = { "vial", 20 },
    })
    Track(world, POTION, 2)
    world:Setting("professions.plans.enabled"):SetValue(false)
    equal(world:RecipeTrackerBlock(POTION.recipeID).header, POTION.name, "Blizzard's header")
    equal(Lines(world, POTION), "- 0/1 vial, - 0/3 spice", "Blizzard's lines")
    world:ShiftClickRecipe(ELIXIR)
    expect(not world:CountPicker(), "no picker")
    world:NextFrame()
    world:Craft(POTION.recipeID)
    VisitBank(world)
    equal(world:Slots(0), "- - - -", "nothing withdrawn")

    world:Setting("professions.plans.enabled"):SetValue(true)
    equal(Plans(world):GetCount(POTION.recipeID), 2, "count kept")
    equal(Lines(world, POTION), "- 0/2 vial, - 0/6 spice", "back")
    VisitBank(world)
    equal(world:Slots(0), "S1'(6) V2'(2) - -", "withdrawn")
end)

test("tracked crafts take their reagents without the bank features", function(world)
    Stock(world, {}, { "S1", "V2" }, {
        S1 = { "spice", 20 },
        V2 = { "vial", 20 },
    })
    Track(world, POTION, 1)
    world:Setting("inventory.bank.enabled"):SetValue(false)
    world:Setting("inventory.transfers.enabled"):SetValue(false)
    VisitBank(world)
    equal(world:Slots(0), "S1'(3) V2' - -", "withdrawn")
    equal(Plans(world):GetCount(POTION.recipeID), 1, "still counted")
end)
