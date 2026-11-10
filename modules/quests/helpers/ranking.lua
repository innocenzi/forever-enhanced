-- Which quests should be tracked: quest log entries with a known location,
-- filtered by the chosen scope, closest first, capped at the chosen count.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local Ranking = {}
Helpers.Ranking = Ranking

-- Tracked quests count as this much closer, so two quests at similar
-- distances don't swap places on every update.
local TRACKED_DISTANCE_FACTOR = 0.85

local function IsCandidate(info)
    return not info.isHeader
        and not info.isHidden
        and not info.isTask
        and not info.isBounty
        and not C_QuestLog.IsWorldQuest(info.questID)
end

-- Distance to the quest's nearest objective (or turn-in), or nil when the
-- quest has no location on the player's continent.
local function GetDistance(questID)
    local distanceSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
    if distanceSq and onContinent then
        return math.sqrt(distanceSq)
    end
end

local function GetQuestsInCurrentZone()
    local quests = {}
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        for _, poi in ipairs(C_QuestLog.GetQuestsOnMap(mapID)) do
            quests[poi.questID] = true
        end
    end
    return quests
end

-- Returns the quest IDs to track, closest first, or nil when no quest has a
-- known location (quest data not loaded yet, or no map here): the tracker
-- should then be left alone rather than emptied.
function Ranking:GetQuests()
    local scope = Helpers:GetSetting("scope")
    local range = Helpers:GetSetting("range")
    local inZone = scope == "zone" and GetQuestsInCurrentZone()
    local Watches = Helpers.Watches

    local quests, scores = {}, {}
    local anyLocated = false
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and IsCandidate(info) and not Watches:IsDismissed(info.questID) then
            local questID = info.questID
            local distance = GetDistance(questID)
            anyLocated = anyLocated or distance ~= nil
            local score = distance and (Watches:IsWatched(questID) and distance * TRACKED_DISTANCE_FACTOR or distance)
            if score and (scope ~= "range" or score <= range) and (not inZone or inZone[questID]) then
                table.insert(quests, questID)
                scores[questID] = score
            end
        end
    end

    if not anyLocated then
        return nil
    end

    table.sort(quests, function(a, b)
        if scores[a] ~= scores[b] then
            return scores[a] < scores[b]
        end
        return a < b
    end)
    for index = #quests, Helpers:GetSetting("count") + 1, -1 do
        quests[index] = nil
    end
    return quests
end
