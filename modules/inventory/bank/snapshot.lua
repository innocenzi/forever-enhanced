-- Saves the character bank while a banker is open: when it opens, then after
-- every change, at most once per frame. Bank contents only exist on the client
-- while the bank is open, so the saved copy is the last state seen there.
-- Also the slice's source of truth for "Blizzard's bank is open": the saved
-- bank and its tab give way to it.

local _, ns = ...

local Bank = ns:GetFeature("inventory", "bank")

local Snapshot = {}
Bank.Snapshot = Snapshot

local bankOpen = false
local captureScheduled = false

local function CaptureTab(tabData)
    local tab = { size = C_Container.GetContainerNumSlots(tabData.ID), items = {} }
    for slot = 1, tab.size do
        local info = C_Container.GetContainerItemInfo(tabData.ID, slot)
        if info then
            tab.items[slot] = {
                link = info.hyperlink,
                count = info.stackCount,
                icon = info.iconFileID,
                quality = info.quality,
                itemID = info.itemID,
                isBound = info.isBound,
                name = info.itemName,
            }
        end
    end
    return tab
end

-- The bag placed in bank tab `tabNumber` (tab 1 is the bank itself).
local function CaptureBag(tabsData, tabNumber)
    local bag = { purchased = tabsData[tabNumber] ~= nil }
    local location = ItemLocation:CreateFromBagAndSlot(Enum.BagIndex.Characterbanktab, tabNumber)
    if C_Item.DoesItemExist(location) then
        bag.link = C_Item.GetItemLink(location)
        bag.icon = C_Item.GetItemIcon(location)
        bag.quality = C_Item.GetItemQuality(location)
    end
    return bag
end

local function Capture()
    captureScheduled = false
    if not bankOpen or not Bank:IsActive() or not C_Bank.CanViewBank(Enum.BankType.Character) then
        return
    end

    local _, class = UnitClass("player")
    local record = {
        name = UnitName("player"),
        class = class,
        realm = Bank.Store:GetRealm(),
        tabs = {},
        bags = {},
    }

    local tabsData = C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character) or {}
    for index, tabData in ipairs(tabsData) do
        record.tabs[index] = CaptureTab(tabData)
    end
    for tabNumber = 2, C_Bank.FetchMaxNumBankTabs(Enum.BankType.Character) do
        record.bags[tabNumber] = CaptureBag(tabsData, tabNumber)
    end

    Bank.Store:Save(record)
end

local function RequestCapture()
    if bankOpen and not captureScheduled then
        captureScheduled = true
        C_Timer.After(0, Capture)
    end
end

local listener = ns:CreateEventListener({
    BANKFRAME_OPENED = function()
        bankOpen = true
        Bank.View:Close()
        Bank.Tab:Refresh()
        RequestCapture()
    end,
    BANKFRAME_CLOSED = function()
        bankOpen = false
        Bank.Tab:Refresh()
    end,
    BAG_UPDATE_DELAYED = RequestCapture,
    BAG_CONTAINER_UPDATE = RequestCapture,
    PLAYERBANKSLOTS_CHANGED = RequestCapture,
    BANK_TABS_CHANGED = RequestCapture,
})

-- BankFrame shows (and opens the bags) before addons get BANKFRAME_OPENED.
function Snapshot:IsBankOpen()
    return bankOpen or BankFrame:IsShown()
end

function Snapshot:Enable()
    bankOpen = BankFrame:IsShown()
    listener:Start()
    RequestCapture()
end

function Snapshot:Disable()
    listener:Stop()
    bankOpen = false
end
