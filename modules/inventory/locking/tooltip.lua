-- Adds a "Locked" line to the tooltip of locked items, wherever they are shown.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local Tooltip = {}
Locking.Tooltip = Tooltip

local LOCK_ICON = CreateAtlasMarkup("QuestSharing-Padlock", 12, 12)
local LINE_COLOR = CreateColor(0.31, 0.76, 0.97)

local installed = false

local function OnItemTooltip(tooltip, data)
    if not Locking:IsActive() or not Locking:GetSetting("showTooltip") then
        return
    end

    if data and Locking:IsGUIDLocked(data.guid) then
        tooltip:AddLine(LOCK_ICON .. " " .. L["inventory.locking.tooltipLine"], LINE_COLOR:GetRGB())
    end
end

-- Tooltip post-calls can't be removed: register once, the callback checks IsActive().
function Tooltip:Enable()
    if installed then
        return
    end
    installed = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end
