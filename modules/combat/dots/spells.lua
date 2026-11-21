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
--
-- A mark (Death Mark) stores part of the damage the player deals its target
-- and deals it at once when it ends, up to a cap. Its description lists, per
-- combo point, the share stored and the cap ("5 points: 60% stored, 1,976
-- damage cap"), the cap including the player's attack power and critical
-- strike chance. What the player deals the target can't be seen in combat, so
-- what the mark stores is predicted: the followed effects' ticks (measured.lua
-- says which it stores more of), the strikes cast (a strike's average damage
-- from its data and the weapons read before combat, or a finishing move's from
-- its description, crits counted at the player's chance), and the average
-- damage of white swings while the player attacks the target. The tracker
-- takes off what the target's armor stops of strikes and swings (armor.lua).

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

-- A mark's share stored (percent) and cap on each line, in order, once
-- no-break spaces are plain spaces.
local MARK_PATTERNS = {
    enUS = "(%d+)%% stored, (%d[%d,]*) damage cap",
    frFR = "(%d+) %% des dégâts accumulés, limite de dégâts de (%d[%d ]*)",
}

-- A finishing strike's lowest and highest damage on each line, in order, once
-- no-break spaces are plain spaces.
local STRIKE_PATTERNS = {
    enUS = "(%d[%d,]*)%-(%d[%d,]*) damage",
    frFR = "(%d[%d ]*)%-(%d[%d ]*)points? de dégâts",
}

-- The speed a normalized strike adds attack power at, by weapon (one-handed
-- weapons the marks' class wields).
local NORMALIZED_SPEED = { dagger = 1.7, other = 2.4 }

-- Attack power adds 1 damage per 14 per second of weapon speed.
local ATTACK_POWER_PER_DAMAGE = 14

-- No-break space and narrow no-break space, in UTF-8.
local NO_BREAK_SPACES = { "\194\160", "\226\128\175" }

-- Spell name -> definition: { key, tick, school, spellPower, comboPoints, ranks,
-- attackPower, talentsRaiseBonus, talents, durations }. Built on first use
-- (names need the spell data).
local spellsByName
-- Spell name -> data.lua's amplifier entry.
local amplifiersByName
-- Spell name -> mark definition: { key, duration, comboPoints, stores }.
local marksByName
-- Spell name -> strike definition: { key, hand, normalized, comboPoints, ranks, talents }.
local strikesByName
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
    spellsByName, amplifiersByName, marksByName, strikesByName, names = {}, {}, {}, {}, {}
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
    for spellID, mark in pairs(DoTs.Data.marks) do
        local name = C_Spell.GetSpellName(spellID)
        local measured = DoTs.Measured.marks[mark.key]
        if name and measured then
            names[mark.key] = name
            marksByName[name] = {
                key = mark.key,
                duration = mark.duration,
                comboPoints = mark.comboPoints,
                stores = measured.stores,
            }
        end
    end
    local strikeTalents = ByKey({ DoTs.Data.strikeTalents })
    for spellID, strike in pairs(DoTs.Data.strikes) do
        local name = C_Spell.GetSpellName(spellID)
        if name then
            strikesByName[name] = {
                key = strike.key,
                hand = strike.hand,
                normalized = strike.normalized,
                comboPoints = strike.comboPoints,
                ranks = strike.ranks,
                talents = strikeTalents[strike.key] or {},
            }
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

-- The definition of a spell marking its target, or nil.
function Spells:GetMark(spellID)
    if not marksByName then
        Build()
    end
    return marksByName[C_Spell.GetSpellName(spellID)]
end

-- The definition of a direct damage spell a mark stores, or nil.
function Spells:GetStrike(spellID)
    if not strikesByName then
        Build()
    end
    return strikesByName[C_Spell.GetSpellName(spellID)]
end

-- The name of the damage over time spell or mark `key` (every rank shares it).
function Spells:GetName(key)
    if not names then
        Build()
    end
    return names[key]
end

-- Spell ID -> its description, as last read while it wasn't secret.
local descriptions = {}

-- The two numbers `patterns` (by locale) captures on the description's line
-- `line`, or nil.
local function ReadDescription(spellID, line, patterns)
    local description = C_Spell.GetSpellDescription(spellID)
    if description and issecretvalue(description) then
        description = descriptions[spellID]
    elseif description then
        descriptions[spellID] = description
    end
    if not description then
        return nil
    end
    for _, space in ipairs(NO_BREAK_SPACES) do
        description = description:gsub(space, " ")
    end
    local index = 0
    for first, second in description:gmatch(patterns[GetLocale()] or patterns.enUS) do
        index = index + 1
        if index == line then
            return tonumber((first:gsub("%D", ""))), tonumber((second:gsub("%D", "")))
        end
    end
    return nil
end

-- The share of the damage the rank `spellID` of a mark stores with `points`
-- combo points (0.6 for 60%), and its cap; nil when its description doesn't say.
function Spells:ReadMark(spellID, points)
    local percent, cap = ReadDescription(spellID, points, MARK_PATTERNS)
    if not percent then
        return nil
    end
    return percent / 100, cap
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
        total, duration = ReadDescription(spellID, points, PATTERNS)
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

-- The average damage of the player's weapon in `hand`, attack power added at
-- the normalized speed if `normalized`; nil without a weapon.
local function WeaponDamage(hand, normalized)
    local weapon = DoTs.Stats:GetWeapon(hand)
    if not weapon then
        return nil
    end
    local damage = (weapon.low + weapon.high) / 2
    if normalized then
        local speed = weapon.dagger and NORMALIZED_SPEED.dagger or NORMALIZED_SPEED.other
        damage = damage + DoTs.Stats:GetAttackPower() * (speed - weapon.speed) / ATTACK_POWER_PER_DAMAGE
    end
    return damage
end

-- The average damage a landed cast of the rank `spellID` of the strike
-- `definition` deals with `points` combo points, crits included; nil when it
-- can't be told (a rank the data doesn't list, no weapon in the hand it strikes
-- with, a description that doesn't say).
function Spells:ReadStrike(definition, spellID, points)
    DoTs.Stats:Refresh()
    local damage
    if definition.ranks then
        local rank = definition.ranks[spellID]
        if not rank then
            return nil
        end
        local flat, percent, daggerPercent = rank[1], rank[2], rank[3]
        local main = DoTs.Stats:GetWeapon("main")
        if daggerPercent and main and main.dagger then
            percent = daggerPercent
        end
        if definition.hand then
            local weapon = WeaponDamage(definition.hand, definition.normalized)
            if not weapon then
                return nil
            end
            damage = (weapon + flat) * percent
        else
            damage = flat * percent
        end
    else
        local low, high = ReadDescription(spellID, points, STRIKE_PATTERNS)
        if not low then
            return nil
        end
        damage = (low + high) / 2
    end
    return damage * (1 + SumTalents(definition.talents)) * (1 + DoTs.Stats:GetCritChance())
end

-- The average damage the player's white swings deal per second, the share
-- that lands and crits included.
function Spells:GetSwingDamagePerSecond()
    DoTs.Stats:Refresh()
    local perSecond = 0
    for _, hand in ipairs({ "main", "off" }) do
        local weapon = DoTs.Stats:GetWeapon(hand)
        if weapon then
            perSecond = perSecond + WeaponDamage(hand, false) / weapon.speed
        end
    end
    return perSecond * DoTs.Measured.swingsLanded * (1 + DoTs.Stats:GetCritChance())
end
