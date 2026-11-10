-- Quest helpers, objectives in tooltips: item tooltips name the quests of the log that
-- need the item, with progress, and follow the log as it changes. Items are
-- their own IDs and names in the fake client.

local function Line(world, title, numFulfilled, numRequired)
    return world.L["quests.helpers.objectives.line"]:format(title, numFulfilled, numRequired)
end

local function Lines(world, itemID)
    return world:ItemTooltip({ id = itemID })
end

local function WithQuests(world, quests)
    world.questLog = quests
    world:Fire("QUEST_LOG_UPDATE")
end

-- A quest that needs 10 Crispy Bat Wings.
local function BatWings(world, numFulfilled)
    return { questID = 1, title = "Bat Wings", objectives = { world:Objective("Crispy Bat Wing", 10, numFulfilled) } }
end

test("names the quest that needs the item, with progress", function(world)
    WithQuests(world, { BatWings(world, 3) })
    local lines = Lines(world, "Crispy Bat Wing")
    equal(#lines, 1, "lines")
    equal(lines[1], Line(world, "Bat Wings", 3, 10), "line")
    equal(#Lines(world, "Linen Cloth"), 0, "nothing for other items")
end)

test("keeps the line once the objective is complete", function(world)
    WithQuests(world, { BatWings(world, 10) })
    equal(Lines(world, "Crispy Bat Wing")[1], Line(world, "Bat Wings", 10, 10), "line")
end)

test("one line per quest that needs the item", function(world)
    WithQuests(world, {
        BatWings(world, 3),
        { isHeader = true, title = "Elwynn Forest" },
        {
            questID = 2,
            title = "Supplies",
            objectives = { world:Objective("Linen Cloth", 5), world:Objective("Crispy Bat Wing", 2, 2) },
        },
    })
    local lines = Lines(world, "Crispy Bat Wing")
    equal(#lines, 2, "lines")
    equal(lines[1], Line(world, "Bat Wings", 3, 10), "first quest")
    equal(lines[2], Line(world, "Supplies", 2, 2), "second quest")
end)

test("ignores objectives that aren't items, and partial names", function(world)
    local quest = BatWings(world, 0)
    table.insert(quest.objectives, world:Objective("Vampire Bat", 8, 0, "monster"))
    WithQuests(world, { quest })
    equal(#Lines(world, "Vampire Bat"), 0, "kill objective")
    equal(#Lines(world, "Bat Wing"), 0, "partial name")
end)

test("reads the item name in any client language's wording", function(world)
    local formats = {
        "%s: %d/%d", -- not positional
        "%1$s：%2$d/%3$d", -- full-width colon
        "%1$s (%2$d/%3$d)", -- pattern characters
        "%2$d/%3$d %1$s",
    }
    for _, format in ipairs(formats) do
        world.env.QUEST_ITEMS_NEEDED = format
        WithQuests(world, {
            { questID = 1, title = "Odd Names", objectives = { world:Objective("Bat-Wing (Large) 50%", 10, 3) } },
        })
        equal(Lines(world, "Bat-Wing (Large) 50%")[1], Line(world, "Odd Names", 3, 10), format)
    end
end)

test("follows progress and quests leaving the log", function(world)
    WithQuests(world, { BatWings(world, 3) })
    equal(Lines(world, "Crispy Bat Wing")[1], Line(world, "Bat Wings", 3, 10), "before")
    world:Progress(1, 1, 4)
    equal(Lines(world, "Crispy Bat Wing")[1], Line(world, "Bat Wings", 4, 10), "after progress")
    WithQuests(world, {})
    equal(#Lines(world, "Crispy Bat Wing"), 0, "quest removed")
end)

test("no line with the option off", function(world)
    WithQuests(world, { BatWings(world, 3) })
    world:Setting("quests.helpers.objectives"):SetValue(false)
    equal(#Lines(world, "Crispy Bat Wing"), 0, "feature off")
    world:Setting("quests.helpers.objectives"):SetValue(true)
    equal(#Lines(world, "Crispy Bat Wing"), 1, "back on")
end)

test("no line with the quest helpers off", function(world)
    WithQuests(world, { BatWings(world, 3) })
    world:Setting("quests.helpers.enabled"):SetValue(false)
    equal(#Lines(world, "Crispy Bat Wing"), 0, "feature off")
end)
