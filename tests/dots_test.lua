-- Damage Over Time to Come: the player's damage over time effects (Garrote
-- and Rupture, Rend, Shadow Word: Pain, Corruption...) show, over the health
-- bar's fill on the target frame and on nameplates, the damage their ticks
-- have yet to deal: each rank's from the data, a finishing move's from its
-- description, raised by attack and spell power read before combat, by
-- talents, and by Hemorrhage on the ticks landing while it lasts; Death Mark
-- adds what it stores of them until it deals it. Casts that
-- miss show nothing (or wait for their combo points), casting again replaces
-- the effect, a spell with a cast time lands on the unit it was cast on, dead
-- units and recycled plates are left, out of combat auras correct the
-- effects, and everything is undone when disabled. Group members who run the
-- addon send each other theirs, which add up.

local GARROTE = 8632 -- a tick every 3 sec
local GARROTE_DAMAGE = 282 -- over 18 sec, before talents and attack power
local RUPTURE = 8639 -- 44 / 63 / 87 / 114 / 144 over 8 to 16 sec, a tick every 2 sec
local RUPTURE_HIGH_RANK = 11275 -- 1032 over 16 sec with 5 points
local HEMORRHAGE = 16511 -- +15% for 15 sec

-- The damage the overlay over the health bar shows (the ticks' and what marks
-- will deal), or 0 without one.
local function Shown(world, healthBar)
    local overlay = world:HealthBarOverlay(healthBar)
    if not overlay then
        return 0
    end
    return overlay.value + (overlay.inner and overlay.inner.value or 0)
end

local function Near(actual, expected, label)
    expect(math.abs(actual - expected) < 0.01, ("%s: expected %s, got %s"):format(label, expected, actual))
end

-- A rogue targeting MOB (1000 health), whose nameplate is shown.
local function Rogue(world)
    world.player.class = "ROGUE"
    local plate = world:ShowNamePlate("MOB")
    world:SetHealth("MOB", 1000, 1000)
    world:Target("MOB")
    return plate
end

test("shows a Garrote's damage over the health left", function(world)
    local plate = Rogue(world)
    world:SetHealth("MOB", 800)
    world:Cast(GARROTE)

    local overlay = world:HealthBarOverlay(world:TargetHealthBar())
    expect(overlay, "shown on the target frame")
    equal(overlay.value, GARROTE_DAMAGE, "the whole damage")
    equal(overlay.range, 800, "out of the health left")
    expect(overlay.fromLeft, "from the left end of the bar")
    expect(overlay.overFill, "over the fill")
    equal(Shown(world, world:NamePlateHealthBar(plate)), GARROTE_DAMAGE, "and on the nameplate")
end)

test("takes each tick off as it lands, then hides", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    world:RunFrames(3.1)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE * 5 / 6, "after the first tick")
    world:RunFrames(12)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE / 6, "before the last tick")
    world:RunFrames(3)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "hidden once the last tick landed")
end)

test("a Rupture deals what the combo points spent give", function(world)
    Rogue(world)
    world:SetComboPoints(3)
    world:Cast(RUPTURE)
    equal(Shown(world, world:TargetHealthBar()), 87, "the 3 points line")
    world:RunFrames(11.9)
    Near(Shown(world, world:TargetHealthBar()), 87 / 6, "lasts the 3 points duration")
    world:RunFrames(0.2)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "then ends")
end)

test("reads large numbers", function(world)
    Rogue(world)
    world:SetHealth("MOB", 5000, 5000)
    world:SetComboPoints(5)
    world:Cast(RUPTURE_HIGH_RANK)
    equal(Shown(world, world:TargetHealthBar()), 1032, "with a thousands separator")
end)

test("a cast that misses shows nothing", function(world)
    Rogue(world)
    for _, miss in ipairs({ "MISS", "DODGE", "PARRY", "IMMUNE" }) do
        world:SetComboPoints(2)
        world:Cast(RUPTURE, miss)
        equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, miss)
    end
end)

test("casting again replaces the effect", function(world)
    Rogue(world)
    world:SetComboPoints(1)
    world:Cast(RUPTURE)
    world:RunFrames(4.1)
    world:SetComboPoints(5)
    world:Cast(RUPTURE)
    equal(Shown(world, world:TargetHealthBar()), 144, "the new Rupture only")
end)

test("Hemorrhage raises the ticks landing while it lasts", function(world)
    Rogue(world)
    world:Cast(HEMORRHAGE)
    world:Cast(GARROTE)
    -- Ticks at 3, 6, 9, 12 and 15 sec land while it lasts, the one at 18 sec after.
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE / 6 * (5 * 1.15 + 1), "raised")

    world:RunFrames(18.1)
    world:Cast(GARROTE)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "no longer once it ended")
end)

test("Hemorrhage only raises the damage on its own target", function(world)
    Rogue(world)
    world:Cast(HEMORRHAGE)
    world:SetHealth("OTHER", 1000, 1000)
    world:Target("OTHER")
    world:Cast(GARROTE)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "not raised")
end)

local DEATH_MARK = 1316709 -- 12% stored per point, caps 165 / 267 / 369 / 471 / 573
local DEATH_MARK_RANK_4 = 1325758 -- caps 401 / 646 / 891 / 1,136 / 1,381

