-- The action slots holding food or drink, kept on the best item of their kind.
-- Every change that may call for a swap (bags, level, slots, the cursor, the
-- end of combat) runs one update on the next frame.

local _, ns = ...

local Food = ns:GetFeature("inventory", "food")

local Slots = {}
Food.Slots = Slots

-- Every action slot, the bars of every page included.
local NUM_ACTION_SLOTS = 180

-- The level PLAYER_LEVEL_UP announced: UnitLevel may still give the former one then.
local announcedLevel = 0

local queued = false

-- Slot -> "food" or "drink", for the slots holding an item that is both: the
-- kind the slot had before, so it keeps it.
local function GetKinds()
    local store = Food:GetCharacterStore()
    store.kinds = store.kinds or {}
    return store.kinds
end

-- "food", "drink" or nil for a slot not holding food or drink.
local function GetKind(slot, kinds)
    local actionType, itemID = GetActionInfo(slot)
    local item = actionType == "item" and Food:GetItem(itemID)
    if not item then
        return nil
    end
    if item.food and item.drink then
        return kinds[slot] or "food"
    end
    return item.food and "food" or "drink"
end

-- Item ID -> how many the bags hold.
local function CountBagItems()
    local counts = {}
    ns.Containers:ForEachSlot(ns.Containers.BAG_IDS, function(bagID, slot)
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info then
            counts[info.itemID] = (counts[info.itemID] or 0) + info.stackCount
        end
    end)
    return counts
end

local function Swap(slot, itemID)
    C_Item.PickupItem(itemID)
    PlaceAction(slot)
    -- The former item came back on the cursor.
    ClearCursor()
end

local function Update()
    -- PlaceAction is protected in combat, and the cursor may hold what the
    -- player is moving: both end with an event that updates again.
    if InCombatLockdown() or GetCursorInfo() then
        return
    end
    local kinds = GetKinds()
    local managed = {}
    for slot = 1, NUM_ACTION_SLOTS do
        local kind = GetKind(slot, kinds)
        kinds[slot] = kind
        if kind then
            managed[slot] = kind
        end
    end
    if not next(managed) then
        return
    end
    local counts = CountBagItems()
    local level = math.max(UnitLevel("player"), announcedLevel)
    local best = {}
    for slot = 1, NUM_ACTION_SLOTS do
        local kind = managed[slot]
        if kind then
            if best[kind] == nil then
                best[kind] = Food:PickBest(kind, counts, level) or false
            end
            local _, current = GetActionInfo(slot)
            if best[kind] and best[kind] ~= current then
                Swap(slot, best[kind])
            end
        end
    end
end

local function RunQueued()
    queued = false
    if Food:IsActive() then
        Update()
    end
end

-- Updates the slots on the next frame (once, however many times it's called).
function Slots:Refresh()
    if not queued then
        queued = true
        C_Timer.After(0, RunQueued)
    end
end

local function Refresh()
    Slots:Refresh()
end

local listener = ns:CreateEventListener({
    BAG_UPDATE_DELAYED = Refresh,
    ACTIONBAR_SLOT_CHANGED = Refresh,
    CURSOR_CHANGED = Refresh,
    PLAYER_REGEN_ENABLED = Refresh,
    PLAYER_LEVEL_UP = function(_, level)
        announcedLevel = level
        Refresh()
    end,
})

function Slots:Enable()
    listener:Start()
    self:Refresh()
end

function Slots:Disable()
    listener:Stop()
end
