-- The quest watch list: makes it match the ranked quests (and their order,
-- with "sort" on), and tells the player's own changes apart from ours and from
-- Blizzard's.
--
-- Normal quest watches carry no "manual" flag, so a watch added by someone
-- else is classified on the next evaluation: if the quest was accepted or made
-- progress in the meantime, Blizzard's autoQuestWatch added it; otherwise the
-- player did, and the quest is pinned (kept while "keepManual" is on).
-- Quests the player untracks are dismissed until they change zone.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local Watches = {}
Helpers.Watches = Watches

-- True while we change watches, to ignore the events we cause.
local applying = false
-- Watches added by someone else since the last evaluation.
local addedElsewhere = {}
-- Quests accepted or progressed since the last evaluation.
local progressed = {}
-- Quests the player untracked, kept out until they change zone.
local dismissed = {}

-- Pinned quests, per character: [questID] = true.
local function GetPins()
    local store = Helpers:GetCharacterStore()
    store.pins = store.pins or {}
    return store.pins
end

local function GetWatchedQuests()
    local quests = {}
    for index = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
        if questID then
            table.insert(quests, questID)
        end
    end
    return quests
end

function Watches:IsWatched(questID)
    return C_QuestLog.GetQuestWatchType(questID) ~= nil
end

function Watches:IsDismissed(questID)
    return dismissed[questID] == true
end

function Watches:ClearDismissals()
    wipe(dismissed)
end

-- QUEST_ACCEPTED / QUEST_WATCH_UPDATE: Blizzard may watch the quest on its own.
function Watches:OnQuestProgress(questID)
    progressed[questID] = true
end

-- QUEST_WATCH_LIST_CHANGED. Returns whether someone else changed the list.
-- The event's "added" argument is optional, so the watch list is checked instead.
function Watches:OnWatchListChanged(questID)
    if applying or not questID then
        return false
    end
    if self:IsWatched(questID) then
        dismissed[questID] = nil
        addedElsewhere[questID] = true
    else
        addedElsewhere[questID] = nil
        GetPins()[questID] = nil
        dismissed[questID] = true
    end
    return true
end

-- Pins the quests the player tracked since the last call, and drops pins of
-- quests that are no longer tracked.
function Watches:Classify()
    local pins = GetPins()
    for questID in pairs(addedElsewhere) do
        if not progressed[questID] then
            pins[questID] = true
        end
    end
    wipe(addedElsewhere)
    wipe(progressed)

    for questID in pairs(pins) do
        if not self:IsWatched(questID) then
            pins[questID] = nil
        end
    end
end

-- Quests that are never untracked: the super-tracked quest and, when
-- "keepManual" is on, the pinned ones.
local function GetKeptQuests()
    local kept = {}
    if Helpers:GetSetting("keepManual") then
        for questID in pairs(GetPins()) do
            kept[questID] = true
        end
    end
    local superTracked = C_SuperTrack.GetSuperTrackedQuestID()
    if superTracked and superTracked ~= 0 then
        kept[superTracked] = true
    end
    return kept
end

-- Makes the watch list follow the given order, which holds every watched
-- quest. A quest tracked again lands at the top of the list: the longest end
-- of the order already in place stays, the other quests are untracked and
-- tracked again from the last to the first. The super-tracked quest stops
-- being super-tracked when untracked: it is super-tracked again. The tracker
-- updates on the next frame and still has the quests' blocks: re-tracked
-- quests don't play the new quest animation.
local function Reorder(order)
    local watched = GetWatchedQuests()
    local inPlace, inPlaceCount, position = {}, 0, #watched
    for index = #order, 1, -1 do
        while position > 0 and watched[position] ~= order[index] do
            position = position - 1
        end
        if position == 0 then
            break
        end
        inPlace[order[index]] = true
        inPlaceCount = inPlaceCount + 1
        position = position - 1
    end
    if inPlaceCount == #order then
        return
    end

    local superTracked = C_SuperTrack.GetSuperTrackedQuestID()
    for _, questID in ipairs(watched) do
        if not inPlace[questID] then
            C_QuestLog.RemoveQuestWatch(questID)
        end
    end
    for index = #order, 1, -1 do
        local questID = order[index]
        if not inPlace[questID] then
            C_QuestLog.AddQuestWatch(questID)
        end
    end
    if superTracked and superTracked ~= 0 and C_SuperTrack.GetSuperTrackedQuestID() ~= superTracked then
        C_SuperTrack.SetSuperTrackedQuestID(superTracked)
    end
end

-- Untracks every quest that isn't ranked or kept, then tracks the ranked ones
-- (closest first) while there is room. With "sort" on, orders the watch list
-- by distance; otherwise the game sorts it.
function Watches:Apply(ranked, distances)
    local wanted = GetKeptQuests()
    for _, questID in ipairs(ranked) do
        wanted[questID] = true
    end

    local changed = false
    applying = true
    for _, questID in ipairs(GetWatchedQuests()) do
        if not wanted[questID] then
            C_QuestLog.RemoveQuestWatch(questID)
            changed = true
        end
    end
    -- Closest first while there is room, then tracked from the farthest: each
    -- lands at the top of the list, so the closest ends up first.
    local added, room = {}, Constants.QuestWatchConsts.MAX_QUEST_WATCHES - C_QuestLog.GetNumQuestWatches()
    for _, questID in ipairs(ranked) do
        if #added < room and not self:IsWatched(questID) then
            table.insert(added, questID)
        end
    end
    for index = #added, 1, -1 do
        C_QuestLog.AddQuestWatch(added[index])
        changed = true
    end
    local sort = Helpers:GetSetting("sort")
    if sort then
        Reorder(Helpers.Ranking:Order(GetWatchedQuests(), distances))
    end
    applying = false

    if changed and not sort then
        C_QuestLog.SortQuestWatches()
    end
end

-- Forgets session state (pins are kept).
function Watches:Reset()
    wipe(addedElsewhere)
    wipe(progressed)
    wipe(dismissed)
end
