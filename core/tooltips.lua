-- Lines added to item tooltips, wherever they are shown (bags, links, recipes...).
--
-- Tooltip post-calls can't be removed, so the addon installs them, once, and
-- they call each feature's handler while that feature is active, in
-- registration order. Price handlers run from the sell price line's post-call,
-- so their lines come right under the sell price, before the item's next lines
-- (appearance, ...); for an item without a sell price line, at the end, before
-- the other handlers.

local _, ns = ...

local priceHandlers = {}
local handlers = {}

-- Tooltip data whose price lines were added under its sell price.
local pricesAdded = setmetatable({}, { __mode = "k" })

-- handler(tooltip, data): data is Blizzard's tooltip data (id = item ID, guid when
-- the item is in a container). options.price: the handler adds price lines,
-- shown right under the sell price. options.part: the toggle key of the part
-- the handler belongs to, which runs it only while that part does.
function ns:AddItemTooltipHandler(feature, handler, options)
    options = options or {}
    local list = options.price and priceHandlers or handlers
    table.insert(list, { feature = feature, handler = handler, part = options.part })
end

local function Run(list, tooltip, data)
    for _, entry in ipairs(list) do
        if entry.feature:IsHandlerActive(entry.part) then
            entry.handler(tooltip, data)
        end
    end
end

-- Runs after Blizzard's own, which draws the sell price.
TooltipDataProcessor.AddLinePostCall(Enum.TooltipDataLineType.SellPrice, function(tooltip)
    local info = tooltip:GetProcessingTooltipInfo()
    local data = info and info.tooltipData
    if data and data.type == Enum.TooltipDataType.Item then
        pricesAdded[data] = true
        Run(priceHandlers, tooltip, data)
    end
end)

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not data then
        return
    end
    if pricesAdded[data] then
        pricesAdded[data] = nil -- a rebuild may process the same data again
    else
        Run(priceHandlers, tooltip, data)
    end
    Run(handlers, tooltip, data)
end)
