-- Quest helpers, sparkles: the sparkle CVar is set on login, set again after
-- graphics presets and entering the world, waits for combat to end, and goes
-- back to the player's value when disabled.

local CVAR = "outlineModeShowLootEffectWhenDisabled"

local function Sparkle()
    return C_CVar.GetCVar(CVAR)
end

local function SetEnabled(world, enabled)
    world:Setting("quests.helpers.sparkles"):SetValue(enabled)
end

-- Like a graphics preset: it rewrites the sparkle CVar, then the quality.
local function PickPreset()
    C_CVar.SetCVar(CVAR, "0")
    C_CVar.SetCVar("graphicsQuality", "3")
end

test("turns the sparkle on at login", function(world)
    equal(Sparkle(), "1", "sparkle")
end)

test("turns the sparkle back on after a graphics preset", function(world)
    PickPreset()
    world:Elapse(0.5)
    equal(Sparkle(), "0", "not yet")
    world:Elapse(0.5)
    equal(Sparkle(), "1", "back on")
end)

test("waits for the end of combat", function(world)
    world.inCombat = true
    PickPreset()
    world:Elapse(2)
    equal(Sparkle(), "0", "off in combat")
    equal(#world.combatCVarWrites, 2, "only the preset's writes")

    world.inCombat = false
    world:Fire("PLAYER_REGEN_ENABLED")
    equal(Sparkle(), "1", "on after combat")
end)

test("turns it back on when synced settings arrive after entering the world", function(world)
    world:Fire("PLAYER_ENTERING_WORLD")
    world.cvars[CVAR:lower()] = "0"
    world:Elapse(5)
    equal(Sparkle(), "1", "sparkle")
end)

test("disabling puts the player's value back and asks for a restart", function(world)
    SetEnabled(world, false)
    equal(Sparkle(), "0", "player's value")
    equal(#world.prints, 1, "messages")
    expect(world.prints[1]:find(world.L["quests.helpers.sparkles.restart"], 1, true), "restart message")

    PickPreset()
    world:Elapse(2)
    equal(Sparkle(), "0", "left alone while disabled")
end)

test("a player who had the sparkle on keeps it", function(world)
    SetEnabled(world, false)
    world.prints = {}
    C_CVar.SetCVar(CVAR, "1")
    SetEnabled(world, true)
    SetEnabled(world, false)
    equal(Sparkle(), "1", "sparkle")
    equal(#world.prints, 0, "no restart message")
end)

test("turning the quest helpers off puts the player's value back", function(world)
    world:Setting("quests.helpers.enabled"):SetValue(false)
    equal(Sparkle(), "0", "player's value")
    world:Setting("quests.helpers.enabled"):SetValue(true)
    equal(Sparkle(), "1", "back on")
end)
