-- Moves reserved items to their slot, with the item mover (core/moves.lua):
--   * when the count of a reserved item rises in the bags (looted, bought,
--     taken from the mail or the bank) or in the bank while it's open
--     (deposited), so moving it out by hand is left alone;
--   * after a cleanup of the bags or the bank, like locking's "Keep in place"
--     (locking/sorting.lua says how a sort reports back).
-- The largest stack outside the slots reserved for the item goes in, swapping
-- out whatever was there. Locked items (Item locking) never move. Bags and bank
-- are separate areas: a slot only takes the item from its own area.

local _, ns = ...

local Slots = ns:GetFeature("inventory", "slots")
local Locking = ns:GetFeature("inventory", "locking")

local Restore = {}
Slots.Restore = Restore

local SORT_TIMEOUT_SECONDS = 1 -- fallback when a sort reports nothing at all
local MAX_MOVES_PER_SLOT = 3

-- Which area each sort function cleans up (the account bank isn't covered).
local SORT_AREAS = { SortBags = "bags", SortBank = "bank", SortBankBags = "bank" }

local bankOpen = false
-- Count of each reserved item per readable area: { bags = { [itemID] = count }, bank = ... }.
local counts = {}
-- Reserved slots to fill: { ["bagID:slot"] = { bagID, slot, area } }.
local pending = {}
local hooksInstalled = false

local function GetContainerIDs(area)
    if area == "bags" then
        return ns.Containers.BAG_IDS
    end
    return ns.Containers:GetBankContainerIDs()
end

-- The areas whose slots can be read now.
local function GetReadableAreas()
    if bankOpen then
        return { "bags", "bank" }
    end
    return { "bags" }
end

local function IsLocked(bagID, slot)
    return Locking:IsLocked(ItemLocation:CreateFromBagAndSlot(bagID, slot))
end

-- Count of each reserved item in the area.
local function CountReservedItems(area)
    local containerIDs = GetContainerIDs(area)
    local result = {}
    Slots:ForEachReservation(containerIDs, function(_, _, itemID)
        result[itemID] = 0
    end)
    ns.Containers:ForEachSlot(containerIDs, function(bagID, slot)
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and result[info.itemID] then
            result[info.itemID] = result[info.itemID] + info.stackCount
        end
    end)
    return result
end

local function TakeBaseline()
    counts = {}
    for _, area in ipairs(GetReadableAreas()) do
        counts[area] = CountReservedItems(area)
    end
end

-- Marks the area's reserved slots pending: all of them, or those of `itemIDs`.
local function MarkPending(area, itemIDs)
    Slots:ForEachReservation(GetContainerIDs(area), function(bagID, slot, itemID)
        if not itemIDs or itemIDs[itemID] then
            pending[bagID .. ":" .. slot] = { bagID = bagID, slot = slot, area = area }
        end
    end)
end

-- Public API: the stack of itemID a slot reserved for it takes from the area
-- ("bags" or "bank"): the largest one that isn't locked or in a slot reserved
-- for it, skipping the slots in `skip` ({ ["bagID:slot"] = true }, optional).
function Slots:FindStackToMove(area, itemID, skip)
    local best, bestCount
    ns.Containers:ForEachSlot(GetContainerIDs(area), function(bagID, slot)
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if
            info
            and info.itemID == itemID
            and (not bestCount or info.stackCount > bestCount)
            and Slots:GetReservedItem(bagID, slot) ~= itemID
            and not IsLocked(bagID, slot)
            and not (skip and skip[bagID .. ":" .. slot])
        then
            best, bestCount = { bagID = bagID, slot = slot }, info.stackCount
        end
    end)
    return best
end

local function FindSource(area, itemID)
    return Slots:FindStackToMove(area, itemID)
end

-- One move per pending slot still missing its item. Slots holding it, freed,
-- gone, locked or with no stack to take are done.
local function Plan()
    local moves = {}
    for key, target in pairs(pending) do
        local itemID = Slots:GetReservedItem(target.bagID, target.slot)
        local info = C_Container.GetContainerItemInfo(target.bagID, target.slot)
        local source = itemID
            and (target.area == "bags" or bankOpen)
            and target.slot <= C_Container.GetContainerNumSlots(target.bagID)
            and not (info and (info.itemID == itemID or IsLocked(target.bagID, target.slot)))
            and FindSource(target.area, itemID)
        if source then
            table.insert(moves, { from = source, to = target, key = key })
        else
            pending[key] = nil
        end
    end
    return moves
end

local mover = ns:CreateMover({ Plan = Plan, maxMovesPerKey = MAX_MOVES_PER_SLOT })

-- Slots left over by a run that gave up aren't retried by the next one.
local function ClearIfIdle()
    if not mover:IsRunning() then
        pending = {}
    end
end

local function OnBagsUpdated()
    local rose = false
    for _, area in ipairs(GetReadableAreas()) do
        local old = counts[area] or {}
        local new = CountReservedItems(area)
        local itemIDs
        for itemID, count in pairs(new) do
            if count > (old[itemID] or 0) then
                itemIDs = itemIDs or {}
                itemIDs[itemID] = true
            end
        end
        if itemIDs then
            if not rose then
                ClearIfIdle()
                rose = true
            end
            MarkPending(area, itemIDs)
        end
        counts[area] = new
    end
    if rose and not mover:IsRunning() then
        mover:Start()
    end
end

local listener = ns:CreateEventListener({
    BAG_UPDATE_DELAYED = OnBagsUpdated,
    BANKFRAME_OPENED = function()
        bankOpen = true
        counts.bank = CountReservedItems("bank")
    end,
    BANKFRAME_CLOSED = function()
        bankOpen = false
        counts.bank = nil
        for key, target in pairs(pending) do
            if target.area == "bank" then
                pending[key] = nil
            end
        end
    end,
})

local function OnSortStarted(area)
    if not Slots:IsActive() or (area == "bank" and not bankOpen) then
        return
    end
    ClearIfIdle()
    MarkPending(area)
    if next(pending) then
        mover:WaitForServer(SORT_TIMEOUT_SECONDS)
    end
end

-- hooksecurefunc hooks can't be removed: install once, OnSortStarted checks IsActive().
function Restore:Enable()
    -- BankFrame shows before addons get BANKFRAME_OPENED.
    bankOpen = BankFrame:IsShown()
    TakeBaseline()
    listener:Start()
    if hooksInstalled then
        return
    end
    hooksInstalled = true
    for name, area in pairs(SORT_AREAS) do
        ns:HookSecureFunc(C_Container, name, function()
            OnSortStarted(area)
        end)
    end
end

function Restore:Disable()
    listener:Stop()
    mover:Stop()
    pending, counts = {}, {}
end

-- A slot just reserved holds its item already: only later arrivals count.
function Restore:OnReservationsChanged()
    if Slots:IsActive() then
        TakeBaseline()
    end
end
