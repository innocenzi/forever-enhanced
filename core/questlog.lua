-- Which quests the quest log holds, as a string that changes whenever a quest
-- enters or leaves it (headers included). QUEST_LOG_UPDATE fires on every bit
-- of objective progress too: features compare this to skip work that only
-- depends on which quests are in the log. Cheap: one number per log entry, no
-- table from the client.

local _, ns = ...

local ids = {}

function ns:GetQuestLogSignature()
    local count = C_QuestLog.GetNumQuestLogEntries()
    for index = 1, count do
        ids[index] = C_QuestLog.GetQuestIDForLogIndex(index) or 0
    end
    for index = #ids, count + 1, -1 do
        ids[index] = nil
    end
    return table.concat(ids, ",")
end
