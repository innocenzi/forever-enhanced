-- Adds "Bat Wings (3/10)" to item tooltips, wherever they are shown, for
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