test("what Death Mark will deal shows from the health's end, darkened", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    local overlay = world:HealthBarOverlay(world:TargetHealthBar())
    equal(overlay.inner, nil, "the ticks alone: no mark bar")

    world:SetComboPoints(5)
    world:Cast(DEATH_MARK_RANK_4)
    overlay = world:HealthBarOverlay(world:TargetHealthBar())
    expect(overlay.fromLeft, "the ticks from the left end")
    equal(overlay.value, GARROTE_DAMAGE, "the ticks' part")
    expect(not overlay.inner.fromLeft, "what it will deal from the health's end")
    Near(overlay.inner.value, 2 * 47 * 0.6 * 2, "what it stores")
    equal(overlay.inner.color[4], 0.5, "darkened")
    expect(overlay.inner.aboveFill, "above the ticks' part")

    world:RunFrames(6.1)
    equal(world:HealthBarOverlay(world:TargetHealthBar()).inner, nil, "none once dealt")
end)

test("the ticks' part is animated, in the health bar's color, up to a flare", function(world)
    local plate = Rogue(world)
    local healthBar = world:NamePlateHealthBar(plate)
    healthBar:SetStatusBarColor(0.9, 0.1, 0.2)
    world:Cast(GARROTE)
    local overlay = world:HealthBarOverlay(healthBar)
    equal(overlay.art.tint[1], 0.9, "the nameplate's color")
    equal(overlay.art.tint[2], 0.1, "its green")
    equal(overlay.flare.tint[1], 0.9, "the flare's too")
    equal(#overlay.art.masks, 1, "within its fill")
    local shown = table.concat(overlay.art.texCoord, " ")
    world:RunFrames(0.2)
    expect(table.concat(overlay.art.texCoord, " ") ~= shown, "animated")
    healthBar:SetStatusBarColor(1, 0.9, 0.1)
    world:NextFrame()
    equal(overlay.art.tint[2], 0.9, "follows its color")
    local target = world:HealthBarOverlay(world:TargetHealthBar())
    expect(target.art.tint[2] > target.art.tint[1], "the target frame's green")
    equal(#target.art.masks, 2, "within its fill and the health bar's shape")
end)

test("Death Mark stores a Rupture cast after it, and a replaced one up to then", function(world)
    Rogue(world)
    world:SetComboPoints(5)
    world:Cast(DEATH_MARK_RANK_4)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "nothing stored yet")
    world:SetComboPoints(5)
    world:Cast(RUPTURE)
    -- 18 per tick, at 2, 4 and 6 sec.
    Near(Shown(world, world:TargetHealthBar()), 144 + 3 * 18 * 0.6 * 2, "its ticks in the mark's time")
    world:RunFrames(2.1)
    world:SetComboPoints(1)
    world:Cast(RUPTURE)
    -- The first Rupture's tick at 2 sec, the new one's (11 per tick) at 4.1 sec.
    Near(Shown(world, world:TargetHealthBar()), 44 + (18 + 11) * 0.6 * 2, "the replaced one's landed tick kept")
end)

test("Death Mark stores up to its cap", function(world)
    Rogue(world)
    world:SetHealth("MOB", 5000, 5000)
    world:Cast(GARROTE)
    world:SetComboPoints(5)
    world:Cast(RUPTURE_HIGH_RANK)
    world:SetComboPoints(5)
    world:Cast(DEATH_MARK)
    -- (2 * 47 + 3 * 129) * 1.2 = 577.2, over the 5 points cap.
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE + 1032 + 573, "capped")
end)

test("Death Mark counts the ticks Hemorrhage raised, even once it ended", function(world)
    Rogue(world)
    world:Cast(HEMORRHAGE)
    world:RunFrames(10)
    world:Cast(GARROTE)
    world:SetComboPoints(1)
    world:Cast(DEATH_MARK_RANK_4)
    local stored = 47 * 1.15 * 0.12 * 2 + 47 * 0.12 * 2 -- at 3 sec raised, at 6 sec after it ended
    Near(Shown(world, world:TargetHealthBar()), 47 * 1.15 + 47 * 5 + stored, "while it lasts")
    world:RunFrames(5.9)
    Near(Shown(world, world:TargetHealthBar()), 47 * 5 + stored, "after it ended")
end)

test("a missed Death Mark stores nothing", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    world:SetComboPoints(5)
    world:Cast(DEATH_MARK_RANK_4, "DODGE")
    world:Elapse(1.1)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "the Garrote only")
end)

local SINISTER_STRIKE = 1752 -- normalized weapon damage + 3
local GHOSTLY_STRIKE = 14278 -- 125% normalized weapon damage, 180% with a dagger in the main hand
local SHANK = 1329283 -- 50% off hand weapon damage
local EVISCERATE = 2098 -- 6-10 / 11-15 / 16-20 / 21-25 / 26-30
local AGGRESSION = 18427 -- Sinister Strike and Eviscerate +5% per rank

-- A level 40 player with daggers, 40-60 in the main hand every 1.5 sec, 20-30
-- in the off hand every 2 sec, and 10% crit, against MOB and OTHER at level 37.
local function Armed(world)
    world.player.level = 40
    world:SetNPCLevel("MOB", 37)
    world:SetNPCLevel("OTHER", 37)
    world:SetWeapon("main", 40, 60, 1.5)
    world:SetWeapon("off", 20, 30, 2)
    world:SetCritChance(10)
end

-- The share of a level 40 player's physical damage armor lets through.
local function Passed(armor)
    return 1 - armor / (armor + 400 + 85 * 40)
end

-- A level 37 warrior NPC's armor (data.lua), and what it lets through.
local WARRIOR_37_ARMOR = 1593
local PASSED = Passed(WARRIOR_37_ARMOR)

