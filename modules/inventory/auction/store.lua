-- Prices, in the account store so every character reads them, per auction
-- house: realm and faction.
--
-- houses["Forever-Horde"] = {
--     prices = { [itemID] = copper per unit },
--     seen = { [itemID] = server time the price was seen },
--     scanned = server time of the last full scan,
-- }

local _, ns = ...

local Auction = ns:GetFeature("inventory", "auction")

local Store = {}
Auction.Store = Store

-- Every battle pet is listed as a pet cage: its item ID says nothing of the pet.
local PET_CAGE_ITEM_ID = 82800

local function GetHouse()
    local store = Auction:GetAccountStore()
    store.houses = store.houses or {}
    local key = GetNormalizedRealmName() .. "-" .. UnitFactionGroup("player")
    local house = store.houses[key]
    if not house then
        house = { prices = {}, seen = {} }
        store.houses[key] = house
    end
    return house
end

-- Copper per unit and the server time it was seen, or nil when never seen.
function Store:GetPrice(itemID)
    local house = GetHouse()
    local price = house.prices[itemID]
    if price then
        return price, house.seen[itemID]
    end
end

-- Puts a price per unit in prices = { [itemID] = copper } unless it holds a
-- lower one. Battle pets are left out.
function Store:KeepLowest(prices, itemID, price)
    if itemID ~= PET_CAGE_ITEM_ID and price and price > 0 and (not prices[itemID] or price < prices[itemID]) then
        prices[itemID] = price
    end
end

-- prices = { [itemID] = copper per unit }, all seen now.
function Store:SetPrices(prices)
    local house = GetHouse()
    local now = GetServerTime()
    for itemID, price in pairs(prices) do
        house.prices[itemID] = price
        house.seen[itemID] = now
    end
end

function Store:GetLastScan()
    return GetHouse().scanned
end

function Store:SetLastScan(time)
    GetHouse().scanned = time
end
