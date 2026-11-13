-- The damage over time spells followed, and what each tick deals: built from
-- data.lua (generated from the client's data: ticks, combo points, each rank's
-- damage per tick and duration, spell power, talents, amplifiers) and
-- measured.lua (attack power, and data measured to differ). Every rank shares
-- the spell's name, so spells are matched by name.
--
-- A finishing move's base damage depends on the points spent, in a formula the
-- data doesn't hold: it is read from its description, which stays readable in
-- combat and lists one line per combo point ("5 points: 144 damage over 16
-- secs"). Descriptions are game text: parsed by the client's locale. Those
-- lines don't include the talents raising the damage (Rupture's fit Serrated
-- Blades on top, measured), while their durations do include the talents
-- lengthening it (Rupture's formula adds Blood Splatter's; unmeasured). Other
-- descriptions can't serve: the client includes the player's talents in their
-- totals (Garrote's 338 is its data's 282 with Opportunity's 20%).
--
-- A tick deals the base damage per tick and a share of the player's attack
-- power and spell power, the talents raising the base damage and, for most
-- spells, the attack and spell power parts too (measured for Garrote and
-- Rupture, see measured.lua). Ticks are evenly spaced, and talents lengthening
-- the effect add ticks; an amplifier on the target raises whole ticks.

local _, ns = ...

local DoTs = ns:GetFeature("combat", "dots")

local Spells = {}
DoTs.Spells = Spells

-- The total and the duration of each line, in order, once no-break spaces
-- are plain spaces.
local PATTERNS = {
    enUS = "(%d[%d,]*) damage over (%d+) sec",
    frFR = "(%d[%d ]*) points de dégâts en (%d+) s",
}

-- No-break space and narrow no-break space, in UTF-8.
local NO_BREAK_SPACES = { "\194\160", "\226\128\175" }

-- Spell name -> definition: { key, tick, school, spellPower, comboPoints, ranks,
-- attackPower, talentsRaiseBonus, talents, durations }. Built on first use
-- (names need the spell data).
local spellsByName
-- Spell name -> data.lua's amplifier entry.
local amplifiersByName
-- Spell key -> its name.
local names

-- Spell key -> talent spell ID -> value at each rank, from `sources` (talent
-- spell ID -> spell key -> values), the later ones replacing the earlier.
local function ByKey(sources)
    local talents = {}
    for _, source in ipairs(sources) do
        for talentSpellID, bySpell in pairs(source) do
            for key, ranks in pairs(bySpell) do
                talents[key] = talents[key] or {}
                talents[key][talentSpellID] = ranks
            end
        end
    end
    return talents
end

local function Build()
    spellsByName, amplifiersByName, names = {}, {}, {}
    local talents = ByKey({ DoTs.Data.talents, DoTs.Measured.talents })
    local durations = ByKey({ DoTs.Data.durations })
    for spellID, spell in pairs(DoTs.Data.spells) do
        local name = C_Spell.GetSpellName(spellID)
        local measured = DoTs.Measured.spells[spell.key]
        if name and measured then
            names[spell.key] = name
            spellsByName[name] = {
                key = spell.key,
                tick = spell.tick,
                school = spell.school,
                spellPower = spell.spellPower,
                comboPoints = spell.comboPoints,
                ranks = spell.ranks,
                attackPower = measured.attackPower,
                talentsRaiseBonus = measured.talentsRaiseBonus,
                talents = talents[spell.key] or {},
                durations = durations[spell.key] or {},
            }
        end
    end
    for spellID, amplifier in pairs(DoTs.Data.amplifiers) do
        local name = C_Spell.GetSpellName(spellID)
        if name then
            amplifiersByName[name] = amplifier
        end
    end
end

-- The definition of a damage over time spell, or nil.
function Spells:Get(spellID)
    if not spellsByName then
        Build()
    end
    return spellsByName[C_Spell.GetSpellName(spellID)]
end

-- The definition of a spell raising the damage of others, or nil.
function Spells:GetAmplifier(spellID)
    if not amplifiersByName then
        Build()
    end
    return amplifiersByName[C_Spell.GetSpellName(spellID)]
end

-- The name of the damage over time spell `key` (every rank shares it).
function Spells:GetName(key)
    if not names then
        Build()
    end
    return names[key]
end

-- The base damage and duration on the description's line `line`, or nil.
local function ReadDescription(spellID, line)
    local description = C_Spell.GetSpellDescription(spellID)
    if not description then
        return nil
    end
    for _, space in ipairs(NO_BREAK_SPACES) do
        description = description:gsub(space, " ")
    end
    local index = 0
    for total, duration in description:gmatch(PATTERNS[GetLocale()] or PATTERNS.enUS) do
        index = index + 1
        if index == line then
            return tonumber((total:gsub("%D", ""))), tonumber(duration)
        end
    end
    return nil
end

-- The sum of the player's ranks of talents (talent spell ID -> value at each rank).
local function SumTalents(talents)
    local sum = 0
    for talentSpellID, ranks in pairs(talents) do
        sum = sum + (ranks[DoTs.Stats:GetTalentRank(talentSpellID)] or 0)
    end
    return sum
end

-- What each tick of the rank `spellID` of `definition` deals with `points`
-- combo points, and the effect's duration; nil when it can't be told (a rank
-- the data doesn't list, a description that doesn't say).
function Spells:Read(definition, spellID, points)
    local perTick, duration
    if definition.ranks then
        local rank = definition.ranks[spellID]
        if not rank then
            return nil
        end
        perTick, duration = rank[1], rank[2] + SumTalents(definition.durations)
    else
        local total
        total, duration = ReadDescription(spellID, points)
        if not total or duration <= 0 then
            return nil
        end
        perTick = total * definition.tick / duration
    end
    local attackPower = definition.attackPower
    if type(attackPower) == "table" then
        attackPower = attackPower[points] or 0
    end
    DoTs.Stats:Refresh()
    local bonus = DoTs.Stats:GetAttackPower() * attackPower
        + DoTs.Stats:GetSpellPower(definition.school) * definition.spellPower
    local multiplier = 1 + SumTalents(definition.talents)
    if definition.talentsRaiseBonus then
        return (perTick + bonus) * multiplier, duration
    end
    return perTick * multiplier + bonus, duration
end
