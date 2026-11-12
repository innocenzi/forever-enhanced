-- Lock set and notes, keyed by item GUID so they follow the item wherever it
-- moves. GUIDs are never reused, so a lock or note left behind by a sold or
-- destroyed item can never match another item.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local function GetStore()
    local store = Locking:GetCharacterStore()
    store.locks = store.locks or {}
    store.notes = store.notes or {}
    return store
end

-- Returns the GUID of the item at `itemLocation`, or nil for an empty or invalid location.
function Locking:GetItemGUID(itemLocation)
    if itemLocation and itemLocation:IsValid() and C_Item.DoesItemExist(itemLocation) then
        return C_Item.GetItemGUID(itemLocation)
    end
end

-- Public API: other features may ask whether an item is locked.
-- Always false while the feature is inactive.
function Locking:IsGUIDLocked(guid)
    return self.active and guid ~= nil and GetStore().locks[guid] == true
end

function Locking:IsLocked(itemLocation)
    return self:IsGUIDLocked(self:GetItemGUID(itemLocation))
end

-- The player's note on a locked item, or nil.
function Locking:GetGUIDNote(guid)
    if self:IsGUIDLocked(guid) then
        return GetStore().notes[guid]
    end
end

-- A note belongs to its lock: unlocking removes it.
local function SetLocked(guid, link, locked)
    local store = GetStore()
    store.locks[guid] = locked or nil
    if not locked then
        store.notes[guid] = nil
    end

    if Locking:GetSetting("announce") then
        local message = locked and L["inventory.locking.locked"] or L["inventory.locking.unlocked"]
        ns:Print(message:format(link))
    end

    ns:RefreshItemButtons()
    ns:RefreshJunk()
end

function Locking:ToggleLock(itemLocation)
    local guid = self:GetItemGUID(itemLocation)
    if guid then
        SetLocked(guid, C_Item.GetItemLink(itemLocation), not GetStore().locks[guid])
    end
end

-- Blank text removes the note and keeps the lock; a note on an unlocked item locks it.
function Locking:SetNote(guid, link, text)
    local note = strtrim(text)
    local store = GetStore()
    if note == "" then
        store.notes[guid] = nil
        return
    end

    store.notes[guid] = note
    if not store.locks[guid] then
        SetLocked(guid, link, true)
    end
end
