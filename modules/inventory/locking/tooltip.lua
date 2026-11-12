-- Adds a "Locked" line to the tooltip of locked items, wherever they are shown.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local LINE_COLOR = CreateColor(0.31, 0.76, 0.97)

ns:AddItemTooltipHandler(Locking, function(tooltip, data)
    if Locking:GetSetting("showTooltip") and Locking:IsGUIDLocked(data.guid) then
        tooltip:AddLine(L["inventory.locking.tooltipLine"], LINE_COLOR:GetRGB())
    end
end)