-- What Death Mark stores per second of white swings with Armed's weapons:
-- 80% landing, crits, through a level 37 warrior's armor.
local SWINGS_PER_SECOND = (50 / 1.5 + 25 / 2) * 0.8 * 1.1 * PASSED

-- What Death Mark stores of a strike's average damage at 5 points: crits at
-- Armed's 10%, through a level 37 warrior's armor, 60% of it.
local STRIKE_STORED = 1.1 * PASSED * 0.6

-- Casts a 5 points Death Mark (60% stored) on the target.
local function Mark(world)
    world:SetComboPoints(5)
    world:Cast(DEATH_MARK_RANK_4)
end

test("Death Mark stores the strikes landing while it lasts, crits and armor counted", function(world)
    Rogue(world)
    Armed(world)
    world:Cast(SINISTER_STRIKE)
    Mark(world)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "not a strike before it")
    world:Cast(SINISTER_STRIKE)
    Near(Shown(world, world:TargetHealthBar()), (50 + 3) * STRIKE_STORED, "a strike after it")
    world:RunFrames(6.1)
    world:Cast(SINISTER_STRIKE)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "nor after it dealt the damage")
end)

test("a strike's weapon damage: dagger percentage, normalized speed, off hand", function(world)
    Rogue(world)
    Armed(world)
    Mark(world)
    world:Cast(GHOSTLY_STRIKE)
    Near(Shown(world, world:TargetHealthBar()), 50 * 1.8 * STRIKE_STORED, "180% with a dagger")
    world:Cast(SHANK)
    Near(Shown(world, world:TargetHealthBar()), (50 * 1.8 + 25 * 0.5) * STRIKE_STORED, "and Shank's off hand")

    world:Target("OTHER")
    world:SetHealth("OTHER", 1000, 1000)
    world:SetAttackPower(140)
    world:SetWeapon("main", 40, 60, 2, Enum.ItemWeaponSubclass.Sword1H)
    Mark(world)
    world:Cast(GHOSTLY_STRIKE)
    -- Attack power added at 2.4 sec rather than the sword's 2: 140 * 0.4 / 14 = 4 more.
    Near(Shown(world, world:TargetHealthBar()), (50 + 4) * 1.25 * STRIKE_STORED, "125% of a sword's, normalized")
end)

test("Eviscerate's damage comes from its description, raised by talents", function(world)
    Rogue(world)
    Armed(world)
    world:LearnTalent(AGGRESSION, 3)
    Mark(world)
    world:SetComboPoints(3)
    world:Cast(EVISCERATE)
    Near(Shown(world, world:TargetHealthBar()), 18 * 1.15 * STRIKE_STORED, "the 3 points line's average")
    world:Cast(SINISTER_STRIKE)
    Near(Shown(world, world:TargetHealthBar()), (18 + 53) * 1.15 * STRIKE_STORED, "Aggression on Sinister Strike too")
end)

test("a missed strike stores nothing", function(world)
    Rogue(world)
    Armed(world)
    Mark(world)
    world:Cast(SINISTER_STRIKE, "DODGE")
    world:Elapse(1.1)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "its combo point never came")
end)

test("Death Mark stores white swings while the player attacks its target", function(world)
    Rogue(world)
    Armed(world)
    world:Fire("PLAYER_ENTER_COMBAT")
    Mark(world)
    Near(Shown(world, world:TargetHealthBar()), SWINGS_PER_SECOND * 6 * 0.6, "until it ends")
    world:RunFrames(2)
    world:Fire("PLAYER_LEAVE_COMBAT")
    Near(Shown(world, world:TargetHealthBar()), SWINGS_PER_SECOND * 2 * 0.6, "until the attack stopped")
    world:RunFrames(1)
    world:Fire("PLAYER_ENTER_COMBAT")
    Near(Shown(world, world:TargetHealthBar()), SWINGS_PER_SECOND * 5 * 0.6, "and again once it started again")
end)

test("white swings at another target aren't stored", function(world)
    local plate = Rogue(world)
    Armed(world)
    Mark(world)
    world:Fire("PLAYER_ENTER_COMBAT")
    world:RunFrames(1)
    world:ShowNamePlate("OTHER")
    world:SetHealth("OTHER", 1000, 1000)
    world:Target("OTHER")
    world:RunFrames(4)
    world:Target("MOB")
    Near(Shown(world, world:NamePlateHealthBar(plate)), SWINGS_PER_SECOND * 2 * 0.6, "the first and last second")
end)

test("Death Mark stores strikes and swings up to its cap", function(world)
    Rogue(world)
    world:SetWeapon("main", 4000, 6000, 1.5)
    world:Fire("PLAYER_ENTER_COMBAT")
    world:SetComboPoints(1)
    world:Cast(DEATH_MARK_RANK_4)
    -- 5000 / 1.5 * 0.8 * 6 sec * 12% = 1920, before armor.
    equal(Shown(world, world:TargetHealthBar()), 401, "the 1 point cap")
    local overlay = world:HealthBarOverlay(world:TargetHealthBar())
    expect(overlay.inner, "what it will deal")
    equal(overlay.value, 0, "no ticks")
    equal(overlay.art, nil, "nothing animated without ticks")
    equal(overlay.flare, nil, "no flare")
end)

-- A creature GUID of the NPC `npcID`.
local function CreatureGUID(npcID)
    return ("Creature-0-1-0-1-%d-0000000001"):format(npcID)
end

-- Targets `guid` (1000 health, its nameplate shown).
local function TargetNew(world, guid)
    world:ShowNamePlate(guid)
    world:SetHealth(guid, 1000, 1000)
    world:Target(guid)
