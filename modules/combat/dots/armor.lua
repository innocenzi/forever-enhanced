-- The share of the player's physical strikes and white swings a unit's armor
-- lets through.
--
-- Armor is secret in combat (and 0 out of it), so a creature's is estimated
-- from what the server would give it (data.lua, from CMaNGOS's Classic
-- database): its NPC class and level's base armor, times its own multiplier
-- when its GUID says which creature it is. Classic's reduction:
-- armor / (armor + 400 + 85 * the attacker's level), at most 75%. Units the
-- data doesn't cover (players, an NPC class without stats) count as warrior
-- NPCs of their level, a hidden level ("??") as a boss's 63 or 10 above the
-- player's. Armor debuffs (Sunder Armor, Expose Armor) and buffs aren't
-- counted.
--
-- Checked in game (build 70959, a level 40 rogue), white swings and strikes
-- against the weapons' average: Feral Crag Coyotes (level 37-38, 1593 to 1709
-- armor: 0.69 to 0.71 through) took 0.69 of it, Crag Coyotes (35-36: 0.72 to
-- 0.74) 0.75, a level 40 Rock Elemental (its 1.5 multiplier: 2946, 0.56)
-- about 0.60.

local _, ns = ...

local DoTs = ns:GetFeature("combat", "dots")

local Armor = {}
DoTs.Armor = Armor

local WARRIOR = 1
local MAX_REDUCTION = 0.75
local BOSS_LEVEL = 63
local HIDDEN_LEVEL_ABOVE = 10

-- The value, or nil when secret.
local function IfReadable(value)
    if value ~= nil and not issecretvalue(value) then
        return value
    end
    return nil
end

-- The NPC ID in the unit's GUID (Creature-0-<server>-<map>-<zoneUID>-<npc>-<spawn>).
local function GetNPCID(unit)
    local guid = IfReadable(UnitGUID(unit))
    if not guid then
        return nil
    end
    local kind, _, _, _, _, npcID = strsplit("-", guid)
    return (kind == "Creature" or kind == "Vehicle") and tonumber(npcID) or nil
end

local function GetLevel(unit, playerLevel)
    local level = IfReadable(UnitLevel(unit)) or playerLevel
    if level > 0 then
        return level
    elseif UnitClassification(unit) == "worldboss" then
        return BOSS_LEVEL
    end
    return playerLevel + HIDDEN_LEVEL_ABOVE
end

-- The unit's estimated armor.
local function GetArmor(unit, playerLevel)
    local classID = not UnitIsPlayer(unit) and IfReadable(select(3, UnitClass(unit)))
    local byLevel = DoTs.Data.armor[classID] or DoTs.Data.armor[WARRIOR]
    local armor = byLevel[math.min(GetLevel(unit, playerLevel), #byLevel)]
    return armor * (DoTs.Data.armorMultipliers[GetNPCID(unit)] or 1)
end

-- The share of the player's physical damage that gets through the unit's armor.
function Armor:GetPassedShare(unit)
    local playerLevel = UnitLevel("player")
    local armor = GetArmor(unit, playerLevel)
    local reduction = armor / (armor + 400 + 85 * playerLevel)
    return 1 - math.min(reduction, MAX_REDUCTION)
end
