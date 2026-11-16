-- When to re-evaluate: on a ticker (no event fires as the player moves), on
-- zone and quest log changes, and on watch list changes made by others. Every
-- request in a frame is coalesced into one evaluation on the next frame.
-- Quest log, quest POI and quest watch updates fire on every bit of objective
-- progress (and after our own watch changes): those wait until
-- EVENT_THROTTLE_SECONDS after the last evaluation, so a burst costs one
-- evaluation now and one at its end. Watch changes wait for the end of combat
-- (the tracker has secure buttons).

local _, ns = ...

local Tracking = ns:GetFeature("quests", "tracking")

local Refresh = {}
Tracking.Refresh = Refresh

local TICK_SECONDS = 2
local EVENT_THROTTLE_SECONDS = 0.5

local queued = false
local waitingForCombatEnd = false
local ticker
-- When the last evaluation ran, and the timer of a throttled request.
local lastEvaluation
local throttleTimer

local function Evaluate()
    queued = false
    if not Tracking:IsActive() then
        return
    end
    lastEvaluation = GetTime()

    Tracking.Watches:Classify()
    if InCombatLockdown() then
        waitingForCombatEnd = true
        return
    end
    waitingForCombatEnd = false
    local ranked, distances = Tracking.Ranking:GetQuests()
    if ranked then
        Tracking.Watches:Apply(ranked, distances)
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

local function RequestThrottled()
    if queued or throttleTimer then
        return
    end
    local wait = lastEvaluation and lastEvaluation + EVENT_THROTTLE_SECONDS - GetTime() or 0
    if wait <= 0 then
        Refresh:Request()
        return
    end
    throttleTimer = C_Timer.NewTimer(wait, function()
        throttleTimer = nil
        Refresh:Request()
    end)
end

local function OnZoneChanged()
    Tracking.Watches:ClearDismissals()
    Refresh:Request()
end

local function OnQuestAccepted(_, questID)
    Tracking.Watches:OnQuestProgress(questID)
    Refresh:Request()
end

-- Blizzard watching the quest on its own is QUEST_WATCH_LIST_CHANGED.
local function OnQuestProgress(_, questID)
    Tracking.Watches:OnQuestProgress(questID)
    RequestThrottled()
end

local listener = ns:CreateEventListener({
    PLAYER_ENTERING_WORLD = OnZoneChanged,
    ZONE_CHANGED_NEW_AREA = OnZoneChanged,
    ZONE_CHANGED = Request,
    ZONE_CHANGED_INDOORS = Request,
    QUEST_LOG_UPDATE = RequestThrottled,
    QUEST_POI_UPDATE = RequestThrottled,
    QUEST_REMOVED = Request,
    SUPER_TRACKING_CHANGED = Request,
    QUEST_ACCEPTED = OnQuestAccepted,
    QUEST_WATCH_UPDATE = OnQuestProgress,
    QUEST_WATCH_LIST_CHANGED = function(_, questID)
        if Tracking.Watches:OnWatchListChanged(questID) then
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
    if throttleTimer then
        throttleTimer:Cancel()
        throttleTimer = nil
    end
    waitingForCombatEnd = false
end