end

test("strikes and swings lose what the target's armor stops: by its NPC class and level", function(world)
    Rogue(world)
    Armed(world)
    world:SetNPCClass("MOB", "MAGE")
    Mark(world)
    world:Cast(SINISTER_STRIKE)
    -- A level 37 mage NPC: 858 armor.
    Near(Shown(world, world:TargetHealthBar()), (50 + 3) * 1.1 * Passed(858) * 0.6, "a level 37 mage's")

    world:SetNPCLevel("OTHER", 30)
    TargetNew(world, "OTHER")
    Mark(world)
    world:Fire("PLAYER_ENTER_COMBAT")
    local swings = (50 / 1.5 + 25 / 2) * 0.8 * 1.1 * Passed(1200)
    Near(Shown(world, world:TargetHealthBar()), swings * 6 * 0.6, "a level 30 warrior's: 1200")
end)

test("a player counts as a warrior NPC of their level, whatever their class", function(world)
    Rogue(world)
    Armed(world)
    local mage = "Player-1-00000001"
    world:SetNPCClass(mage, "MAGE")
    world:SetNPCLevel(mage, 37)
    TargetNew(world, mage)
    Mark(world)
    world:Cast(SINISTER_STRIKE)
    Near(Shown(world, world:TargetHealthBar()), (50 + 3) * STRIKE_STORED, "a level 37 warrior's armor")
end)

test("a creature's own armor multiplier", function(world)
    Rogue(world)
    Armed(world)
    local elemental = CreatureGUID(92) -- Rock Elemental: 1.5 times its class and level's
    world:SetNPCLevel(elemental, 37)
    TargetNew(world, elemental)
    Mark(world)
    world:Cast(SINISTER_STRIKE)
    Near(
        Shown(world, world:TargetHealthBar()),
        (50 + 3) * 1.1 * Passed(WARRIOR_37_ARMOR * 1.5) * 0.6,
        "half again a warrior's"
    )
end)

test("a hidden level counts as 10 above the player's, a boss's as 63, armor stopping 75% at most", function(world)
    Rogue(world)
    Armed(world)
    world:SetNPCLevel("MOB", -1)
    Mark(world)
    world:Cast(SINISTER_STRIKE)
    -- A level 50 warrior NPC: 2999 armor.
    Near(Shown(world, world:TargetHealthBar()), (50 + 3) * 1.1 * Passed(2999) * 0.6, "10 above")

    world.player.level = 12
    world:SetNPCLevel("OTHER", -1)
    world:SetNPCClassification("OTHER", "worldboss")
    TargetNew(world, "OTHER")
    Mark(world)
    world:Cast(SINISTER_STRIKE)
    -- A level 63 warrior NPC: 4691 armor, 77% against a level 12 player.
    Near(Shown(world, world:TargetHealthBar()), (50 + 3) * 1.1 * 0.25 * 0.6, "a boss's, capped")
end)

test("stays on the nameplate of a unit no longer targeted", function(world)
    local plate = Rogue(world)
    world:Cast(GARROTE)
    world:ShowNamePlate("OTHER")
    world:Target("OTHER")
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "not on the new target")
    equal(Shown(world, world:NamePlateHealthBar(plate)), GARROTE_DAMAGE, "still on the first unit's plate")
    world:Target("MOB")
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "back on the target frame")
end)

test("leaves recycled plates and unit frames", function(world)
    local plate = Rogue(world)
    local healthBar = world:NamePlateHealthBar(plate)
    world:Cast(GARROTE)
    world:HideNamePlate("MOB")
    local recycled = world:ShowNamePlate("OTHER")
    equal(recycled, plate, "the same plate")
    equal(world:NamePlateHealthBar(recycled), healthBar, "and unit frame")
    equal(world:HealthBarOverlay(healthBar), nil, "nothing on the other unit")
    local newPlate = world:ShowNamePlate("MOB")
    equal(Shown(world, world:NamePlateHealthBar(newPlate)), GARROTE_DAMAGE, "back with the unit's new plate")
end)

test("undone when disabled", function(world)
    local plate = Rogue(world)
    world:Cast(GARROTE)
    world:Setting("combat.dots.enabled"):SetValue(false)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "target frame")
    equal(world:HealthBarOverlay(world:NamePlateHealthBar(plate)), nil, "nameplate")
    world:Cast(GARROTE)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "casts aren't followed")
    world:Setting("combat.dots.enabled"):SetValue(true)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "nothing left over once enabled again")
end)

local SERRATED_BLADES = 14171 -- Rupture +10% per rank, its base damage only
local OPPORTUNITY = 14057 -- Garrote +4% per rank, attack power part included

test("Opportunity raises Garrote's attack power part, Serrated Blades only Rupture's base", function(world)
    Rogue(world)
    world:SetAttackPower(241)
    world:LearnTalent(SERRATED_BLADES, 3)
    world:LearnTalent(OPPORTUNITY, 5)
    world:Cast(GARROTE)
    Near(Shown(world, world:TargetHealthBar()), (GARROTE_DAMAGE + 0.18 * 241) * 1.2, "Garrote")
    world:SetComboPoints(5)
    world:Cast(RUPTURE)
    Near(
        Shown(world, world:TargetHealthBar()),
        (GARROTE_DAMAGE + 0.18 * 241) * 1.2 + 144 * 1.3 + 0.24 * 241,
        "and Rupture"
    )
end)

