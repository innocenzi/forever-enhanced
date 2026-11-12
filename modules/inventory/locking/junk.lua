-- Sell All Junk and auto selling (core/junk.lua) keep locked items. With
-- "sellUnlockedJunk" off, Sell All Junk is cancelled instead when some junk is locked.

local _, ns = ...

local Locking = ns:GetFeature("inventory", "locking")

ns:AddJunkHandler(Locking, {
    IsKept = function(itemLocation)
        return Locking:IsLocked(itemLocation)
    end,
    CanSellAroundKept = function()
        return Locking:GetSetting("sellUnlockedJunk")
    end,
})
