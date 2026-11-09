-- Lock set, keyed by item GUID so a lock follows the item wherever it moves.
-- GUIDs are never reused, so a lock left behind by a sold or destroyed item
-- can never match another item.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local function GetLocks()
    local store = Locking:GetCharacterStore()
    store.locks = store.locks or {}
    return store.locks
end

-- Returns the GUID of the item at `itemLocation`, or nil for an empty or invalid location.
function Locking.GetItemGUID(itemLocation)
    if itemLocation and itemLocation:IsValid() and C_Item.DoesItemExist(itemLocation) then
        return C_Item.GetItemGUID(itemLocation)
    end
end

-- Public API: other features may ask whether an item is locked.
-- Always false while the feature is inactive.
function Locking:IsGUIDLocked(guid)
    return self.active and guid ~= nil and GetLocks()[guid] == true
end

function Locking:IsLocked(itemLocation)
    return self:IsGUIDLocked(self.GetItemGUID(itemLocation))
end

function Locking:ToggleLock(itemLocation)
    local guid = self.GetItemGUID(itemLocation)
    if not guid then
        return
    end

    local locks = GetLocks()
    local locked = not locks[guid]
    locks[guid] = locked or nil

    if self:GetSetting("announce") then
        local message = locked and L["inventory.locking.locked"] or L["inventory.locking.unlocked"]
        ns:Print(message:format(C_Item.GetItemLink(itemLocation)))
    end

    self.Buttons:Refresh()
end