-- Ticks seen in the combat log, with 241 attack power (236 for the 5 points
-- Rupture), Serrated Blades 3/3 and Opportunity 5/5.
test("matches the ticks measured in game", function(world)
    Rogue(world)
    world:LearnTalent(SERRATED_BLADES, 3)
    world:LearnTalent(OPPORTUNITY, 5)
    world:SetAttackPower(241)
    world:Cast(GARROTE)
    expect(math.abs(Shown(world, world:TargetHealthBar()) / 6 - 65) < 0.5, "Garrote ticks for 65")

    world:Target("OTHER")
    world:SetHealth("OTHER", 1000, 1000)
    world:SetComboPoints(3)
    world:Cast(RUPTURE)
    expect(math.abs(Shown(world, world:TargetHealthBar()) / 6 - 26) < 0.5, "a 3 points Rupture ticks for 26")

    world:SetAttackPower(236)
    world:Target("THIRD")
    world:SetHealth("THIRD", 1000, 1000)
    world:SetComboPoints(5)
    world:Cast(RUPTURE)
    expect(math.abs(Shown(world, world:TargetHealthBar()) / 8 - 30) < 0.5, "a 5 points Rupture ticks for 30")

    world:Cast(HEMORRHAGE)
    world:Cast(RUPTURE)
    local before = Shown(world, world:TargetHealthBar())
    world:RunFrames(2.1)
    expect(math.abs(before - Shown(world, world:TargetHealthBar()) - 35) < 0.5, "and for 35 under Hemorrhage")
end)

test("a miss that may be someone else's waits for the combo points", function(world)
    Rogue(world)
    world:SetComboPoints(5)
    world:Cast(RUPTURE, "DODGE")
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "not shown yet")
    world:RunFrames(0.2)
    world:SetComboPoints(0)
    -- Timed from the cast: its first tick still lands 2 sec after it.
    equal(Shown(world, world:TargetHealthBar()), 144, "shown once the points were spent")
    world:RunFrames(1.9)
    equal(Shown(world, world:TargetHealthBar()), 144 * 7 / 8, "ticking from the cast")
end)

test("a cast that missed keeps its combo points and is dropped", function(world)
    Rogue(world)
    world:SetComboPoints(5)
    world:Cast(RUPTURE, "DODGE")
    world:Elapse(1.1)
    world:SetComboPoints(0)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "points spent later don't bring it back")
end)

test("a builder that may have missed lands with the points it awards", function(world)
    Rogue(world)
    world:Cast(HEMORRHAGE, "PARRY")
    world:SetComboPoints(1)
    world:Cast(GARROTE)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE / 6 * (5 * 1.15 + 1), "raised by Hemorrhage")
end)

test("forgets the effects on a unit that died", function(world)
    local plate = Rogue(world)
    world:Cast(GARROTE)
    world:Kill("MOB")
    world:NextFrame()
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "target frame")
    equal(world:HealthBarOverlay(world:NamePlateHealthBar(plate)), nil, "nameplate")
end)

test("forgets a unit whose identity is secret once its nameplate goes", function(world)
    local firstPlate = Rogue(world)
    world.secretIdentities.MOB = true
    world:Cast(GARROTE)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "followed by its nameplate: on the target frame")
    equal(Shown(world, world:NamePlateHealthBar(firstPlate)), GARROTE_DAMAGE, "and its nameplate")
    world:HideNamePlate("MOB")
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "can't tell it apart without its plate")
    local plate = world:ShowNamePlate("MOB")
    equal(world:HealthBarOverlay(world:NamePlateHealthBar(plate)), nil, "not taken for another unit's")
end)

test("skips a unit whose identity is secret without a nameplate", function(world)
    world.player.class = "ROGUE"
    world.secretIdentities.MOB = true
    world:SetHealth("MOB", 1000, 1000)
    world:Target("MOB")
    world:Cast(GARROTE)
    local plate = world:ShowNamePlate("MOB")
    equal(world:HealthBarOverlay(world:NamePlateHealthBar(plate)), nil, "the cast wasn't followed")
end)

test("a unit whose identity becomes secret keeps nothing it can't be told by", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    world.secretIdentities.MOB = true
    world:NextFrame()
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "kept under its GUID, now unreadable")
end)

test("out of combat, forgets the effects whose aura is gone", function(world)
    Rogue(world)
    world:EnterCombat()
    world:Cast(GARROTE)
    world:LeaveCombat()
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "the unit reset")
end)

test("out of combat, takes the aura's timing, a longer aura adding ticks of the same damage", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    world:SetAura("MOB", GARROTE, 18, world.now + 9)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE / 2, "half of it left")
    -- Lengthened by a talent the data didn't tell.
    world:SetAura("MOB", GARROTE, 24, world.now + 24)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE / 6 * 8, "8 ticks of the same damage")
end)

test("in combat, leaves the effects alone when auras change", function(world)
    Rogue(world)
    world:EnterCombat()
    world:Cast(GARROTE)
    world:RemoveAura("MOB", GARROTE)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "still shown")
end)

