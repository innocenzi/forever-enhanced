-- Lines added to item tooltips, wherever they are shown (bags, links, recipes...).
--
-- Tooltip post-calls can't be removed, so the addon installs one, once, and it
-- calls each feature's handler while that feature is active, in registration order.

local _, ns = ...

local handlers = {}

-- handler(tooltip, data): data is Blizzard's tooltip data (id = item ID, guid when
-- the item is in a container).
function ns:AddItemTooltipHandler(feature, handler)
    table.insert(handlers, { feature = feature, handler = handler })
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not data then
        return
    end
    for _, entry in ipairs(handlers) do
        if entry.feature:IsActive() then
            entry.handler(tooltip, data)
        end
    end
end)
