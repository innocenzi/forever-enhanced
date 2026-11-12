-- What Sell All Junk sells: Blizzard's junk (poor quality items with a sell
-- price, in bags not excluded from Sell All Junk), plus the items features add,
-- minus the items features keep, through handlers registered here.
--
-- C_MerchantFrame.SellAllJunkItems() sells Blizzard's junk in one server call
-- and can't add or skip items. So when a feature adds or keeps some, we replace
-- Blizzard's confirmation with our own, and on accept sell the junk ourselves,
-- one C_Container.UseContainerItem per item, as a right-click at the merchant
-- would. Otherwise Blizzard's own sale runs untouched.
--
-- Blizzard's button is disabled without poor items: we enable it while
-- features add junk.

local _, ns = ...

local L = ns.L

local SELL_ALL_JUNK_CLICKED = "MerchantFrame.SellAllJunkButtonClicked"

-- { feature, handler } in registration order. Handler fields, all optional:
--   IsJunk(itemLocation, info)  true adds a sellable item that isn't poor quality
--   IsKept(itemLocation)        true keeps a junk item
--   CanSellAroundKept()         false cancels Sell All Junk when an item is kept
-- info is the slot's C_Container.GetContainerItemInfo. Only handlers of active
-- features are called; call ns:RefreshJunk() when what a handler adds or keeps changes.
local handlers = {}

function ns:AddJunkHandler(feature, handler)
    table.insert(handlers, { feature = feature, handler = handler })
end

local function AnyActive(field, ...)
    for _, entry in ipairs(handlers) do
        local method = entry.handler[field]
        if method and entry.feature:IsActive() and method(...) then
            return true
        end
    end
    return false
end

local function CanSellAroundKept()
    for _, entry in ipairs(handlers) do
        local method = entry.handler.CanSellAroundKept
        if method and entry.feature:IsActive() and not method() then
            return false
        end
    end
    return true
end

-- Mirrors Blizzard's Sell All Junk: the bag's "exclude from Sell All Junk" option.
local function IsBagExcluded(bagID)
    if bagID == Enum.BagIndex.Backpack then
        return C_Container.GetBackpackSellJunkDisabled()
    end
    return C_Container.GetBagSlotFlag(bagID, Enum.BagSlotFlags.ExcludeJunkSell)
end

-- Returns the junk to sell, { { bagID, slot, info } ... }, then how many junk
-- items features keep and how many of those to sell they add.
function ns:CollectJunk()
    local junk, keptCount, addedCount = {}, 0, 0
    for _, bagID in ipairs(ns.Containers.BAG_IDS) do
        if not IsBagExcluded(bagID) then
            for slot = 1, C_Container.GetContainerNumSlots(bagID) do
                local info = C_Container.GetContainerItemInfo(bagID, slot)
                if info and not info.hasNoValue then
                    local itemLocation = ItemLocation:CreateFromBagAndSlot(bagID, slot)
                    local isPoor = info.quality == Enum.ItemQuality.Poor
                    if isPoor or AnyActive("IsJunk", itemLocation, info) then
                        if AnyActive("IsKept", itemLocation) then
                            keptCount = keptCount + 1
                        else
                            addedCount = addedCount + (isPoor and 0 or 1)
                            table.insert(junk, { bagID = bagID, slot = slot, info = info })
                        end
                    end
                end
            end
        end
    end
    return junk, keptCount, addedCount
end

-- Re-collects on accept: bags may have changed while the confirmation was up.
local function SellJunk()
    if not MerchantFrame:IsShown() then
        return
    end
    for _, item in ipairs((ns:CollectJunk())) do
        C_Container.UseContainerItem(item.bagID, item.slot)
    end
end

local function OnSellAllJunkClicked()
    local junk, keptCount, addedCount = ns:CollectJunk()
    if keptCount == 0 and addedCount == 0 then
        return -- exactly Blizzard's junk: its own sale runs
    end

    StaticPopup_Hide("GENERIC_CONFIRMATION")

    if keptCount > 0 and not CanSellAroundKept() then
        ns:Error(L["core.junk.sellBlocked"])
    elseif #junk == 0 then
        ns:Error(L["core.junk.allKept"])
    elseif keptCount > 0 then
        StaticPopup_ShowCustomGenericConfirmation({
            text = L["core.junk.sellConfirmKept"],
            text_arg1 = #junk,
            text_arg2 = keptCount,
            callback = SellJunk,
        })
    else
        StaticPopup_ShowCustomGenericConfirmation({
            text = L["core.junk.sellConfirm"],
            text_arg1 = #junk,
            callback = SellJunk,
        })
    end
end

-- Blizzard enables Sell All Junk only with poor items (MerchantFrame_Update):
-- also enable it while features add junk. Writes only when that changes its
-- state. Features call this when what their handler adds or keeps changes.
function ns:RefreshJunk()
    if not MerchantFrame:IsShown() or not MerchantSellAllJunkButton:IsShown() then
        return
    end
    local _, _, addedCount = ns:CollectJunk()
    local hasJunk = C_MerchantFrame.GetNumJunkItems() > 0 or addedCount > 0
    if MerchantSellAllJunkButton:IsEnabled() ~= hasJunk then
        MerchantSellAllJunkButton:SetEnabled(hasJunk)
        MerchantSellAllJunkButton.Icon:SetDesaturated(not hasJunk)
    end
end

-- Both run for every player, and do nothing unless a feature adds or keeps junk.
EventRegistry:RegisterCallback(SELL_ALL_JUNK_CLICKED, OnSellAllJunkClicked, {})
hooksecurefunc("MerchantFrame_Update", function()
    ns:RefreshJunk()
end)
