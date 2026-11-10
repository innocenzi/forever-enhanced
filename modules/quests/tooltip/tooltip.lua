-- Adds "Bat Wings (3/10)" to item tooltips, wherever they are shown, for
-- each quest of the log that needs the item. Completed objectives keep their
-- line: the items are still needed to turn the quest in.

local _, ns = ...

local Tooltip = ns:GetFeature("quests", "tooltip")

ns:AddItemTooltipHandler(Tooltip, function(tooltip, data)
    if not data.id then
        return
    end
    -- Nil until the item is cached; the tooltip refreshes once it is.
    local name = C_Item.GetItemInfo(data.id)
    local needs = name and Tooltip.Needs:Find(name)
    if not needs then
        return
    end
    for _, need in ipairs(needs) do
        local line = ns.L["quests.tooltip.line"]:format(need.title, need.numFulfilled, need.numRequired)
        tooltip:AddLine(NORMAL_FONT_COLOR:WrapTextInColorCode(line))
    end
end)
