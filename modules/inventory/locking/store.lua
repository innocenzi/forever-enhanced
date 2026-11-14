-- Lock set, keyed by item GUID so locks follow the item wherever it moves.
-- GUIDs are never reused, so a lock left behind by a sold or destroyed item
-- can never match another item.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local function GetStore()
    local store = Locking:GetCharacterStore()
    store.locks = store.locks or {}
    return store
end

-- Public API: other features may ask whether an item is locked.
-- Always false while the feature is inactive.
function Locking:IsGUIDLocked(guid)
    return self.active and guid ~= nil and GetStore().locks[guid] == true
end

function Locking:IsLocked(itemLocation)
    return self:IsGUIDLocked(ns.Containers:GetItemGUID(itemLocation))
end

-- Whether Alt Left Click locks: unless Item marks (loaded after this slice)
-- gives it to a mark.
function Locking:AltClickLocks()
    return ns:GetFeature("inventory", "marks"):GetAltClickDestination() == nil
end

-- The error shown when a locked item is touched: how to unlock it.
function Locking:GetIsLockedMessage()
    return self:AltClickLocks() and L["inventory.locking.isLocked"] or L["inventory.locking.isLockedMenu"]
end

local function SetLocked(guid, locked)
    GetStore().locks[guid] = locked or nil
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end

function Locking:ToggleLock(itemLocation)
    local guid = ns.Containers:GetItemGUID(itemLocation)
    if guid then
        SetLocked(guid, not GetStore().locks[guid])
    end
end
