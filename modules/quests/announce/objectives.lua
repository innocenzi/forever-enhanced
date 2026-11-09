-- Remembers whether each objective of each quest is finished and announces the
-- ones that go from unfinished to finished. Quests are recorded silently when
-- first seen (on enable, on accept, or once their data loads), so objectives
-- that were already done are never announced. Each objective is announced at
-- most once while its quest stays in the log, even if it is undone (an item
-- sold) and done again.

local _, ns = ...

local Announce = ns:GetFeature("quests", "announce")

local Objectives = {}
Announce.Objectives = Objectives

-- finished[questID][objectiveIndex] = boolean
local finished = {}
-- announced[questID][objectiveIndex] = true
local announced = {}

local function MarkAnnounced(questID, index)
    local quest = announced[questID]
    if not quest then
        quest = {}
        announced[questID] = quest
    end
    if quest[index] then
        return false
    end
    quest[index] = true
    return true
end

local function Update(questID, announce)
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    -- Nothing while the quest data loads: keep what we knew.
    if not objectives or #objectives == 0 then
        return
    end
    local previous = finished[questID]
    local current = {}
    for index, objective in ipairs(objectives) do
        current[index] = objective.finished
        if
            announce
            and previous
            and previous[index] == false
            and objective.finished
            and MarkAnnounced(questID, index)
        then
            Announce.Message:Announce(questID, objective)
        end
    end
    finished[questID] = current
end

-- Every quest in the log, plus the ones already known (a quest under a
-- collapsed header may not be listed).
local function Scan(announce)
    local questIDs = {}
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and not info.isHidden and info.questID then
            questIDs[info.questID] = true
        end
    end
    for questID in pairs(finished) do
        questIDs[questID] = true
    end
    for questID in pairs(questIDs) do
        Update(questID, announce)
    end
end

local listener = ns:CreateEventListener({
    QUEST_LOG_UPDATE = function()
        Scan(true)
    end,
    QUEST_REMOVED = function(_, questID)
        finished[questID] = nil
        announced[questID] = nil
    end,
})

function Objectives:Enable()
    Scan(false)
    listener:Start()
end

function Objectives:Disable()
    listener:Stop()
    wipe(finished)
    wipe(announced)
end
