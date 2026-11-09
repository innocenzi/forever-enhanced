-- Repairs all items at a merchant that can repair.
--
-- Selling junk first can pay for the repair, but its money only arrives once
-- the server confirms each sale: when the player's gold plus the expected sale
-- covers the cost, the repair waits for PLAYER_MONEY until the gold is there
-- (or the merchant closes).

local _, ns = ...

local L = ns.L
local Merchant = ns:GetFeature("inventory", "merchant")

local Repair = {}
Merchant.Repair = Repair

-- GetGuildBankWithdrawMoney() returns -1 when withdrawals are unlimited.
local UNLIMITED_WITHDRAW = -1

-- The player's gold once the junk sale lands, while a repair is due; nil otherwise.
local expectedMoney

-- The repair cost, or nil when there is nothing to repair here.
local function GetCost()
    if not CanMerchantRepair() then
        return nil
    end
    local cost, canRepair = GetRepairAllCost()
    if canRepair and cost > 0 then
        return cost
    end
end

local function CanUseGuildFunds(cost)
    if Merchant:GetSetting("repairFunds") ~= "guild" or not CanGuildBankRepair() then
        return false
    end
    local limit = GetGuildBankWithdrawMoney()
    return limit == UNLIMITED_WITHDRAW or limit >= cost
end

-- Repairs if affordable now. Returns true when the repair should wait for the junk money.
local function TryRepair()
    local cost = GetCost()
    if not cost then
        return false
    end

    local guildFunds = CanUseGuildFunds(cost)
    if guildFunds or GetMoney() >= cost then
        RepairAllItems(guildFunds)
        local message = guildFunds and "inventory.merchant.repairedGuild" or "inventory.merchant.repaired"
        Merchant:Announce(L[message]:format(GetMoneyString(cost, true)))
        return false
    end

    if expectedMoney >= cost then
        return true
    end
    ns:Error(L["inventory.merchant.notEnoughMoney"])
    return false
end

-- A merchant opened; `income` is the money the junk sale should bring.
function Repair:Start(income)
    expectedMoney = Merchant:GetSetting("autoRepair") and GetMoney() + income or nil
    self:Retry()
end

-- Repairs a due repair, or keeps it due while the junk money is on its way.
function Repair:Retry()
    if expectedMoney and not TryRepair() then
        expectedMoney = nil
    end
end

function Repair:Cancel()
    expectedMoney = nil
end
