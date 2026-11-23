-- Quest watch, super tracking and recipe tracking changes kept away from
-- Blizzard's objective tracker.
--
-- C_TradeSkillUI.SetRecipeTracked fires TRACKED_RECIPE_UPDATE the same way,
-- handled by the recipe tracker module (unmeasured: shielded like the others);
-- its next update (a bag change, BAG_UPDATE_DELAYED) shows the change.
--
-- C_QuestLog.AddQuestWatch / RemoveQuestWatch / SortQuestWatches fire
-- QUEST_WATCH_LIST_CHANGED at once (measured in game), and super tracking
-- changes SUPER_TRACKING_CHANGED: the tracker's modules handle them inside our
-- call, from our tainted code, and mark the tracker dirty from there. Its
-- next-frame update then runs tainted and writes the tracker's own state, so
-- every later update runs tainted too, for the session. In combat, each update
-- reads the player's auras (ShouldShowMawBuffs), which throws from tainted code
-- while they're secret, and stops the update halfway.
-- The quest log beside the map (QuestMapFrame) handles both events too and
-- rebuilds itself from there, and the tracker reads it (the quest whose
-- details are open): its state tainted, the tracker's updates run tainted the
-- same way (measured in game: the quest log tainted right after our watch
-- changes, the tracker with it).
-- So while our changes run, neither listens to these events; the game's own
-- follow-up events (QUEST_LOG_UPDATE, QUEST_POI_UPDATE,
-- SUPER_TRACKING_PATH_UPDATED) refresh them, untainted (unmeasured).

local _, ns = ...

local EVENTS = { "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED", "TRACKED_RECIPE_UPDATE" }

-- Blizzard's frames that must not handle EVENTS from our code.
local function GetListeners()
    local frames = { QuestMapFrame }
    for module in pairs(ObjectiveTrackerManager.moduleToContainerMap) do
        table.insert(frames, module)
    end
    return frames
end

-- Calls func() with Blizzard's tracker modules and quest log deaf to the
-- events it causes. Every quest watch, super tracking, map pin or recipe
-- tracking change goes through here.
function ns:ShieldObjectiveTracker(func)
    local muted = {}
    for _, frame in ipairs(GetListeners()) do
        for _, event in ipairs(EVENTS) do
            if frame:IsEventRegistered(event) then
                frame:UnregisterEvent(event)
                table.insert(muted, { frame = frame, event = event })
            end
        end
    end
    local ok, err = pcall(func)
    for _, entry in ipairs(muted) do
        entry.frame:RegisterEvent(entry.event)
    end
    if not ok then
        error(err, 0)
    end
end
