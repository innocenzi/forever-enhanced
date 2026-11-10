-- Adds a "Locked" line to the tooltip of locked items, wherever they are shown,
-- then the player's note, set apart by an empty line and quoted like item
-- flavor text. The note shows even with "showTooltip" off: the player wrote it
-- to read it.

local _, ns = ...

local L = ns.L
local Locking = ns:GetFeature("inventory", "locking")

local LINE_COLOR = CreateColor(0.31, 0.76, 0.97)
local NOTE_COLOR = CreateColor(0.69, 0.88, 1)

ns:AddItemTooltipHandler(Locking, function(tooltip, data)
    if Locking:GetSetting("showTooltip") and Locking:IsGUIDLocked(data.guid) then
        tooltip:AddLine(L["inventory.locking.tooltipLine"], LINE_COLOR:GetRGB())
    end

    local note = Locking:GetGUIDNote(data.guid)
    if note then
        local r, g, b = NOTE_COLOR:GetRGB()
        tooltip:AddLine(" ")
        tooltip:AddLine(L["inventory.locking.noteLine"]:format(note), r, g, b, true)
    end
end)
