-- The quest watch list: makes it match the ranked quests, and tells the
-- player's own changes apart from ours and from Blizzard's.
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

-- Untracks every quest that isn't ranked or kept, then tracks the ranked ones
-- (closest first) while there is room.
function Watches:Apply(ranked)
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
    for _, questID in ipairs(ranked) do
        if
            not self:IsWatched(questID)
            and C_QuestLog.GetNumQuestWatches() < Constants.QuestWatchConsts.MAX_QUEST_WATCHES
        then
            C_QuestLog.AddQuestWatch(questID)
            changed = true
        end
    end
    applying = false

    if changed then
        C_QuestLog.SortQuestWatches()
    end
end

-- Forgets session state (pins are kept).
function Watches:Reset()
    wipe(addedElsewhere)
    wipe(progressed)
    wipe(dismissed)
end
