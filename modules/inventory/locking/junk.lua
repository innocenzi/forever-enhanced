-- Sell All Junk with locked junk.
--
-- C_MerchantFrame.SellAllJunkItems() sells every poor-quality item in one
-- server call and can't skip items; the only official exclusion is per bag.
-- So when the player's junk includes locked items, we replace Blizzard's
-- confirmation with our own, and on accept sell the unlocked junk ourselves,
-- one C_Container.UseContainerItem per item, as a right-click at the merchant
-- would. With "sellUnlockedJunk" off, the sale is cancelled instead.
-- Without locked junk, Blizzard's own sale runs untouched.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local Junk = {}
Locking.Junk = Junk

local SELL_ALL_JUNK_CLICKED = "MerchantFrame.SellAllJunkButtonClicked"

-- Mirrors Blizzard's Sell All Junk: the bag's "exclude from Sell All Junk" option.
local function IsBagExcluded(bagID)
    if bagID == Enum.BagIndex.Backpack then
        return C_Container.GetBackpackSellJunkDisabled()
    end
    return C_Container.GetBagSlotFlag(bagID, Enum.BagSlotFlags.ExcludeJunkSell)
end

-- Mirrors Blizzard's junk definition (ContainerFrameItemButtonMixin:UpdateJunkItem).
local function IsJunk(bagID, slot)
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    return info ~= nil and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue
end

-- Junk Sell All Junk would sell: { unlocked = { { bagID, slot } ... }, lockedCount }.
local function CollectJunk()
    local unlocked, lockedCount = {}, 0
    for _, bagID in ipairs(Locking.BAG_IDS) do
        if not IsBagExcluded(bagID) then
            for slot = 1, C_Container.GetContainerNumSlots(bagID) do
                if IsJunk(bagID, slot) then
                    if Locking:IsLocked(ItemLocation:CreateFromBagAndSlot(bagID, slot)) then
                        lockedCount = lockedCount + 1
                    else
                        table.insert(unlocked, { bagID = bagID, slot = slot })
                    end
                end
            end
        end
    end
    return unlocked, lockedCount
end

-- Re-collects on accept: bags may have changed while the confirmation was up.
local function SellUnlockedJunk()
    if not Locking:IsActive() or not MerchantFrame:IsShown() then
        return
    end
    for _, location in ipairs((CollectJunk())) do
        C_Container.UseContainerItem(location.bagID, location.slot)
    end
end

local function OnSellAllJunkClicked()
    local unlocked, lockedCount = CollectJunk()
    if lockedCount == 0 then
        return
    end

    StaticPopup_Hide("GENERIC_CONFIRMATION")

    if not Locking:GetSetting("sellUnlockedJunk") then
        ns:Error(L["inventory.locking.sellJunkBlocked"])
    elseif #unlocked == 0 then
        ns:Error(L["inventory.locking.allJunkLocked"])
    else
        StaticPopup_ShowCustomGenericConfirmation({
            text = L["inventory.locking.sellJunkConfirm"],
            text_arg1 = #unlocked,
            text_arg2 = lockedCount,
            callback = SellUnlockedJunk,
        })
    end
end

function Junk:Enable()
    EventRegistry:RegisterCallback(SELL_ALL_JUNK_CLICKED, OnSellAllJunkClicked, self)
end

function Junk:Disable()
    EventRegistry:UnregisterCallback(SELL_ALL_JUNK_CLICKED, self)
end
