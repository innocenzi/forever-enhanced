-- Bag fullness and the lowest value items.

local _, ns = ...

local Cheapest = ns:GetFeature("inventory", "cheapest")
local Locking = ns:GetFeature("inventory", "locking")
local Auction = ns:GetFeature("inventory", "auction")

local Value = {}
Cheapest.Value = Value

-- Bag family of a regular bag: any other only holds some items (quivers, soul bags).
local REGULAR_BAG_FAMILY = 0

-- The bags looked at: all of them, but the reagent bag with "excludeReagentBag".
local function GetBagIDs()
    if not Cheapest:GetSetting("excludeReagentBag") then
        return ns.Containers.BAG_IDS
    end
    local bagIDs = {}
    for _, bagID in ipairs(ns.Containers.BAG_IDS) do
        if bagID ~= Enum.BagIndex.ReagentBag then
            table.insert(bagIDs, bagID)
        end
    end
    return bagIDs
end

-- Whether every slot of the regular bags is taken.
function Value:IsFull()
    for _, bagID in ipairs(GetBagIDs()) do
        local free, family = C_Container.GetContainerNumFreeSlots(bagID)
        if free > 0 and family == REGULAR_BAG_FAMILY then
            return false
        end
    end
    return true
end

-- What the stack is worth, or nil when it can't be told: no sell price (quest
-- items, hearthstone) or item data not loaded yet.
local function GetStackValue(info)
    if info.hasNoValue then
        return nil
    end
    local sellPrice = select(11, C_Item.GetItemInfo(info.itemID))
    if not sellPrice then
        return nil
    end
    local auctionPrice = not info.isBound and Auction:GetPrice(info.itemID) or 0
    return math.max(sellPrice, auctionPrice) * info.stackCount
end

-- The bag items worth the least, { [guid] = true }: every one tied for the
-- lowest value, locked items left out.
function Value:Collect()
    local lowest, items = nil, {}
    ns.Containers:ForEachSlot(GetBagIDs(), function(bagID, slot)
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        local value = info and GetStackValue(info)
        if not value then
            return
        end
        local guid = ns.Containers:GetItemGUID(ItemLocation:CreateFromBagAndSlot(bagID, slot))
        if not guid or Locking:IsGUIDLocked(guid) then
            return
        end
        if not lowest or value < lowest then
            lowest, items = value, {}
        end
        if value == lowest then
            items[guid] = true
        end
    end)
    return items
end
