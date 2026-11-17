-- What an icon matches: its file name (Macros.NAMES), and the names of the
-- player's spells and items showing it (spellbook, bags, equipment), so a
-- search in the player's language finds their own icons too.

local _, ns = ...

local Macros = ns:GetFeature("interface", "macros")

local Names = {}
Macros.Names = Names

-- The lowercased words of the search.
local terms = {}
-- The file IDs whose file name holds every word of the search.
local matchingFiles = {}
-- Icon → the lowercased names of the player's spells and items showing it, one per line.
local ownNames = {}

local function HasAllTerms(text)
    for _, term in ipairs(terms) do
        if not text:find(term, 1, true) then
            return false
        end
    end
    return true
end

-- Reads Macros.NAMES through, decoding each name (tools/icons.ts, encodeIcons):
-- a base 36 file ID, a letter for how many characters it shares with the name
-- before (A for none), then the rest of the name. Keeps only the matches.
local function FindMatchingFiles()
    wipe(matchingFiles)
    local name = ""
    for id, shared, rest in Macros.NAMES:gmatch("([%l%d]+)(%u)([^\n]*)") do
        name = name:sub(1, shared:byte() - 65) .. rest
        if HasAllTerms(name) then
            matchingFiles[tonumber(id, 36)] = true
        end
    end
end

-- An icon is a file ID, or a path for the few icons the client names (Interface\Icons\<name>).
local function MatchesFileName(icon)
    if type(icon) == "number" then
        return matchingFiles[icon] == true
    end
    if type(icon) == "string" then
        return HasAllTerms((icon:match("([^\\/]+)$") or icon):lower())
    end
    return false
end

local function AddOwnName(icon, name)
    if icon and name and name ~= "" then
        name = name:lower()
        ownNames[icon] = ownNames[icon] and ownNames[icon] .. "\n" .. name or name
    end
end

local function CollectOwnNames()
    wipe(ownNames)
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local spell = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
            if spell then
                AddOwnName(spell.iconID, spell.name)
            end
        end
    end
    ns.Containers:ForEachSlot(ns.Containers.BAG_IDS, function(bagID, slot)
        local item = C_Container.GetContainerItemInfo(bagID, slot)
        if item then
            AddOwnName(item.iconFileID, item.itemName)
        end
    end)
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            AddOwnName(GetInventoryItemTexture("player", slot), C_Item.GetItemNameByID(itemID))
        end
    end
end

-- Readies a search for every one of the (lowercased) words, before Matches.
function Names:Search(words)
    terms = words
    FindMatchingFiles()
    CollectOwnNames()
end

-- Whether the icon's file name, or its spells and items' names, hold every word of the search.
function Names:Matches(icon)
    local own = ownNames[icon]
    return MatchesFileName(icon) or (own ~= nil and HasAllTerms(own))
end
