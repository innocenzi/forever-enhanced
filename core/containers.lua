-- Bag and bank containers, for features that scan or move items.

local _, ns = ...

local Containers = {}
ns.Containers = Containers

-- The player's bags (what merchants can buy from).
Containers.BAG_IDS = {}
for bagID = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
    table.insert(Containers.BAG_IDS, bagID)
end

-- Every container, bank tabs included (what sorting can move).
Containers.ALL_CONTAINER_IDS = {}
for _, bagID in pairs(Enum.BagIndex) do
    if not tContains(Containers.ALL_CONTAINER_IDS, bagID) then
        table.insert(Containers.ALL_CONTAINER_IDS, bagID)
    end
end
table.sort(Containers.ALL_CONTAINER_IDS)

local isBag = {}
for _, bagID in ipairs(Containers.BAG_IDS) do
    isBag[bagID] = true
end

-- Whether `bagID` is one of the player's bags.
function Containers:IsBag(bagID)
    return isBag[bagID] == true
end

-- The GUID of the item at `itemLocation`, or nil for an empty or invalid location.
function Containers:GetItemGUID(itemLocation)
    if itemLocation and itemLocation:IsValid() and C_Item.DoesItemExist(itemLocation) then
        return C_Item.GetItemGUID(itemLocation)
    end
end

-- The character bank's purchased tabs, in tab order (index N is tab N; tabs 2
-- and up hold the bank bags). Their slots only exist while the bank is open.
function Containers:GetBankContainerIDs()
    local containerIDs = {}
    for _, tabData in ipairs(C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character) or {}) do
        table.insert(containerIDs, tabData.ID)
    end
    return containerIDs
end

-- Calls func(bagID, slot) for every slot of the given containers.
-- Stops and returns true as soon as func returns true.
function Containers:ForEachSlot(containerIDs, func)
    for _, bagID in ipairs(containerIDs) do
        for slot = 1, C_Container.GetContainerNumSlots(bagID) do
            if func(bagID, slot) then
                return true
            end
        end
    end
    return false
end