-- The generated data (data.lua) and what was measured (measured.lua) must agree.
test("every followed spell has its attack power measured", function()
    local DoTs = ForeverEnhanced:GetFeature("combat", "dots")
    local keys = {}
    for _, spell in pairs(DoTs.Data.spells) do
        keys[spell.key] = spell
        local measured = DoTs.Measured.spells[spell.key]
        expect(measured, spell.key .. ": attack power measured")
        local perPoint = spell.comboPoints == "spend"
        equal(type(measured.attackPower), perPoint and "table" or "number", spell.key .. ": one per point")
        equal(type(measured.talentsRaiseBonus), "boolean", spell.key .. ": whether talents raise the bonus")
        equal(spell.ranks == nil, perPoint, spell.key .. ": ranks from the data, unless a finishing move")
    end
    for key in pairs(DoTs.Measured.spells) do
        expect(keys[key], key .. ": a followed spell")
    end
    local marks = {}
    for _, mark in pairs(DoTs.Data.marks) do
        marks[mark.key] = true
        local measured = DoTs.Measured.marks[mark.key]
        expect(measured, mark.key .. ": what it stores measured")
        for key in pairs(measured.stores) do
            expect(keys[key], ("%s stores %s: a followed spell"):format(mark.key, key))
        end
    end
    for key in pairs(DoTs.Measured.marks) do
        expect(marks[key], key .. ": a followed mark")
    end
    for talentSpellID, bySpell in pairs(DoTs.Measured.talents) do
        for key, ranks in pairs(bySpell) do
            local data = DoTs.Data.talents[talentSpellID]
            expect(data and data[key], ("%d %s: a talent the data has"):format(talentSpellID, key))
            equal(#ranks, #data[key], ("%d %s: every rank"):format(talentSpellID, key))
        end
    end
end)

local REND = 772 -- 15 over 9 sec, a tick every 3 sec
local REND_RANK_2 = 6546 -- 28 over 12 sec

-- A warrior targeting MOB (1000 health), whose nameplate is shown.
local function Warrior(world)
    world.player.class = "WARRIOR"
    local plate = world:ShowNamePlate("MOB")
    world:SetHealth("MOB", 1000, 1000)
    world:Target("MOB")
    return plate
end

test("follows a warrior's Rend, each rank's damage from the data", function(world)
    local plate = Warrior(world)
    world:Cast(REND)
    equal(Shown(world, world:TargetHealthBar()), 15, "rank 1")
    equal(Shown(world, world:NamePlateHealthBar(plate)), 15, "on the nameplate too")
    world:Cast(REND_RANK_2)
    equal(Shown(world, world:TargetHealthBar()), 28, "replaced by rank 2")
    world:RunFrames(3.1)
    Near(Shown(world, world:TargetHealthBar()), 28 * 3 / 4, "after its first tick")
    world:RunFrames(9)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "ended after 12 sec")
end)

test("draws under the health text", function(world)
    local plate = Rogue(world)
    world:Cast(GARROTE)
    expect(world:HealthBarOverlay(world:TargetHealthBar()).underText, "target frame: above the fill, under the text")
    expect(
        world:HealthBarOverlay(world:NamePlateHealthBar(plate)).underText,
        "nameplate: above the fill, under the text"
    )
end)

test("measures no nameplate in combat and keeps the attack power read before it", function(world)
    Rogue(world)
    world:SetAttackPower(241)
    world:EnterCombat()
    -- A plate shown in combat gets its overlay then: measuring it would throw.
    local plate = world:ShowNamePlate("OTHER")
    world:SetHealth("OTHER", 1000, 1000)
    world:Target("OTHER")
    world:Cast(GARROTE)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE + 0.18 * 241, "the attack power before combat")
    expect(world:HealthBarOverlay(world:NamePlateHealthBar(plate)), "shown")
end)

local SHADOW_WORD_PAIN = 589 -- 5 per tick, every 3 sec for 18 sec; 20% of shadow spell power per tick
local IMPROVED_SHADOW_WORD_PAIN = 15275 -- +3 / +6 sec
local TWIN_DISCIPLINES = 1225132 -- +1% per rank
local CORRUPTION = 172 -- 10 per tick, every 3 sec for 12 sec
local SHADOW = 6

-- A priest targeting MOB (1000 health), whose nameplate is shown.
local function Priest(world)
    world.player.class = "PRIEST"
    local plate = world:ShowNamePlate("MOB")
    world:SetHealth("MOB", 1000, 1000)
    world:Target("MOB")
    return plate
end

test("keeps the spell power read before combat, when it is secret", function(world)
    Priest(world)
    world:SetSpellPower(SHADOW, 100)
    world:EnterCombat()
    world:Cast(SHADOW_WORD_PAIN)
    Near(Shown(world, world:TargetHealthBar()), (5 + 0.2 * 100) * 6, "the spell power before combat")
end)

test("talents raise the spell power part and lengthening ones add ticks", function(world)
    Priest(world)
    world:SetSpellPower(SHADOW, 100)
    world:LearnTalent(TWIN_DISCIPLINES, 5)
    world:LearnTalent(IMPROVED_SHADOW_WORD_PAIN, 2)
    world:Cast(SHADOW_WORD_PAIN)
    Near(Shown(world, world:TargetHealthBar()), (5 + 0.2 * 100) * 1.05 * 8, "8 ticks over 24 sec")
    world:RunFrames(23.9)
    expect(world:HealthBarOverlay(world:TargetHealthBar()), "still there before the last tick")
    world:RunFrames(0.2)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "then ends")
end)

test("a spell with a cast time lands on the unit it was cast on", function(world)
    local plate = Priest(world)
    world:ShowNamePlate("OTHER")
    world:SetHealth("OTHER", 1000, 1000)
    local cast = world:BeginCast(CORRUPTION)
    world:Target("OTHER")
    world:EndCast(cast)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "not on the new target")
    equal(Shown(world, world:NamePlateHealthBar(plate)), 40, "on the unit it was cast on")
end)

