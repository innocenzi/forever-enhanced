-- Auction house prices: item tooltips show the lowest buyout price seen for
-- the item at the auction house, per unit (and for the whole stack while Shift
-- is held, "stack"), with how long ago it was seen once that is over an hour
-- ("age").
--
-- Prices can only be read at an open auction house, from two sources:
--   - a full scan (C_AuctionHouse.ReplicateItems: every auction at once, which
--     the server answers once every 15 minutes), requested on opening the
--     auction house ("scan"), or by another addon;
--   - the browse and search results the player looks at, recorded as they
--     come, without sending queries of our own (they would replace the
--     results the auction house window shows).
-- Prices are kept by item ID, per realm and faction, in the account store so
-- every character reads them. A newer price replaces an older one; an item no
-- longer listed keeps its last price, which its age shows.
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   store.lua    prices per realm and faction, and the last full scan
--   scan.lua     the full scan, read a slice per frame
--   results.lua  records the browse and search results
--   tooltip.lua  the tooltip lines

local _, ns = ...

local Auction = ns:RegisterFeature("inventory", "auction", {
    order = 5,
    settings = {
        { key = "scan", type = "toggle", default = true },
        { key = "stack", type = "toggle", default = true },
        { key = "age", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = true, scan = true, stack = false, age = true },
        enhanced = { enabled = true, scan = true, stack = true, age = true },
    },
})

local listener = ns:CreateEventListener({
    AUCTION_HOUSE_SHOW = function()
        Auction.Scan:Request()
    end,
    AUCTION_HOUSE_CLOSED = function()
        Auction.Scan:Stop()
    end,
    REPLICATE_ITEM_LIST_UPDATE = function()
        Auction.Scan:Read()
    end,
    AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = function()
        Auction.Results:RecordBrowse(C_AuctionHouse.GetBrowseResults())
    end,
    AUCTION_HOUSE_BROWSE_RESULTS_ADDED = function(_, addedBrowseResults)
        Auction.Results:RecordBrowse(addedBrowseResults)
    end,
    COMMODITY_SEARCH_RESULTS_UPDATED = function(_, itemID)
        Auction.Results:RecordCommodity(itemID)
    end,
    ITEM_SEARCH_RESULTS_UPDATED = function(_, itemKey)
        Auction.Results:RecordItem(itemKey)
    end,
})

function Auction:OnEnable()
    listener:Start()
end

function Auction:OnDisable()
    listener:Stop()
    self.Scan:Stop()
end
