-- Adds "7 in the bank" to item tooltips, wherever they are shown, from this
-- character's saved bank (updated live while the bank is open).

local _, ns = ...

local Bank = ns:GetFeature("inventory", "bank")

ns:AddItemTooltipHandler(Bank, function(tooltip, data)
    if not Bank:GetSetting("tooltipCount") or not data.id then
        return
    end

    local count = Bank.Store:CountItem(Bank.Store:GetPlayerKey(), data.id)
    if count > 0 then
        tooltip:AddLine(Bank:FormatCount(count))
    end
end)
