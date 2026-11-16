-- Remembers whether each objective of each quest is finished and announces the
-- ones that go from unfinished to finished. Quests are recorded silently when
-- first seen (on enable, on accept, or once their data loads), so objectives
-- that were already done are never announced. Each objective is announced at
-- most once while its quest stays in the log, even if it is undone (an item
-- sold) and done again.
--
-- QUEST_LOG_UPDATE fires on every bit of progress, at most once per frame.
-- The client names the quest that progressed beforehand (QUEST_WATCH_UPDATE,
-- QUEST_LOG_CRITERIA_UPDATE; unmeasured on Forever, the retail client does,
-- and Blizzard's auto quest watch relies on it): only those are read again,
-- with the quests whose data hasn't loaded yet. The whole log is read again
-- when quests enter or leave it.

local _, ns = ...

local Announce = ns:GetFeature("quests", "announce")

local Objectives = {}
Announce.Objectives = Objectives

-- finished[questID][objectiveIndex] = boolean
local finished = {}
-- announced[questID][objectiveIndex] = true
local announced = {}
-- Quests that progressed since the last quest log update: [questID] = true.
local progressed = {}
-- Quests without objectives at their last read (data loading, or none at
-- all): [questID] = true.
local loading = {}
-- The quest log at the last read (ns:GetQuestLogSignature).
local lastLog

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
        loading[questID] = true
        return
    end
    loading[questID] = nil
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
    lastLog = ns:GetQuestLogSignature()
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

local function OnQuestLogUpdate()
    if ns:GetQuestLogSignature() ~= lastLog then
        Scan(true)
    else
        for questID in pairs(loading) do
            progressed[questID] = true
        end
        for questID in pairs(progressed) do
            Update(questID, true)
        end
    end
    wipe(progressed)
end

local function OnQuestProgress(_, questID)
    if questID then
        progressed[questID] = true
    end
end

local listener = ns:CreateEventListener({
    QUEST_WATCH_UPDATE = OnQuestProgress,
    QUEST_LOG_CRITERIA_UPDATE = OnQuestProgress,
    QUEST_LOG_UPDATE = OnQuestLogUpdate,
    QUEST_REMOVED = function(_, questID)
        finished[questID] = nil
        announced[questID] = nil
        progressed[questID] = nil
        loading[questID] = nil
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
    wipe(progressed)
    wipe(loading)
    lastLog = nil
end
