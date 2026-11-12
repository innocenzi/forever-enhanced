-- Item buttons (core/itembuttons.lua): the lock indicator (see indicators.lua),
-- Alt Left Click to toggle the lock (unless Item marks' "altClick" gives it to
-- a mark), the lock and note entries of the item
-- menu, and the click shield over locked items:
--   * while the cursor holds an item: no swapping them out;
--   * while a merchant, mail, trade or auction window is open: no right-click
--     selling, attaching or posting.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local function OnLockedItemTouched(itemLocation, mouseButton)
    if Locking:IsLocked(itemLocation) then
        local isSelling = mouseButton == "RightButton" and MerchantFrame:IsShown()
        ns:Error(isSelling and L["inventory.locking.cannotSell"] or Locking:GetIsLockedMessage())
    end
end

ns:AddItemButtonHandler(Locking, {
    Update = function(button, _, guid)
        local locked = Locking:IsGUIDLocked(guid)
        Locking.Indicators:Update(button, locked and Locking:GetSetting("indicator") or "none")
    end,
    IsGuarded = function(guid, context)
        return context.protect and Locking:IsGUIDLocked(guid)
    end,
    OnGuardedClick = OnLockedItemTouched,
    OnGuardedDrag = OnLockedItemTouched,
    OnAltClick = function(itemLocation)
        if Locking:AltClickLocks() then
            Locking:ToggleLock(itemLocation)
        end
    end,
    -- Entries act only while the item the menu was opened on is still in its slot.
    -- The lock checkbox comes last, next to the other features' checkboxes.
    AddMenuEntries = function(rootDescription, itemLocation, guid)
        local key = Locking:GetGUIDNote(guid) and "inventory.locking.editNote" or "inventory.locking.addNote"
        rootDescription:CreateButton(L[key], function()
            Locking:EditNote(itemLocation, guid)
        end)

        rootDescription:CreateCheckbox(L["inventory.locking.lock"], function()
            return Locking:IsGUIDLocked(guid)
        end, function()
            if Locking:GetItemGUID(itemLocation) == guid then
                Locking:ToggleLock(itemLocation)
            end
        end)
    end,
})
