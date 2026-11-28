-- The moves a transfer still needs, read from live positions every round
-- (see core/moves.lua). Dropping a stack onto a partial stack of the same item
-- fills it, and what doesn't fit stays in the source slot, so a remainder is
-- simply planned again next round.
--   "stacks": source stacks, smallest first, go onto the destination's partial
--             stacks of the same item. Empty slots are never used.
--   "all":    the same, then the remaining source stacks of items the
--             destination holds go to empty slots that accept them.
--   "marked": (deposit) like "all", for the bag items marked for the bank
--             (Item marks), whether or not the bank holds them.
--   "refill": (withdraw, automatic) like "stacks", except for the items marked
--             for the bank, which the automatic deposit takes back.
--   "upTo":   (withdraw, Transfers:WithdrawUpTo) brings the bags up to a total of
--             each item: whole bank stacks, smallest first, while they fit what
--             is missing, then the rest split off the next one. Each goes onto
--             a bag stack with room for all of it, or an empty slot.
-- Locked items (Item Locking) never move, but their stacks are filled like any
-- other: a merge keeps the receiving stack (and its lock) in place.

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

-- Bag type flags of each container (special bags), 0 for a normal bag.
local function GetBagFamilies(containerIDs)
    local families = {}
    for _, bagID in ipairs(containerIDs) do
        local _, family = C_Container.GetContainerNumFreeSlots(bagID)
        families[bagID] = family
    end
    return families
end

-- Stacks by item ID, in container order: { itemIDs = { ... }, [itemID] = { stack, ... } },
-- a stack being { order, location, guid, count, maxCount, locked }; and the empty
-- slots, with their bag family.
local function Scan(containerIDs)
    local stacks, emptySlots = { itemIDs = {} }, {}
    local families = GetBagFamilies(containerIDs)
    ns.Containers:ForEachSlot(containerIDs, function(bagID, slot)
        local location = { bagID = bagID, slot = slot }
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if not info then
            table.insert(emptySlots, { location = location, family = families[bagID] })
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

-- Takes the first empty slot that accepts the item: special bags only take
-- items of a matching family.
local function TakeEmptySlot(emptySlots, itemID)
    local itemFamily = C_Item.GetItemFamily(itemID)
    for index, emptySlot in ipairs(emptySlots) do
        if emptySlot.family == 0 or bit.band(itemFamily, emptySlot.family) ~= 0 then
            return table.remove(emptySlots, index).location
        end
    end
end

local function Move(stack, to)
    return { from = stack.location, to = to, key = stack.guid }
end

-- Plans the moves of one item: its movable source stacks onto the destination's
-- partial stacks, then, with `useEmptySlots`, into empty slots.
local function PlanItem(moves, itemID, sources, destinations, emptySlots, useEmptySlots)
    local candidates = GetMovableStacks(sources[itemID])
    local nextCandidate = 1
    for _, stack in ipairs(destinations[itemID] or {}) do
        local candidate = candidates[nextCandidate]
        if candidate and stack.count < stack.maxCount then
            table.insert(moves, Move(candidate, stack.location))
            nextCandidate = nextCandidate + 1
        end
    end
    if useEmptySlots then
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

-- The item IDs a mode moves: the ones the destination holds, or for "marked"
-- the source's items marked for the bank (Item marks, loaded after this slice);
-- "refill" leaves those out while the bank mark is on.
local function GetItemIDs(mode, sources, destinations)
    local Marks = ns:GetFeature("inventory", "marks")
    local function Filter(itemIDs, marked)
        local filtered = {}
        for _, itemID in ipairs(itemIDs) do
            if Marks:IsMarked(itemID, "bank") == marked then
                table.insert(filtered, itemID)
            end
        end
        return filtered
    end
    if mode == "marked" then
        return Filter(sources.itemIDs, true)
    end
    if mode == "refill" and Marks:IsDestinationActive("bank") then
        return Filter(destinations.itemIDs, false)
    end
    return destinations.itemIDs
end

local function CountStacks(stacks)
    local total = 0
    for _, stack in ipairs(stacks or {}) do
        total = total + stack.count
    end
    return total
end

-- A destination stack of the item with room for `count` more (the room is
-- taken), or else an empty slot that accepts the item.
local function TakeRoom(stacks, emptySlots, itemID, count)
    for _, stack in ipairs(stacks or {}) do
        if stack.maxCount - stack.count >= count then
            stack.count = stack.count + count
            return stack.location
        end
    end
    return TakeEmptySlot(emptySlots, itemID)
end

-- The "upTo" moves: what the destination lacks of totals[itemID], from the
-- movable source stacks, smallest first, the last one split if it holds more.
local function PlanUpTo(moves, totals, sources, destinations, emptySlots)
    local itemIDs = {}
    for itemID in pairs(totals) do
        table.insert(itemIDs, itemID)
    end
    table.sort(itemIDs)
    for _, itemID in ipairs(itemIDs) do
        local missing = totals[itemID] - CountStacks(destinations[itemID])
        for _, stack in ipairs(GetMovableStacks(sources[itemID])) do
            if missing <= 0 then
                break
            end
            local count = math.min(stack.count, missing)
            local to = TakeRoom(destinations[itemID], emptySlots, itemID, count)
            if not to then
                break
            end
            local move = Move(stack, to)
            if count < stack.count then
                move.count = count
            end
            table.insert(moves, move)
            missing = missing - count
        end
    end
end

-- The moves still needed; `totals` ({ [itemID] = count }) for the "upTo" mode.
-- Other modes leave out the items of `skipped` (a set of item IDs).
function Planner:Plan(direction, mode, totals, skipped)
    local sourceIDs, destinationIDs = GetSides(direction)
    local sources = Scan(sourceIDs)
    local destinations, emptySlots = Scan(destinationIDs)
    local moves = {}
    if mode == "upTo" then
        PlanUpTo(moves, totals, sources, destinations, emptySlots)
        return moves
    end
    for _, itemID in ipairs(GetItemIDs(mode, sources, destinations)) do
        if not (skipped and skipped[itemID]) then
            PlanItem(moves, itemID, sources, destinations, emptySlots, mode == "all" or mode == "marked")
        end
    end
    return moves
end
