-- The full scan: on opening the auction house, asks the server for every
-- auction (C_AuctionHouse.ReplicateItems), at most once every 15 minutes, its
-- limit. When the list arrives (REPLICATE_ITEM_LIST_UPDATE), reads it a slice
-- per frame, keeping each item's lowest buyout per unit, and saves the prices
-- once it has read it all. A list another addon asked for is read the same way
-- unless we read one less than 15 minutes ago.
--
-- The list's prices need no item information: auctions of items the client
-- hasn't cached yet are read like the others.

local _, ns = ...

local Auction = ns:GetFeature("inventory", "auction")
local Store = Auction.Store

local Scan = {}
Auction.Scan = Scan

-- The server answers one ReplicateItems every 15 minutes.
Scan.INTERVAL = 15 * 60
Scan.AUCTIONS_PER_FRAME = 1000

local requested = false
-- The list being read: { index (0-based), count, prices }.
local reading

local function IsRecent()
    local scanned = Store:GetLastScan()
    return scanned ~= nil and GetServerTime() - scanned < Scan.INTERVAL
end

function Scan:Request()
    if not Auction:GetSetting("scan") or requested or reading or IsRecent() then
        return
    end
    requested = true
    Store:SetLastScan(GetServerTime())
    C_AuctionHouse.ReplicateItems()
end

local function ReadSlice(job)
    if reading ~= job then
        return -- stopped
    end
    local prices = job.prices
    local last = math.min(job.index + Scan.AUCTIONS_PER_FRAME, job.count) - 1
    for index = job.index, last do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
            C_AuctionHouse.GetReplicateItemInfo(index)
        if itemID and buyout and count and count > 0 then
            Store:KeepLowest(prices, itemID, math.floor(buyout / count))
        end
    end
    job.index = last + 1
    if job.index < job.count then
        C_Timer.After(0, function()
            ReadSlice(job)
        end)
    else
        reading = nil
        Store:SetPrices(prices)
    end
end

function Scan:Read()
    if reading or (not requested and IsRecent()) then
        return
    end
    requested = false
    Store:SetLastScan(GetServerTime())
    reading = { index = 0, count = C_AuctionHouse.GetNumReplicateItems(), prices = {} }
    ReadSlice(reading)
end

-- The list may be gone once the auction house closes: a scan cut short saves nothing.
function Scan:Stop()
    requested = false
    reading = nil
end
