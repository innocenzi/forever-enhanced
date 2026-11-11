-- Spell Rank Upgrades: learning a new rank puts it in place of every older
-- rank of that spell on the bars, out of combat only, and only while enabled.

local BACKSTAB, BACKSTAB_RANK_2, SINISTER_STRIKE = 53, 2589, 1752

-- Backstab on the main bar and the bottom left bar, Sinister Strike beside it.
local function Bars(world)
    world:PlaceSpell(1, BACKSTAB)
    world:PlaceSpell(2, SINISTER_STRIKE)
    world:PlaceSpell(61, BACKSTAB)
    world:NextFrame()
end

test("replaces every older rank on the bars when a new one is learned", function(world)
    Bars(world)
    world:LearnSpell(BACKSTAB_RANK_2)
    equal(world.actions[1], BACKSTAB_RANK_2)
    equal(world.actions[61], BACKSTAB_RANK_2)
    equal(world.actions[2], SINISTER_STRIKE)
    equal(world.cursorAction, nil)
end)

test("waits for combat to end", function(world)
    Bars(world)
    world:EnterCombat()
    world:LearnSpell(BACKSTAB_RANK_2)
    equal(world.actions[1], BACKSTAB)
    world:LeaveCombat()
    equal(world.actions[1], BACKSTAB_RANK_2)
    equal(world.actions[61], BACKSTAB_RANK_2)
end)

test("leaves the bars alone while disabled", function(world)
    Bars(world)
    world:Setting("interface.ranks.enabled"):SetValue(false)
    world:NextFrame()
    world:LearnSpell(BACKSTAB_RANK_2)
    equal(world.actions[1], BACKSTAB)
end)
