-- Which quests should be tracked: quest log entries with a known location,
-- filtered by the chosen scope, closest first, capped at the chosen count.
-- With "dungeons" off, dungeon and raid quests are tracked only inside their
-- instance, ahead of every other quest there.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local Ranking = {}
Helpers.Ranking = Ranking

-- Tracked quests count as this much closer, so two quests at similar
-- distances don't swap places on every update.
local TRACKED_DISTANCE_FACTOR = 0.85

-- Tags of quests done inside an instance (the quest log shows "Dungeon",
-- "Raid", ...).
local INSTANCE_TAGS = {
    [Enum.QuestTag.Dungeon] = true,
    [Enum.QuestTag.Heroic] = true,
    [Enum.QuestTag.Raid] = true,
    [Enum.QuestTag.Raid10] = true,
    [Enum.QuestTag.Raid25] = true,
}

local function IsCandidate(info)
    return not info.isHeader
        and not info.isHidden
        and not info.isTask
        and not info.isBounty
        and not C_QuestLog.IsWorldQuest(info.questID)
end

local function IsInstanceQuest(questID)
    local tag = C_QuestLog.GetQuestTagInfo(questID)
    return tag ~= nil and INSTANCE_TAGS[tag.tagID] == true
end

-- Distance to the quest's nearest objective (or turn-in), or nil when the
-- quest has no location on the player's continent.
local function GetDistance(questID)
    local distanceSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
    if distanceSq and onContinent then
        return math.sqrt(distanceSq)
    end
end

-- The quests on the player's map, or nil when the client has no quest data
-- for it (it returns nothing for a while after a zone change, e.g. on a boat).
local function GetQuestsInCurrentZone()
    local mapID = C_Map.GetBestMapForUnit("player")
    local pois = mapID and C_QuestLog.GetQuestsOnMap(mapID)
    if not pois then
        return nil
    end
    local quests = {}
    for _, poi in ipairs(pois) do
        quests[poi.questID] = true
    end
    return quests
end

-- The quests of the instance the player is in (none outside one). The client
-- doesn't link quests to instances: these are the quests with objectives on
-- the instance's map, and those under a quest log header named after it.
local function GetCurrentInstanceQuests()
    local quests = {}
    if not IsInInstance() then
        return quests
    end
    local instanceName = GetInstanceInfo()
    local onMap = GetQuestsInCurrentZone() or {}
    local header
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and info.isHeader then
            header = info.title
        elseif info and (onMap[info.questID] or header == instanceName) then
            quests[info.questID] = true
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
    local inZone
    if scope == "zone" then
        inZone = GetQuestsInCurrentZone()
        if not inZone then
            return nil
        end
    end
    local instanceQuests = not Helpers:GetSetting("dungeons") and GetCurrentInstanceQuests()
    local Watches = Helpers.Watches

    local quests, scores = {}, {}
    local function Add(questID, score)
        table.insert(quests, questID)
        scores[questID] = score
    end

    local anyLocated = false
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and IsCandidate(info) and not Watches:IsDismissed(info.questID) then
            local questID = info.questID
            if instanceQuests and IsInstanceQuest(questID) then
                if instanceQuests[questID] then
                    anyLocated = true
                    Add(questID, 0)
                end
            else
                local distance = GetDistance(questID)
                anyLocated = anyLocated or distance ~= nil
                local score = distance
                    and (Watches:IsWatched(questID) and distance * TRACKED_DISTANCE_FACTOR or distance)
                if score and (scope ~= "range" or score <= range) and (not inZone or inZone[questID]) then
                    Add(questID, score)
                end
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
