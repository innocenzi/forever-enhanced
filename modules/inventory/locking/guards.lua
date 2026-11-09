-- Cursor guard: whatever picked up a locked item (click, drag, keybind, another
-- bag addon, the character frame), put it back on the next frame. Destroying an
-- item needs it on the cursor, so this also prevents deletion.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local Guards = {}
Locking.Guards = Guards

local returnScheduled = false

local function ReturnLockedCursorItem()
    returnScheduled = false

    local itemLocation = C_Cursor.GetCursorItem()
    if itemLocation and Locking:IsLocked(itemLocation) then
        ClearCursor()
        ns:Error(L["inventory.locking.isLocked"])
    end
end

local listener = ns:CreateEventListener({
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
end

function Guards:Disable()
    listener:Stop()
end
