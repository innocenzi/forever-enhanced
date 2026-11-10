-- The item objectives of the quest log, by item name. Objectives carry no item
-- ID, only their text ("3/10 Crispy Bat Wing"), so the item is the text
-- without its count. The index is rebuilt on the first lookup after the log
-- changes.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local Needs = {}
Helpers.Needs = Needs

-- byName[itemName] = { { title, numFulfilled, numRequired }, ... }
local byName = {}
local stale = true

local function Rebuild()
    wipe(byName)
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if not info.isHeader and not info.isHidden then
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                local name = objective.type == "item" and objective.text:match("^%d+/%d+ (.+)$")
                if name then
                    byName[name] = byName[name] or {}
                    table.insert(byName[name], {
                        title = info.title,
                        numFulfilled = objective.numFulfilled,
                        numRequired = objective.numRequired,
                    })
                end
            end
        end
    end
    stale = false
end

local listener = ns:CreateEventListener({
    QUEST_LOG_UPDATE = function()
        stale = true
    end,
})

-- The quests that need the item named `name`, or nil.
function Needs:Find(name)
    if stale then
        Rebuild()
    end
    return byName[name]
end

function Needs:Enable()
    stale = true
    listener:Start()
end

function Needs:Disable()
    listener:Stop()
    wipe(byName)
end
