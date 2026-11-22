-- The withdrawal: when the bank opens, the bank feature brings the bags up to
-- what every plan needs (Bank:WithdrawUpTo), and the plans are forgotten. Once
-- it's done, with "announce", chat lists what came from the bank and what is
-- still missing.

local _, ns = ...

local Plans = ns:GetFeature("professions", "plans")
local Bank = ns:GetFeature("inventory", "bank")

local Withdrawal = {}
Plans.Withdrawal = Withdrawal

local function SortedItemIDs(totals)
    local itemIDs = {}
    for itemID in pairs(totals) do
        table.insert(itemIDs, itemID)
    end
    table.sort(itemIDs)
    return itemIDs
end

local function FormatItem(itemID, count)
    local _, link = C_Item.GetItemInfo(itemID)
    local name = link or C_Item.GetItemNameByID(itemID) or tostring(itemID)
    return ns.L["professions.plans.item"]:format(name, count)
end

-- Chat lines: the items whose bag count went up since `before`, then those still short of `totals`.
local function Announce(totals, before)
    if not Plans:IsActive() or not Plans:GetSetting("announce") then
        return
    end
    local withdrawn, missing = {}, {}
    for _, itemID in ipairs(SortedItemIDs(totals)) do
        local count = C_Item.GetItemCount(itemID)
        if count > before[itemID] then
            table.insert(withdrawn, FormatItem(itemID, count - before[itemID]))
        end
        if count < totals[itemID] then
            table.insert(missing, FormatItem(itemID, totals[itemID] - count))
        end
    end
    if withdrawn[1] then
        ns:Print(ns.L["professions.plans.withdrawn"]:format(table.concat(withdrawn, ", ")))
    end
    if missing[1] then
        ns:Print(ns.L["professions.plans.missing"]:format(table.concat(missing, ", ")))
    end
end

local listener = ns:CreateEventListener({
    BANKFRAME_OPENED = function()
        local totals = Plans:GetTotals()
        if not next(totals) then
            return
        end
        local before = {}
        for itemID in pairs(totals) do
            before[itemID] = C_Item.GetItemCount(itemID)
        end
        if Bank:WithdrawUpTo(totals, function()
            Announce(totals, before)
        end) then
            Plans:ClearPlans()
        end
    end,
})

function Withdrawal:Start()
    listener:Start()
end

function Withdrawal:Stop()
    listener:Stop()
end
