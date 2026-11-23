-- The item objectives of the quest log, by item name. Objectives carry no item
-- ID, only their text, which the client words with QUEST_ITEMS_NEEDED
-- ("3/10 Crispy Bat Wing", "Steak de loup : 3/10"): reading that format back
-- gives the item name in every language. The index is rebuilt on the first
-- lookup after the log changes.
--
-- Shared by the "objectives" part (tooltip lines) and the "leftovers" part
-- (which quests use the quest items in the bags): it runs while either does.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local Needs = {}
Helpers.Needs = Needs

-- byName[itemName] = { { questID, title, numFulfilled, numRequired }, ... }
local byName = {}
local stale = true
-- Whether the last rebuild met an item objective whose text it couldn't read
-- (empty, or without the item's name yet).
local unreadable = false

-- No-break spaces (U+00A0, and the narrow U+202F) become plain spaces, so
-- the format and the text agree on spacing (French puts one before a colon).
local function NormalizeSpaces(text)
    return (text:gsub("\194\160", " "):gsub("\226\128\175", " "))
end

-- A Lua pattern capturing the item name from a format like "%2$d/%3$d %1$s"
-- or "%1$s : %2$d/%3$d" (positional or not: the string is the name, the
-- numbers are the count). Any run of spaces matches any spacing.
local function NamePattern(format)
    local pattern = NormalizeSpaces(format)
        :gsub("%%%d*%$?([sd])", function(kind)
            return kind == "s" and "\1" or "\2"
        end)
        :gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
        :gsub(" +", "%%s*")
        :gsub("\1", "(.-)")
        :gsub("\2", "%%d+")
    return "^" .. pattern .. "$"
end

local function Rebuild()
    wipe(byName)
    unreadable = false
    local pattern = NamePattern(QUEST_ITEMS_NEEDED)
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and not info.isHidden then
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                if objective.type == "item" then
                    local name = NormalizeSpaces(objective.text or ""):match(pattern)
                    if name and name ~= "" then
                        byName[name] = byName[name] or {}
                        table.insert(byName[name], {
                            questID = info.questID,
                            title = info.title,
                            numFulfilled = objective.numFulfilled,
                            numRequired = objective.numRequired,
                        })
                    else
                        unreadable = true
                    end
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

-- Whether the last lookup met an item objective it couldn't read yet: its
-- item may still be needed by a quest the index doesn't list.
function Needs:HasUnreadable()
    return unreadable
end

-- The parts using the index (their toggle keys): it runs while any does.
local users = {}

function Needs:Acquire(user)
    if next(users) == nil then
        stale = true
        listener:Start()
    end
    users[user] = true
end

function Needs:Release(user)
    users[user] = nil
    if next(users) == nil then
        listener:Stop()
        wipe(byName)
        unreadable = false
    end
end

-- Public API: whether a quest of the log needs the item named `name` (an item
-- objective, fulfilled or not); always false while no part uses the index.
function Helpers:IsNeededByQuest(name)
    return next(users) ~= nil and Needs:Find(name) ~= nil
end
