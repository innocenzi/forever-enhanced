-- The recipes of our data this character knows, saved per character
-- (known[spellID] = true). The client tells whether a recipe is learned only
-- for the profession whose window is open, so every list update of that window
-- records its recipes, and a recipe learned anywhere else is added as it is
-- learned. A recipe counts as known only while its profession is still one of
-- the character's: dropping a profession forgets its recipes in the game.

local _, ns = ...

local Reagents = ns:GetFeature("professions", "reagents")

local Known = {}
Reagents.Known = Known

-- The recipe spells of our data, as a set, built on first use.
local recipeSpells

local function GetRecipeSpells()
    if not recipeSpells then
        recipeSpells = {}
        for _, uses in pairs(Reagents.Data) do
            for _, use in ipairs(uses) do
                recipeSpells[use[1]] = true
            end
        end
    end
    return recipeSpells
end

local function GetStore()
    local store = Reagents:GetCharacterStore()
    store.known = store.known or {}
    return store.known
end

-- Records what the open profession window says of each recipe it lists. The
-- list is filtered (unlearned recipes hidden, search text), so recipes it
-- leaves out keep their state.
local function ReadOpenProfession()
    local known = GetStore()
    local recipes = GetRecipeSpells()
    for _, recipeID in ipairs(C_TradeSkillUI.GetFilteredRecipeIDs()) do
        if recipes[recipeID] then
            local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
            if info then
                known[recipeID] = info.learned or nil
            end
        end
    end
end

local listener = ns:CreateEventListener({
    TRADE_SKILL_LIST_UPDATE = ReadOpenProfession,
    NEW_RECIPE_LEARNED = function(_, recipeID)
        if GetRecipeSpells()[recipeID] then
            GetStore()[recipeID] = true
        end
    end,
})

function Known:Start()
    listener:Start()
end

function Known:Stop()
    listener:Stop()
end

-- Whether this character knows recipe spellID of skillLine, given the skill
-- lines it has learned (Reagents:GetPlayerSkillLines()).
function Known:IsKnown(spellID, skillLine, playerSkillLines)
    return playerSkillLines[skillLine] == true and GetStore()[spellID] == true
end