test("only passive talents count, not cooldowns", function()
    local DoTs = ForeverEnhanced:GetFeature("combat", "dots")
    equal(DoTs.Data.talents[12042], nil, "Arcane Power")
end)

test("a miss on the nameplate of the unit cast on drops the cast", function(world)
    local plate = Priest(world)
    world:ShowNamePlate("OTHER")
    world:SetHealth("OTHER", 1000, 1000)
    local cast = world:BeginCast(CORRUPTION)
    world:Target("OTHER")
    world:EndCast(cast, "RESIST", plate:GetUnit())
    equal(world:HealthBarOverlay(world:NamePlateHealthBar(plate)), nil, "resisted")
end)

-- Sharing with the group. A member's messages are the player's own, as their
-- client would send them.

local SHARE_PREFIX = "FEDots"
local ALICE, BOB = "Player-1-Alice", "Player-1-Bob"

-- The player's share messages sent since the last call.
local function SentShares(world)
    local messages = {}
    for _, record in ipairs(world.sentAddon) do
        if record.prefix == SHARE_PREFIX then
            table.insert(messages, record.message)
        end
    end
    world.sentAddon = {}
    return messages
end

-- A member's message, from `message` the player sent, on MOB or `unitGUID`.
local function As(world, memberGUID, message, unitGUID)
    message = message:gsub(world.player.guid:gsub("%p", "%%%0"), memberGUID)
    return (message:gsub(":MOB:", ":" .. (unitGUID or "MOB") .. ":"))
end

local function Receive(world, message, chatType)
    world:ReceiveGroupAddon(SHARE_PREFIX, message, chatType or "PARTY", "Alice-Forever")
end

-- The player in a party with Alice, as Rogue.
local function PartyRogue(world)
    local plate = Rogue(world)
    world:GuestJoins("Alice")
    world:NextFrame()
    SentShares(world)
    return plate
end

-- The snapshot the player sends once casting `spellID`, then gone from the
-- player: only what a member sends is shown.
local function SnapshotOf(world, spellID)
    world:Cast(spellID)
    world:NextFrame()
    local messages = SentShares(world)
    equal(#messages, 1, "one message")
    world:Setting("combat.dots.enabled"):SetValue(false)
    world:Setting("combat.dots.enabled"):SetValue(true)
    world:NextFrame()
    SentShares(world)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "nothing of the player's left")
    return messages[1]
end

test("sends nothing outside a group", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    world:NextFrame()
    equal(#SentShares(world), 0, "no message")
end)

test("a group member's effects show like the player's own", function(world)
    local plate = PartyRogue(world)
    local garrote = SnapshotOf(world, GARROTE)
    Receive(world, As(world, ALICE, garrote))
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "on the target frame")
    equal(Shown(world, world:NamePlateHealthBar(plate)), GARROTE_DAMAGE, "and the nameplate")
    world:RunFrames(3.1)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE * 5 / 6, "each tick taken off as it lands")
    world:RunFrames(15)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "hidden once the last tick landed")
end)

test("everyone's effects add up", function(world)
    PartyRogue(world)
    world:GuestJoins("Bob")
    local garrote = SnapshotOf(world, GARROTE)
    world:Cast(GARROTE)
    Receive(world, As(world, ALICE, garrote))
    Receive(world, As(world, BOB, garrote), "RAID")
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE * 3, "the same spell of three players")
    Receive(world, As(world, ALICE, garrote))
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE * 3, "a member's new snapshot replaces theirs")
    Receive(world, garrote)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE * 3, "the player's own message isn't counted twice")
end)

