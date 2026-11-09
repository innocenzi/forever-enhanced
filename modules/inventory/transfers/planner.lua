-- The moves a transfer still needs, read from live positions every round
-- (see core/moves.lua). Dropping a stack onto a partial stack of the same item
-- fills it, and what doesn't fit stays in the source slot, so a remainder is
-- simply planned again next round.
--   "stacks": source stacks, smallest first, go onto the destination's partial
--             stacks of the same item. Empty slots are never used.
--   "all":    the same, then the remaining source stacks of items the
--             destination holds go to empty slots that accept them.
-- Locked items (Item Locking) neither move nor receive items.

local _, ns = ...

local Transfers = ns:GetFeature("inventory", "transfers")
local Locking = ns:GetFeature("inventory", "locking")

local Planner = {}
Transfers.Planner = Planner

-- Source and destination container IDs.
local function GetSides(direction)
    local bags, bank = ns.Containers.BAG_IDS, ns.Containers:GetBankContainerIDs()
    if direction == "deposit" then
        return bags, bank
    end
    return bank, bags
end

-- Stacks by item ID, in container order: { itemIDs = { ... }, [itemID] = { stack, ... } },
-- a stack being { order, location, guid, count, maxCount, locked }; and the empty slots.
local function Scan(containerIDs)
    local stacks, emptySlots = { itemIDs = {} }, {}
    ns.Containers:ForEachSlot(containerIDs, function(bagID, slot)
        local location = { bagID = bagID, slot = slot }
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if not info then
            table.insert(emptySlots, location)
            return
        end
        local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slot)
        if not stacks[info.itemID] then
            stacks[info.itemID] = {}
            table.insert(stacks.itemIDs, info.itemID)
        end
        table.insert(stacks[info.itemID], {
            order = #stacks[info.itemID] + 1,
            location = location,
            guid = C_Item.GetItemGUID(itemLocation),
            count = info.stackCount,
            maxCount = C_Item.GetItemMaxStackSize(itemLocation),
            locked = Locking:IsLocked(itemLocation),
        })
    end)
    return stacks, emptySlots
end

-- Unlocked stacks, smallest first (then in container order).
local function GetMovableStacks(stacks)
    local movable = {}
    for _, stack in ipairs(stacks or {}) do
        if not stack.locked then
            table.insert(movable, stack)
        end
    end
    table.sort(movable, function(a, b)
        if a.count ~= b.count then
            return a.count < b.count
        end
        return a.order < b.order
    end)
    return movable
end

-- Special bags (bag family flags) only take items of a matching family.
local function Accepts(bagID, itemID)
    local _, bagFamily = C_Container.GetContainerNumFreeSlots(bagID)
    return bagFamily == 0 or bit.band(C_Item.GetItemFamily(itemID), bagFamily) ~= 0
end

-- Takes the first empty slot that accepts the item.
local function TakeEmptySlot(emptySlots, itemID)
    for index, location in ipairs(emptySlots) do
        if Accepts(location.bagID, itemID) then
            return table.remove(emptySlots, index)
        end
    end
end

local function Move(stack, to)
    return { from = stack.location, to = to, key = stack.guid }
end

function Planner:Plan(direction, mode)
    local sourceIDs, destinationIDs = GetSides(direction)
    local sources = Scan(sourceIDs)
    local destinations, emptySlots = Scan(destinationIDs)
    local moves = {}

    for _, itemID in ipairs(destinations.itemIDs) do
        local candidates = GetMovableStacks(sources[itemID])
        local nextCandidate = 1
        for _, stack in ipairs(destinations[itemID]) do
            local candidate = candidates[nextCandidate]
            if candidate and not stack.locked and stack.count < stack.maxCount then
                table.insert(moves, Move(candidate, stack.location))
                nextCandidate = nextCandidate + 1
            end
        end
        if mode == "all" then
            while candidates[nextCandidate] do
                local emptySlot = TakeEmptySlot(emptySlots, itemID)
                if not emptySlot then
                    break
                end
                table.insert(moves, Move(candidates[nextCandidate], emptySlot))
                nextCandidate = nextCandidate + 1
            end
        end
    end
    return moves
end
