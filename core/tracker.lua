-- Quest watch and super tracking changes kept away from Blizzard's objective
-- tracker.
--
-- C_QuestLog.AddQuestWatch / RemoveQuestWatch / SortQuestWatches fire
-- QUEST_WATCH_LIST_CHANGED at once (measured in game), and super tracking
-- changes SUPER_TRACKING_CHANGED: the tracker's modules handle them inside our
-- call, from our tainted code, and mark the tracker dirty from there. Its
-- next-frame update then runs tainted and writes the tracker's own state, so
-- every later update runs tainted too, for the session. In combat, each update
-- reads the player's auras (ShouldShowMawBuffs), which throws from tainted code
-- while they're secret, and stops the update halfway.
-- So while our changes run, the modules don't listen to these events; the
-- game's own follow-up events (QUEST_LOG_UPDATE, QUEST_POI_UPDATE,
-- SUPER_TRACKING_PATH_UPDATED) refresh them, untainted (unmeasured).

local _, ns = ...

local EVENTS = { "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED" }

-- Calls func() with Blizzard's tracker modules deaf to the events it causes.
-- Every quest watch, super tracking or map pin change goes through here.
function ns:ShieldObjectiveTracker(func)
    local muted = {}
    for module in pairs(ObjectiveTrackerManager.moduleToContainerMap) do
        for _, event in ipairs(EVENTS) do
            if module:IsEventRegistered(event) then
                module:UnregisterEvent(event)
                table.insert(muted, { module = module, event = event })
            end
        end
    end
    local ok, err = pcall(func)
    for _, entry in ipairs(muted) do
        entry.module:RegisterEvent(entry.event)
    end
    if not ok then
        error(err, 0)
    end
end
