-- Which quests should be tracked: quest log entries with a known location,
-- filtered by the chosen scope, closest first, capped at the chosen count.
-- With "dungeons" off, dungeon and raid quests are tracked only inside their
-- instance, ahead of every other quest there.
-- With "sort" on, also the order the tracker shows them in.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local Ranking = {}
Helpers.Ranking = Ranking

-- A quest must be clearly closer than a tracked one to replace it, or than
-- the one above it to move up in the tracker, so two quests at similar
-- distances don't swap places on every update: closer by this factor and by
-- this many yards (near objectives, distances are small and a step changes
-- them by more than any factor).
local CLOSER_FACTOR = 0.85
local CLOSER_YARDS = 20

-- The distance under which a quest is clearly closer than one at this distance.
local function ClearlyCloserThan(distance)
    return math.min(distance * CLOSER_FACTOR, distance - CLOSER_YARDS)
end

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

-- Returns the quest IDs to track, closest first, and the distance of every
-- located quest ([questID] = yards, 0 for the quests of the current
-- instance), or nil when no quest has a known location (quest data not loaded
-- yet, or no map here): the tracker should then be left alone rather than
-- emptied.
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

    local quests, scores, distances = {}, {}, {}
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
                    distances[questID] = 0
                    Add(questID, 0)
                end
            else
                local distance = GetDistance(questID)
                anyLocated = anyLocated or distance ~= nil
                distances[questID] = distance
                local score = distance and (Watches:IsWatched(questID) and ClearlyCloserThan(distance) or distance)
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
    return quests, distances
end

-- The order the tracker should show the watched quests in (watch list order):
-- the super-tracked quest first, then the located quests closest first, then
-- the others as they are. A quest moves above another only when it is clearly
-- closer, so quests at similar distances keep their places.
function Ranking:Order(watched, distances)
    local superTracked = C_SuperTrack.GetSuperTrackedQuestID()
    local order, located, others = {}, {}, {}
    for _, questID in ipairs(watched) do
        local distance = distances[questID]
        if questID == superTracked then
            table.insert(order, questID)
        elseif distance then
            local position = #located + 1
            while position > 1 and distance < ClearlyCloserThan(distances[located[position - 1]]) do
                position = position - 1
            end
            table.insert(located, position, questID)
        else
            table.insert(others, questID)
        end
    end
    for _, questID in ipairs(located) do
        table.insert(order, questID)
    end
    for _, questID in ipairs(others) do
        table.insert(order, questID)
    end
    return order
end
