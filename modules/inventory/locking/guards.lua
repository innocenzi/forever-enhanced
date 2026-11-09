-- Guards that don't depend on item buttons.
--
-- Cursor guard: whatever picked up a locked item (click, drag, keybind,
-- another bag addon, the character frame), put it back on the next frame. Destroying
-- an item needs it on the cursor, so this also prevents deletion.
--
-- Sell All Junk guard: the merchant's Sell All Junk sells every poor-quality
-- item in one server call, so cancel its confirmation while locked junk exists.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local Guards = {}
Locking.Guards = Guards

local SELL_ALL_JUNK_CLICKED = "MerchantFrame.SellAllJunkButtonClicked"

local function HasLockedJunk()
    for bagID = Enum.BagIndex.Backpack, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bagID) do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if
                info
                and info.quality == Enum.ItemQuality.Poor
                and not info.hasNoValue
                and Locking:IsLocked(ItemLocation:CreateFromBagAndSlot(bagID, slot))
            then
                return true
            end
        end
    end
    return false
end

local function OnSellAllJunkClicked()
    if HasLockedJunk() then
        StaticPopup_Hide("GENERIC_CONFIRMATION")
        ns:Error(L["inventory.locking.sellJunkBlocked"])
    end
end

local returnScheduled = false

local function ReturnLockedCursorItem()
    returnScheduled = false

    local itemLocation = C_Cursor.GetCursorItem()
    if itemLocation and Locking:IsLocked(itemLocation) then
        ClearCursor()
        ns:Error(L["inventory.locking.isLocked"])
    end
end

local listener = ns.CreateEventListener({
    -- CURSOR_CHANGED fires synchronously from inside the pickup call. Clearing
    -- the cursor there interrupts the client mid-pickup and can leave the slot
    -- stuck, so put the item back on the next frame instead.
    CURSOR_CHANGED = function()
        if not returnScheduled then
            returnScheduled = true
            C_Timer.After(0, ReturnLockedCursorItem)
        end
    end,
})

function Guards:Enable()
    listener:Start()
    EventRegistry:RegisterCallback(SELL_ALL_JUNK_CLICKED, OnSellAllJunkClicked, self)
end

function Guards:Disable()
    listener:Stop()
    EventRegistry:UnregisterCallback(SELL_ALL_JUNK_CLICKED, self)
end
