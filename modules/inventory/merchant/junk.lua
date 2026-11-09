-- Sells the junk Sell All Junk Items would sell, keeping locked items.
--
-- Without locked junk, Blizzard's C_MerchantFrame.SellAllJunkItems() sells it
-- all in one server call. It can't skip items, so with locked junk the rest is
-- sold one C_Container.UseContainerItem per item, as a right-click at the
-- merchant would (like Item Locking's Sell All Junk).

local _, ns = ...

local L = ns.L
local Merchant = ns:GetFeature("inventory", "merchant")
local Locking = ns:GetFeature("inventory", "locking")

local Junk = {}
Merchant.Junk = Junk

local function GetSellValue(info)
    local sellPrice = select(11, C_Item.GetItemInfo(info.itemID))
    return (sellPrice or 0) * info.stackCount
end

-- Sells the junk and returns the money it should bring (0 when nothing is sold).
function Junk:Sell()
    if not Merchant:GetSetting("autoSellJunk") then
        return 0
    end

    local unlocked, lockedCount = Locking:CollectUnlockedJunk()
    if #unlocked == 0 then
        return 0
    end

    local value = 0
    for _, junk in ipairs(unlocked) do
        value = value + GetSellValue(junk.info)
    end

    if lockedCount == 0 and C_MerchantFrame.IsSellAllJunkEnabled() then
        C_MerchantFrame.SellAllJunkItems()
    else
        for _, junk in ipairs(unlocked) do
            C_Container.UseContainerItem(junk.bagID, junk.slot)
        end
    end

    Merchant:Announce(L["inventory.merchant.sold"]:format(#unlocked, GetMoneyString(value, true)))
    return value
end
