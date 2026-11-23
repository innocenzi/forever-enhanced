-- Bag fullness and the lowest value items.

local _, ns = ...

local Cheapest = ns:GetFeature("inventory", "cheapest")
local Locking = ns:GetFeature("inventory", "locking")
local Auction = ns:GetFeature("inventory", "auction")
local Marks = ns:GetFeature("inventory", "marks")

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

local NUM_ACTION_SLOTS = 180

-- The marks that keep an item (the "marks" option of "ignore"): every one but junk.
local KEPT_MARKS = { "auction", "bank", "mail" }

-- The items on the action bars, as a set of item IDs.
local function GetActionBarItems()
    local items = {}
    for slot = 1, NUM_ACTION_SLOTS do
        local actionType, id = GetActionInfo(slot)
        if actionType == "item" then
            items[id] = true
        end
    end
    return items
end

local function IsTool(itemID)
    if Cheapest.Tools[itemID] then
        return true
    end
    local classID, subclassID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == Enum.ItemClass.Weapon and subclassID == Enum.ItemWeaponSubclass.Fishingpole
end

local function IsClassReagent(itemID, class)
    if select(6, C_Item.GetItemInfoInstant(itemID)) == Enum.ItemClass.Projectile then
        return true
    end
    return tContains(Cheapest.ClassReagents[itemID] or {}, class)
end

local function IsMarkedToKeep(itemID)
    for _, destination in ipairs(KEPT_MARKS) do
        if Marks:IsMarked(itemID, destination) then
            return true
        end
    end
    return false
end

-- Each "ignore" option and whether it keeps the item: (info, guid, context),
-- context being what the whole bag scan shares (actionBarItems, class). Food,
-- quests and professions load after this slice: looked up on use.
local IGNORES = {
    food = function(info)
        return ns:GetFeature("inventory", "food"):IsFoodOrDrink(info.itemID)
    end,
    questItems = function(info)
        return info.itemName ~= nil and ns:GetFeature("quests", "helpers"):IsNeededByQuest(info.itemName)
    end,
    tools = function(info)
        return IsTool(info.itemID)
    end,
    reagents = function(info)
        return ns:GetFeature("professions", "reagents"):IsKnownReagent(info.itemID)
    end,
    classReagents = function(info, _, context)
        return IsClassReagent(info.itemID, context.class)
    end,
    actionBars = function(info, _, context)
        context.actionBarItems = context.actionBarItems or GetActionBarItems()
        return context.actionBarItems[info.itemID] == true
    end,
    marks = function(info)
        return IsMarkedToKeep(info.itemID)
    end,
    notes = function(_, guid)
        return Marks:GetGUIDNote(guid) ~= nil
    end,
}

-- Every "ignore" option must have its check.
for _, entry in ipairs(Cheapest.settings) do
    if entry.key == "ignore" then
        for _, option in ipairs(entry.options) do
            assert(IGNORES[option], "no check for ignore option " .. option)
        end
    end
end

local function IsIgnored(info, guid, context)
    local ignore = Cheapest:GetSetting("ignore")
    for option, Ignores in pairs(IGNORES) do
        if ignore[option] and Ignores(info, guid, context) then
            return true
        end
    end
    return false
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
-- items, hearthstone) or item data not loaded yet. Then whether the item's
-- data wasn't loaded.
local function GetStackValue(info)
    if info.hasNoValue then
        return nil, false
    end
    local sellPrice = select(11, C_Item.GetItemInfo(info.itemID))
    if not sellPrice then
        return nil, true
    end
    local auctionPrice = not info.isBound and Auction:GetPrice(info.itemID) or 0
    return math.max(sellPrice, auctionPrice) * info.stackCount, false
end

-- The bag items worth the least, { [guid] = true }: every one tied for the
-- lowest value, locked and ignored items left out. Then the items whose data
-- wasn't loaded yet, { [itemID] = true }: their value counts once it is.
function Value:Collect()
    local lowest, items, unloaded = nil, {}, {}
    local context = { class = select(2, UnitClass("player")) }
    ns.Containers:ForEachSlot(GetBagIDs(), function(bagID, slot)
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if not info then
            return
        end
        local value, isUnloaded = GetStackValue(info)
        if isUnloaded then
            unloaded[info.itemID] = true
        end
        if not value then
            return
        end
        local guid = ns.Containers:GetItemGUID(ItemLocation:CreateFromBagAndSlot(bagID, slot))
        if not guid or Locking:IsGUIDLocked(guid) or IsIgnored(info, guid, context) then
            return
        end
        if not lowest or value < lowest then
            lowest, items = value, {}
        end
        if value == lowest then
            items[guid] = true
        end
    end)
    return items, unloaded
end
