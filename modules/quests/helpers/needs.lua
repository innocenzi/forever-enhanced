-- The item objectives of the quest log, by item name. Objectives carry no item
-- ID, only their text, which the client words with QUEST_ITEMS_NEEDED
-- ("3/10 Crispy Bat Wing", "Steak de loup : 3/10"): reading that format back
-- gives the item name in every language. The index is rebuilt on the first
-- lookup after the log changes.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local Needs = {}
Helpers.Needs = Needs

-- byName[itemName] = { { title, numFulfilled, numRequired }, ... }
local byName = {}
local stale = true

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
    local pattern = NamePattern(QUEST_ITEMS_NEEDED)
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(index)
        if not info.isHeader and not info.isHidden then
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                local name = objective.type == "item" and NormalizeSpaces(objective.text):match(pattern)
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
