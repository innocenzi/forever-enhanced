-- When to re-evaluate: on a ticker (no event fires as the player moves), on
-- zone and quest log changes, and on watch list changes made by others. Every
-- request in a frame is coalesced into one evaluation on the next frame.
-- Watch changes wait for the end of combat (the tracker has secure buttons).

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local Refresh = {}
Helpers.Refresh = Refresh

local TICK_SECONDS = 2

local queued = false
local waitingForCombatEnd = false
local ticker

local function Evaluate()
    queued = false
    if not Helpers:IsPartActive("nearby") then
        return
    end

    Helpers.Watches:Classify()
    if InCombatLockdown() then
        waitingForCombatEnd = true
        return
    end
    waitingForCombatEnd = false
    local ranked, distances = Helpers.Ranking:GetQuests()
    if ranked then
        Helpers.Watches:Apply(ranked, distances)
    end
end

function Refresh:Request()
    if not queued then
        queued = true
        C_Timer.After(0, Evaluate)
    end
end

local function Request()
    Refresh:Request()
end

local function OnZoneChanged()
    Helpers.Watches:ClearDismissals()
    Refresh:Request()
end

local function OnQuestProgress(_, questID)
    Helpers.Watches:OnQuestProgress(questID)
    Refresh:Request()
end

local listener = ns:CreateEventListener({
    PLAYER_ENTERING_WORLD = OnZoneChanged,
    ZONE_CHANGED_NEW_AREA = OnZoneChanged,
    ZONE_CHANGED = Request,
    ZONE_CHANGED_INDOORS = Request,
    QUEST_LOG_UPDATE = Request,
    QUEST_POI_UPDATE = Request,
    QUEST_REMOVED = Request,
    SUPER_TRACKING_CHANGED = Request,
    QUEST_ACCEPTED = OnQuestProgress,
    QUEST_WATCH_UPDATE = OnQuestProgress,
    QUEST_WATCH_LIST_CHANGED = function(_, questID)
        if Helpers.Watches:OnWatchListChanged(questID) then
            Refresh:Request()
        end
    end,
    PLAYER_REGEN_ENABLED = function()
        if waitingForCombatEnd then
            Refresh:Request()
        end
    end,
})

function Refresh:Enable()
    listener:Start()
    ticker = C_Timer.NewTicker(TICK_SECONDS, Request)
    self:Request()
end

function Refresh:Disable()
    listener:Stop()
    ticker:Cancel()
    ticker = nil
    waitingForCombatEnd = false
end
