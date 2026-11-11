-- How much of a recipe's reagents the bags hold: all of them (the recipe can be
-- crafted at least once), some (at least one of its reagents), or none. Tools
-- and crafting stations aren't reagents and don't count.

local _, ns = ...

local Reagents = ns:GetFeature("professions", "reagents")

local Stock = {}
Reagents.Stock = Stock

Stock.ALL = 1
Stock.SOME = 2
Stock.NONE = 3

-- Recipe spell ID -> { [itemID] = quantity }, the data turned around, built on
-- first use. A recipe of two professions is listed under each with the same
-- reagents.
local reagentsBySpell

local function GetReagentsBySpell()
    if not reagentsBySpell then
        reagentsBySpell = {}
        for itemID, uses in pairs(Reagents.Data) do
            for _, use in ipairs(uses) do
                local spellID = use[1]
                reagentsBySpell[spellID] = reagentsBySpell[spellID] or {}
                reagentsBySpell[spellID][itemID] = use[3]
            end
        end
    end
    return reagentsBySpell
end

-- Stock.ALL, Stock.SOME or Stock.NONE for recipe spellID.
function Stock:GetLevel(spellID)
    local all, some = true, false
    for itemID, quantity in pairs(GetReagentsBySpell()[spellID]) do
        local count = C_Item.GetItemCount(itemID)
        if count > 0 then
            some = true
        end
        if count < quantity then
            all = false
        end
    end
    if all then
        return Stock.ALL
    end
    return some and Stock.SOME or Stock.NONE
end
