-- Marks the component lines of a crate's Use text. The Use line lists them
-- after "\n", one per line ("- 20 unités d’étoffe de laine", a no-break space
-- after the count in French), in the order of the crate's data (data.lua): the
-- nth line of the tooltip reading "- <count>" is the nth component. A line
-- whose count differs from the data's gets no mark, so a crate changed since
-- the data was generated shows nothing rather than wrong marks.
--
-- A line changes through its font string (<tooltip name>TextLeft<n>, from
-- SharedTooltipTemplates), which keeps its color; Blizzard rewrites it on
-- every rebuild, so a mark is never added twice.

local _, ns = ...

local Crates = ns:GetFeature("inventory", "crates")
local Bank = ns:GetFeature("inventory", "bank")

local Tooltip = {}
Crates.Tooltip = Tooltip

Tooltip.MARKS = {
    bags = "|A:UI-LFG-ReadyMark:14:14|a",
    bank = "|TInterface\\Minimap\\Tracking\\Banker:14:14|t",
    missing = "|A:UI-LFG-PendingMark:14:14|a",
}

-- The count of a component line ("- 20 ...", maybe after a color code); nil for other lines.
local function ComponentCount(line)
    local text = line:gsub("^|c%x%x%x%x%x%x%x%x", ""):gsub("^|cn[^:]*:", ""):gsub("\194\160", " ")
    return tonumber(text:match("^%s*%-%s*(%d+)%s"))
end

local function Mark(component)
    local itemID, need = component[1], component[2]
    local inBags = C_Item.GetItemCount(itemID)
    if inBags >= need then
        return Tooltip.MARKS.bags
    elseif inBags + Bank:CountSavedItem(itemID) >= need then
        return Tooltip.MARKS.bank
    end
    return Tooltip.MARKS.missing
end

-- `text` with a mark before each of its component lines, nil without any; the
-- position of the next component.
local function MarkLines(text, components, position)
    local lines, changed = {}, false
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local count = ComponentCount(line)
        local component = count and components[position]
        if component then
            position = position + 1
            if component[2] == count then
                line = Mark(component) .. " " .. line
                changed = true
            end
        end
        table.insert(lines, line)
    end
    return changed and table.concat(lines, "\n") or nil, position
end

ns:AddItemTooltipHandler(Crates, function(tooltip, data)
    local components = Crates.Data[data.id]
    local name = tooltip:GetName()
    if not components or not name then
        return
    end

    local position = 1
    for index = 1, tooltip:NumLines() do
        local fontString = _G[name .. "TextLeft" .. index]
        local text = fontString and fontString:GetText()
        if type(text) == "string" and not issecretvalue(text) then
            local marked
            marked, position = MarkLines(text, components, position)
            if marked then
                fontString:SetText(marked)
            end
        end
    end
end)
