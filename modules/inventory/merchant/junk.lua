-- Sells the junk Sell All Junk Items would sell (core/junk.lua: marked items
-- are added, locked items kept).
--
-- When that is exactly Blizzard's junk, C_MerchantFrame.SellAllJunkItems()
-- sells it in one server call. It can't add or skip items, so otherwise the
-- junk is sold one C_Container.UseContainerItem per item, as a right-click at
-- the merchant would.

local _, ns = ...

local L = ns.L
local Merchant = ns:GetFeature("inventory", "merchant")

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

    local junk, keptCount, addedCount = ns:CollectJunk()
    if #junk == 0 then
        return 0
    end

    local value = 0
    for _, item in ipairs(junk) do
        value = value + GetSellValue(item.info)
    end

    if keptCount == 0 and addedCount == 0 and C_MerchantFrame.IsSellAllJunkEnabled() then
        C_MerchantFrame.SellAllJunkItems()
    else
        for _, item in ipairs(junk) do
            C_Container.UseContainerItem(item.bagID, item.slot)
        end
    end

    Merchant:Announce(L["inventory.merchant.sold"]:format(#junk, GetMoneyString(value, true)))
    return value
end
