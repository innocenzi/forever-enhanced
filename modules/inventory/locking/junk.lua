-- Sell All Junk and auto selling (core/junk.lua) keep locked items.

local _, ns = ...

local Locking = ns:GetFeature("inventory", "locking")

ns:AddJunkHandler(Locking, {
    IsKept = function(itemLocation)
        return Locking:IsLocked(itemLocation)
    end,
})
