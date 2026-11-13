-- The player's attack power, spell power and talent ranks, which raise what the
-- effects deal. Attack power is secret in combat (measured), spell power most
-- likely too: they are read whenever they can be (as a cast is read out of
-- combat, last as combat starts, before the lockdown) and what was read last
-- is kept for the fight. Talents only change out of combat, with their own
-- events.

local _, ns = ...

local DoTs = ns:GetFeature("combat", "dots")

local Stats = {}
DoTs.Stats = Stats

-- GetSpellBonusDamage's schools: holy, fire, nature, frost, shadow, arcane
-- (1, physical, has none).
local FIRST_SPELL_SCHOOL, LAST_SPELL_SCHOOL = 2, 7

local attackPower = 0
-- School -> spell power.
local spellPower = {}
-- Talent spell ID -> rank, for the talents learned.
local talentRanks = {}

local function ReadPower()
    if InCombatLockdown() then
        return
    end
    local base, positive, negative = UnitAttackPower("player")
    if not (issecretvalue(base) or issecretvalue(positive) or issecretvalue(negative)) then
        attackPower = base + positive + negative
    end
    for school = FIRST_SPELL_SCHOOL, LAST_SPELL_SCHOOL do
        local power = GetSpellBonusDamage(school)
        if not issecretvalue(power) then
            spellPower[school] = power
        end
    end
end

-- Walks the active talent tree: talents are traits on Forever.
local function ReadTalents()
    local configID = C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    if not config then
        return
    end
    local ranks = {}
    for _, treeID in ipairs(config.treeIDs) do
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID)) do
            local node = C_Traits.GetNodeInfo(configID, nodeID)
            if node and node.currentRank > 0 and node.activeEntry then
                local entry = C_Traits.GetEntryInfo(configID, node.activeEntry.entryID)
                local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                if definition and definition.spellID then
                    ranks[definition.spellID] = node.currentRank
                end
            end
        end
    end
    talentRanks = ranks
end

local listener = ns:CreateEventListener({
    -- Fires just before the lockdown: the last chance to read them.
    PLAYER_REGEN_DISABLED = ReadPower,
    -- The talent tree loads after login.
    TRAIT_CONFIG_LIST_UPDATED = ReadTalents,
    TRAIT_CONFIG_UPDATED = ReadTalents,
})

-- Reads attack and spell power again, when they can be read.
function Stats:Refresh()
    ReadPower()
end

function Stats:GetAttackPower()
    return attackPower
end

-- The spell power of a school (GetSpellBonusDamage's index), 0 for physical.
function Stats:GetSpellPower(school)
    return spellPower[school] or 0
end

-- The rank of the talent whose spell is `spellID`, 0 when not learned.
function Stats:GetTalentRank(spellID)
    return talentRanks[spellID] or 0
end

function Stats:Enable()
    listener:Start()
    ReadPower()
    ReadTalents()
end

function Stats:Disable()
    listener:Stop()
end
