-- Damage Over Time to Come: the player's damage over time effects (Garrote
-- and Rupture, Rend, Shadow Word: Pain, Corruption...) show, over the health
-- bar's fill on the target frame and on nameplates, the damage their ticks
-- have yet to deal: each rank's from the data, a finishing move's from its
-- description, raised by attack and spell power read before combat, by
-- talents, and by Hemorrhage on the ticks landing while it lasts. Casts that
-- miss show nothing (or wait for their combo points), casting again replaces
-- the effect, a spell with a cast time lands on the unit it was cast on, dead
-- units and recycled plates are left, out of combat auras correct the
-- effects, and everything is undone when disabled.

local GARROTE = 8632 -- a tick every 3 sec
local GARROTE_DAMAGE = 282 -- over 18 sec, before talents and attack power
local RUPTURE = 8639 -- 44 / 63 / 87 / 114 / 144 over 8 to 16 sec, a tick every 2 sec
local RUPTURE_HIGH_RANK = 11275 -- 1032 over 16 sec with 5 points
local HEMORRHAGE = 16511 -- +15% for 15 sec

-- The damage the overlay over the health bar shows, or 0 without one.
local function Shown(world, healthBar)
    local overlay = world:HealthBarOverlay(healthBar)
    return overlay and overlay.value or 0
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

test("follows the health left", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    world:SetHealth("MOB", 200)
    world:NextFrame()
    local overlay = world:HealthBarOverlay(world:TargetHealthBar())
    equal(overlay.range, 200, "out of the new health")
    equal(overlay.value, 200, "covers it all when the damage would kill")
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

test("adds up the effects on the unit", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    world:SetComboPoints(1)
    world:Cast(RUPTURE)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE + 44, "Garrote and Rupture")
end)

test("a cast that misses shows nothing", function(world)
    Rogue(world)
    for _, miss in ipairs({ "MISS", "DODGE", "PARRY", "IMMUNE" }) do
        world:SetComboPoints(2)
        world:Cast(RUPTURE, miss)
        equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, miss)
    end
end)

test("a cast that misses leaves the effects already running", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    world:SetComboPoints(2)
    world:Cast(RUPTURE, "DODGE")
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "the Garrote")
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

test("a missed Hemorrhage raises nothing", function(world)
    Rogue(world)
    world:Cast(HEMORRHAGE, "PARRY")
    world:Cast(GARROTE)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "not raised")
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

test("adds a share of attack power", function(world)
    Rogue(world)
    world:SetAttackPower(241)
    world:Cast(GARROTE)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE + 0.18 * 241, "Garrote")
    world:SetComboPoints(3)
    world:Cast(RUPTURE)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE + 0.18 * 241 + 87 + 0.18 * 241, "and a 3 points Rupture")
end)

test("talents raise the damage", function(world)
    Rogue(world)
    world:LearnTalent(SERRATED_BLADES, 3)
    world:LearnTalent(OPPORTUNITY, 5)
    world:Cast(GARROTE)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE * 1.2, "Garrote with Opportunity")
    world:SetComboPoints(5)
    world:Cast(RUPTURE)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE * 1.2 + 144 * 1.3, "and Rupture with Serrated Blades")
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

test("keeps the attack power read before combat, when it is secret", function(world)
    Rogue(world)
    world:SetAttackPower(241)
    world:EnterCombat()
    world:Cast(GARROTE)
    Near(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE + 0.18 * 241, "the attack power before combat")
end)

