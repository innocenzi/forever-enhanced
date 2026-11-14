-- Lines added to item tooltips, wherever they are shown (bags, links, recipes...).
--
-- Tooltip post-calls can't be removed, so the addon installs one, once, and it
-- calls each feature's handler while that feature is active: price handlers
-- first, so their lines follow the client's sell price, then the others, each
-- group in registration order.

local _, ns = ...

local priceHandlers = {}
local handlers = {}

-- handler(tooltip, data): data is Blizzard's tooltip data (id = item ID, guid when
-- the item is in a container). options.price: the handler adds price lines,
-- shown right under the sell price.
function ns:AddItemTooltipHandler(feature, handler, options)
    local list = options and options.price and priceHandlers or handlers
    table.insert(list, { feature = feature, handler = handler })
end

local function Run(list, tooltip, data)
    for _, entry in ipairs(list) do
        if entry.feature:IsActive() then
            entry.handler(tooltip, data)
        end
    end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not data then
        return
    end
    Run(priceHandlers, tooltip, data)
    Run(handlers, tooltip, data)
end)
