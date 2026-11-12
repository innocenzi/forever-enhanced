-- Objectives: adds "Bat Wings (3/10)" to item tooltips, wherever they are shown, for
-- each quest of the log that needs the item. Completed objectives keep their
-- line: the items are still needed to turn the quest in.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

ns:AddItemTooltipHandler(Helpers, function(tooltip, data)
    if not Helpers:IsPartActive("objectives") or not data.id then
        return
    end
    -- Nil until the item is cached; the tooltip refreshes once it is.
    local name = C_Item.GetItemInfo(data.id)
    local needs = name and Helpers.Needs:Find(name)
    if not needs then
        return
    end
    for _, need in ipairs(needs) do
        local line = ns.L["quests.helpers.objectives.line"]:format(need.title, need.numFulfilled, need.numRequired)
        tooltip:AddLine(NORMAL_FONT_COLOR:WrapTextInColorCode(line))
    end
end)

-- Leftovers: "Quest completed: Bat Wings" for the quests of a quest item once
-- they are all completed (leftovers.lua), "Quest completed" when none was
-- seen with its title.
local MAX_LEFTOVER_LINES = 2

ns:AddItemTooltipHandler(Helpers, function(tooltip, data)
    if not Helpers:IsPartActive("leftovers") then
        return
    end
    local quests = Helpers.Leftovers:GetCompletedQuests(data.id)
    if not quests then
        return
    end
    local lines = {}
    for _, questID in ipairs(quests) do
        local title = Helpers.Leftovers:GetTitle(questID)
        if title and #lines < MAX_LEFTOVER_LINES then
            table.insert(lines, ns.L["quests.helpers.leftovers.line"]:format(title))
        end
    end
    if #lines == 0 then
        lines[1] = ns.L["quests.helpers.leftovers.lineUnknown"]
    end
    for _, line in ipairs(lines) do
        tooltip:AddLine(NORMAL_FONT_COLOR:WrapTextInColorCode(line))
    end
end)
