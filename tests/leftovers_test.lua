-- Quest helpers, leftover quest items: which quests use a quest item is learned
-- as the player plays; once they are all completed, the item's tooltip says so
-- and its bag button shows a check mark. Items are their own IDs and names in
-- the fake client; the bag starts as G1 G2 - GJUNK, so slot 3 is free.

local SLOT = 3

local BLOOM = { questID = 10, title = "Bloom of the Heavens" }
local SEEDS = { questID = 11, title = "Seeds of Doubt" }

local function Quest(quest, objectives)
    return { questID = quest.questID, title = quest.title, objectives = objectives or {} }
end

-- Puts `itemID` in the free slot, a quest item unless `ordinary`.
local function Put(world, itemID, ordinary)
    world.questItems[itemID] = not ordinary or nil
    world.bags[0][SLOT] = itemID
    world:Fire("BAG_UPDATE_DELAYED")
    world:NextFrame()
end

local function Completed(world, title)
    return title and world.L["quests.helpers.leftovers.line"]:format(title)
        or world.L["quests.helpers.leftovers.lineUnknown"]
end

-- The leftover lines of the item's tooltip.
local function Lines(world, itemID)
    local prefix = world.L["quests.helpers.leftovers.lineUnknown"]
    local lines = {}
    for _, line in ipairs(world:ItemTooltip({ id = itemID })) do
        if line:sub(1, #prefix) == prefix then
            table.insert(lines, line)
        end
    end
    return lines
end

local function IsLeftover(world, itemID)
    return #Lines(world, itemID) > 0
end

local function TurnIn(world, quest)
    world:TurnInQuest(quest.questID)
    world:NextFrame()
end

-- The player accepts `quest` and brings `itemID` to its NPC.
local function TakenAtTurnIn(world, quest, itemID)
    world:AcceptQuest(Quest(quest))
    world:ShowQuestProgress(quest, { itemID })
    world:NextFrame()
end

test("an item a quest takes is a leftover once the quest is completed", function(world)
    Put(world, "NORDEL")
    TakenAtTurnIn(world, BLOOM, "NORDEL")
    expect(not IsLeftover(world, "NORDEL"), "not while the quest is in the log")
    expect(not world:LeftoverMark(SLOT), "no mark while the quest is in the log")

    TurnIn(world, BLOOM)
    local lines = Lines(world, "NORDEL")
    equal(#lines, 1, "one line")
    equal(lines[1], Completed(world, BLOOM.title), "names the quest, from the turn-in window")
    expect(world:LeftoverMark(SLOT), "check mark in the bags")
    expect(not world:LeftoverMark(1), "no mark on other items")
end)

test("learns the quest items the log's objectives need", function(world)
    world:Setting("quests.helpers.objectives"):SetValue(false)
    world:AcceptQuest(Quest(BLOOM, { world:Objective("NORDEL", 1, 0) }))
    Put(world, "NORDEL")
    TurnIn(world, BLOOM)
    equal(Lines(world, "NORDEL")[1], Completed(world, BLOOM.title), "linked through the objective")
end)

test("learns the quest items a quest gives when accepted", function(world)
    world:ShowQuestDetail(BLOOM)
    world:CloseQuestFrame()
    world:AcceptQuest(Quest(BLOOM))
    world:NextFrame()
    world:Elapse(0.5)
    Put(world, "NORDEL")
    TurnIn(world, BLOOM)
    equal(Lines(world, "NORDEL")[1], Completed(world, BLOOM.title), "linked to the accepted quest")
end)

test("a quest window closed without accepting links nothing later", function(world)
    world:ShowQuestDetail(BLOOM)
    world:CloseQuestFrame()
    world:Elapse(10)
    world:AcceptQuest(Quest(SEEDS))
    Put(world, "NORDEL")
    TurnIn(world, SEEDS)
    expect(not IsLeftover(world, "NORDEL"), "not linked to a quest accepted much later")
end)

test("an item that starts a completed quest is a leftover", function(world)
    world.startsQuest.LETTER = 20
    Put(world, "LETTER")
    expect(not IsLeftover(world, "LETTER"), "not while its quest is still to do")
    world.completedQuests[20] = true
    world:Fire("QUEST_LOG_UPDATE")
    world:NextFrame()
    equal(Lines(world, "LETTER")[1], Completed(world), "untitled line")
    expect(world:LeftoverMark(SLOT), "check mark")
end)

test("an item stays needed while any of its quests is in the log", function(world)
    Put(world, "NORDEL")
    TakenAtTurnIn(world, BLOOM, "NORDEL")
    TakenAtTurnIn(world, SEEDS, "NORDEL")
    TurnIn(world, BLOOM)
    expect(not IsLeftover(world, "NORDEL"), "the other quest still needs it")
    TurnIn(world, SEEDS)
    local lines = Lines(world, "NORDEL")
    equal(#lines, 2, "one line per quest")
    equal(lines[1], Completed(world, BLOOM.title), "first quest")
    equal(lines[2], Completed(world, SEEDS.title), "second quest")
end)

test("items of repeatable quests are never leftovers", function(world)
    Put(world, "NORDEL")
    TakenAtTurnIn(world, BLOOM, "NORDEL")
    TurnIn(world, BLOOM)
    world.completedQuests[BLOOM.questID] = nil -- never flagged, like the client's repeatables
    world:Fire("QUEST_LOG_UPDATE")
    world:NextFrame()
    expect(not IsLeftover(world, "NORDEL"), "no line")
    expect(not world:LeftoverMark(SLOT), "no mark")
end)

test("ordinary items are never learned", function(world)
    Put(world, "MEAT", true)
    TakenAtTurnIn(world, BLOOM, "MEAT")
    TurnIn(world, BLOOM)
    expect(not IsLeftover(world, "MEAT"), "no line")
    equal(world.env.ForeverEnhancedDB.stores.quests.helpers.items.MEAT, nil, "not saved")
end)

test("links are saved for the whole account", function(world)
    Put(world, "NORDEL")
    TakenAtTurnIn(world, BLOOM, "NORDEL")
    local store = world.env.ForeverEnhancedDB.stores.quests.helpers
    expect(store.items.NORDEL[BLOOM.questID], "item linked to the quest")
    equal(store.titles[BLOOM.questID], BLOOM.title, "title kept")
end)

test("the mark follows its option, the line stays", function(world)
    Put(world, "NORDEL")
    TakenAtTurnIn(world, BLOOM, "NORDEL")
    TurnIn(world, BLOOM)
    world:Setting("quests.helpers.leftoverMark"):SetValue(false)
    expect(not world:LeftoverMark(SLOT), "mark hidden")
    expect(IsLeftover(world, "NORDEL"), "line kept")
    world:Setting("quests.helpers.leftoverMark"):SetValue(true)
    expect(world:LeftoverMark(SLOT), "mark back")
end)

test("nothing shows with the option or the quest helpers off", function(world)
    Put(world, "NORDEL")
    TakenAtTurnIn(world, BLOOM, "NORDEL")
    TurnIn(world, BLOOM)
    world:Setting("quests.helpers.leftovers"):SetValue(false)
    expect(not IsLeftover(world, "NORDEL"), "no line with the option off")
    expect(not world:LeftoverMark(SLOT), "no mark with the option off")
    world:Setting("quests.helpers.leftovers"):SetValue(true)
    expect(world:LeftoverMark(SLOT), "mark back")
    world:Setting("quests.helpers.enabled"):SetValue(false)
    expect(not IsLeftover(world, "NORDEL"), "no line with the feature off")
    expect(not world:LeftoverMark(SLOT), "no mark with the feature off")
end)

test("learns nothing while off", function(world)
    world:Setting("quests.helpers.leftovers"):SetValue(false)
    Put(world, "NORDEL")
    TakenAtTurnIn(world, BLOOM, "NORDEL")
    TurnIn(world, BLOOM)
    world:Setting("quests.helpers.leftovers"):SetValue(true)
    world:NextFrame()
    expect(not IsLeftover(world, "NORDEL"), "not linked")
end)
