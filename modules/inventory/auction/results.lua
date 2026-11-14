-- Records the prices of what the player browses and searches at the auction
-- house, as the results arrive: the lowest price of each browse result, and
-- the lowest buyout per unit of a commodity's or an item's search results.
-- Results are keyed by item key (item level, suffix): an item ID keeps the
-- lowest of its keys in one batch of results.

local _, ns = ...

local Auction = ns:GetFeature("inventory", "auction")
local Store = Auction.Store

local Results = {}
Auction.Results = Results

function Results:RecordBrowse(browseResults)
    local prices = {}
    for _, result in ipairs(browseResults) do
        Store:KeepLowest(prices, result.itemKey.itemID, result.minPrice)
    end
    Store:SetPrices(prices)
end

function Results:RecordCommodity(itemID)
    local prices = {}
    for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
        local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
        if result then
            Store:KeepLowest(prices, itemID, result.unitPrice)
        end
    end
    Store:SetPrices(prices)
end

function Results:RecordItem(itemKey)
    local prices = {}
    for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
        local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
        if result and result.buyoutAmount and result.quantity > 0 then
            Store:KeepLowest(prices, itemKey.itemID, math.floor(result.buyoutAmount / result.quantity))
        end
    end
    Store:SetPrices(prices)
end