test("follows attack power and talents changing out of combat", function(world)
    Rogue(world)
    world:SetAttackPower(100)
    world:LearnTalent(OPPORTUNITY, 5)
    world:Cast(GARROTE)
    Near(Shown(world, world:TargetHealthBar()), (GARROTE_DAMAGE + 0.18 * 100) * 1.2, "as they are")
    world:SetAttackPower(200)
    world:LearnTalent(OPPORTUNITY, 2)
    world:Cast(GARROTE)
    Near(Shown(world, world:TargetHealthBar()), (GARROTE_DAMAGE + 0.18 * 200) * 1.08, "as they became")
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

test("follows a unit whose identity is secret by its nameplate", function(world)
    local plate = Rogue(world)
    world.secretIdentities.MOB = true
    world:Cast(GARROTE)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE, "on the target frame")
    equal(Shown(world, world:NamePlateHealthBar(plate)), GARROTE_DAMAGE, "and its nameplate")
end)

test("forgets a unit whose identity is secret once its nameplate goes", function(world)
    Rogue(world)
    world.secretIdentities.MOB = true
    world:Cast(GARROTE)
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

test("out of combat, takes the aura's timing", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    world:SetAura("MOB", GARROTE, 18, world.now + 9)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE / 2, "half of it left")
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
local IMPROVED_REND = 12286 -- 12 / 23 / 35%

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

test("Improved Rend raises Rend", function(world)
    Warrior(world)
    world:LearnTalent(IMPROVED_REND, 3)
    world:Cast(REND_RANK_2)
    Near(Shown(world, world:TargetHealthBar()), 28 * 1.35, "35% at rank 3")
end)

test("a Rend whose cast logged a miss is dropped: nothing confirms it", function(world)
    Warrior(world)
    world:Cast(REND, "DODGE")
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "not shown")
    world:Elapse(1.1)
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "nor later")
end)

local PIP = "UI-HUD-ExperienceBar-Frame-Pip"

test("draws under the health text: a pip at its end on nameplates, a line on the target frame", function(world)
    local plate = Rogue(world)
    world:Cast(GARROTE)
    local target = world:HealthBarOverlay(world:TargetHealthBar(), PIP)
    expect(target.underText, "target frame: above the fill, under the text")
    equal(target.marker, nil, "target frame: no pip")
    equal(target.line, 1, "a thin line")
    local nameplate = world:HealthBarOverlay(world:NamePlateHealthBar(plate), PIP)
    expect(nameplate.underText, "nameplate: above the fill, under the text")
    equal(nameplate.marker.width, 10, "nameplate: the experience bar's pip")
    equal(nameplate.marker.height, 14, "at its size")
    equal(nameplate.line, nil, "no line")
end)

test("measures no nameplate in combat", function(world)
    Rogue(world)
    world:EnterCombat()
    -- A plate shown in combat gets its overlay then: measuring it would throw.
    local plate = world:ShowNamePlate("OTHER")
    world:SetHealth("OTHER", 1000, 1000)
    world:Target("OTHER")
    world:Cast(GARROTE)
    expect(world:HealthBarOverlay(world:NamePlateHealthBar(plate), PIP), "shown")
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

test("adds a share of spell power to each tick", function(world)
    Priest(world)
    world:SetSpellPower(SHADOW, 100)
    world:Cast(SHADOW_WORD_PAIN)
    Near(Shown(world, world:TargetHealthBar()), (5 + 0.2 * 100) * 6, "6 ticks")
end)

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

test("a resisted spell is dropped", function(world)
    Priest(world)
    world:Cast(SHADOW_WORD_PAIN, "RESIST")
    equal(world:HealthBarOverlay(world:TargetHealthBar()), nil, "not shown")
end)

test("only passive talents count, not cooldowns", function()
    local DoTs = ForeverEnhanced:GetFeature("combat", "dots")
    equal(DoTs.Data.talents[12042], nil, "Arcane Power")
end)

test("out of combat, a longer aura adds ticks of the same damage", function(world)
    Rogue(world)
    world:Cast(GARROTE)
    -- Lengthened by a talent the data didn't tell.
    world:SetAura("MOB", GARROTE, 24, world.now + 24)
    equal(Shown(world, world:TargetHealthBar()), GARROTE_DAMAGE / 6 * 8, "8 ticks of the same damage")
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