test("a member sees what the caster sees: combo points, Hemorrhage, Death Mark, time passed", function(world)
    PartyRogue(world)
    Armed(world)
    world:SetHealth("MOB", 5000, 5000)
    world:Cast(HEMORRHAGE)
    world:Cast(GARROTE)
    world:SetComboPoints(5)
    world:Cast(RUPTURE)
    world:RunFrames(2.5)
    Mark(world)
    world:Cast(SINISTER_STRIKE)
    world:NextFrame()
    local overlay = world:HealthBarOverlay(world:TargetHealthBar())
    local ticks, stored = overlay.value, overlay.inner.value
    local messages = SentShares(world)
    world:Setting("combat.dots.enabled"):SetValue(false)
    world:Setting("combat.dots.enabled"):SetValue(true)
    Receive(world, As(world, ALICE, messages[#messages]))
    overlay = world:HealthBarOverlay(world:TargetHealthBar())
    expect(math.abs(overlay.value - ticks) < 0.5, ("ticks: %s, got %s"):format(ticks, overlay.value))
    expect(math.abs(overlay.inner.value - stored) < 0.5, ("mark: %s, got %s"):format(stored, overlay.inner.value))
    world:RunFrames(6.1)
    equal(world:HealthBarOverlay(world:TargetHealthBar()).inner, nil, "the mark gone once dealt")
end)

test("sends one snapshot a cast, and none for what changes nothing", function(world)
    PartyRogue(world)
    Armed(world)
    world:Cast(SINISTER_STRIKE)
    world:Cast(HEMORRHAGE)
    world:SetComboPoints(5)
    world:Cast(EVISCERATE)
    world:NextFrame()
    equal(#SentShares(world), 0, "strikes without a mark, an amplifier without an effect")
    world:Cast(GARROTE)
    world:NextFrame()
    equal(#SentShares(world), 1, "an effect")
    world:Cast(HEMORRHAGE)
    world:NextFrame()
    equal(#SentShares(world), 1, "an amplifier of it")
    Mark(world)
    world:NextFrame()
    equal(#SentShares(world), 1, "a mark")
    world:Cast(SINISTER_STRIKE)
    world:NextFrame()
    equal(#SentShares(world), 1, "a strike it stores")
    world:SetComboPoints(5)
    world:Cast(RUPTURE, "DODGE")
    world:NextFrame()
    equal(#SentShares(world), 0, "not a miss")
end)

test("what waits for the client's pace goes out as of then, once per unit", function(world)
    PartyRogue(world)
    for _ = 1, 20 do
        world:Cast(GARROTE)
        world:NextFrame()
    end
    local messages = SentShares(world)
    expect(#messages <= 8, "a burst at most")
    world:Elapse(3)
    messages = SentShares(world)
    equal(#messages, 1, "then the latest only")
    local elapsed = tonumber(messages[1]:match(":[%d.]+,[%d.]+,[%d.]+,([%d.]+):$"))
    expect(elapsed and elapsed > 0, "timed from the cast")
end)

test("out of combat, the group hears of effects whose aura is gone", function(world)
    PartyRogue(world)
    local garrote = SnapshotOf(world, GARROTE)
    Receive(world, As(world, ALICE, garrote))
    world:EnterCombat()
    world:Cast(GARROTE)
    world:NextFrame()
    SentShares(world)
    world:LeaveCombat()
    world:NextFrame()
    local messages = SentShares(world)
    equal(#messages, 1, "a snapshot")
    Receive(world, As(world, ALICE, messages[1]))
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "an empty one, removing the member's")
end)

test("in combat, sends and shows as out of it", function(world)
    PartyRogue(world)
    world:EnterCombat()
    world:Cast(GARROTE)
    world:NextFrame()
    local messages = SentShares(world)
    equal(#messages, 1, "sent")
    Receive(world, As(world, ALICE, messages[1]))
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE * 2, "added")
end)

test("joining a group asks for its effects and sends the player's, and an ask is answered", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    world:GuestJoins("Alice")
    world:NextFrame()
    local messages = SentShares(world)
    equal(#messages, 2, "both")
    local ask = messages[1]
    Receive(world, As(world, ALICE, ask))
    world:NextFrame()
    local answer = SentShares(world)
    equal(#answer, 1, "answered")
    expect(answer[1]:find(":MOB:", 1, true), "with the snapshot")
    Receive(world, ask)
    world:NextFrame()
    equal(#SentShares(world), 0, "not the player's own ask")
end)

test("forgets the effects of a member who leaves, and of a unit that died", function(world)
    PartyRogue(world)
    world:GuestJoins("Bob")
    local garrote = SnapshotOf(world, GARROTE)
    Receive(world, As(world, ALICE, garrote))
    Receive(world, As(world, BOB, garrote))
    world:GuestLeaves("Bob")
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "Alice's only")
    world:Kill("MOB")
    world:NextFrame()
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "dead")
    equal(ForeverEnhanced:GetFeature("combat", "dots").Sharing:IsTracking(), false, "nothing kept")
    Receive(world, As(world, ALICE, garrote, "OTHER"))
    world:LeaveGroup()
    equal(ForeverEnhanced:GetFeature("combat", "dots").Sharing:IsTracking(), false, "nor once the group is left")
end)

test("ignores strangers, other channels, secret and malformed messages", function(world)
    PartyRogue(world)
    local snapshot = SnapshotOf(world, GARROTE)
    local garrote = As(world, ALICE, snapshot)
    Receive(world, As(world, "Player-1-Mallory", snapshot))
    Receive(world, garrote, "WHISPER")
    Receive(world, world:Secret(garrote))
    Receive(world, (garrote:gsub("^1", "2")))
    Receive(world, ("1U:%s:MOB:nan,3.00,18.00,0.00:"):format(ALICE))
    Receive(world, ("1U:%s:MOB:5.00,0.00,18.00,0.00:"):format(ALICE))
    Receive(world, ("1U:%s:MOB:5.00,0.01,9999.00,0.00:"):format(ALICE))
    Receive(world, ("1U:%s:MOB:5.00,3.00,18.00:"):format(ALICE))
    Receive(world, ("1U:%s:MOB::5.00"):format(ALICE))
    Receive(world, "1U")
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "none shown")
    Receive(world, garrote)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "a proper one is")
end)

test("shares no unit told apart by its nameplate, and drops what a lockdown refuses", function(world)
    PartyRogue(world)
    world.secretIdentities.MOB = true
    world:Cast(GARROTE)
    world:NextFrame()
    equal(#SentShares(world), 0, "a nameplate means nothing to others")
    world.secretIdentities.MOB = nil
    world.addonLockdown = true
    world:Cast(GARROTE)
    world:Elapse(2)
    world.addonLockdown = false
    world:Elapse(2)
    equal(#SentShares(world), 0, "not sent later")
    expect(Shown(world, world:TargetHealthBar()) > 0, "the player's own still shown")
end)

test("sharing turned off sends and shows nothing of others", function(world)
    PartyRogue(world)
    local garrote = SnapshotOf(world, GARROTE)
    Receive(world, As(world, ALICE, garrote))
    world:Setting("combat.dots.share"):SetValue(false)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "gone at once")
    Receive(world, As(world, ALICE, garrote))
    world:Cast(GARROTE)
    world:NextFrame()
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "the player's own only")
    equal(#SentShares(world), 0, "not sent")
    world:Setting("combat.dots.share"):SetValue(true)
    world:NextFrame()
    equal(#SentShares(world), 2, "asks, and sends what is running once on again")
end)
