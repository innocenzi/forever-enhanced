-- Glow on Nearest Object: the soft targeting CVars and their restore, the
-- nameplate on glowing objects only, categories, reach and usable states,
-- following the soft target, and combat. The game picks the soft target again
-- on the next frame after a CVar change, and shows its nameplate the frame
-- after our nameplate CVar opens (see Soft interact in tests/wow.lua).

local TICK_SECONDS = 0.15

local function Set(world, key, value)
    world:Setting("interface.glow." .. key):SetValue(value)
end

local function CVar(name)
    return C_CVar.GetCVar(name)
end

-- Lets the game pick the soft target and show its nameplate.
local function Settle(world)
    world:NextFrame()
    world:NextFrame()
end

local function Enable(world)
    Set(world, "enabled", true)
    Settle(world)
end

local function Approach(world, object)
    world:SoftInteract(object)
    Settle(world)
end

-- The nameplate the glow shows on, its category and state; nil when hidden.
local function Glow(world)
    return world.ns:GetFeature("interface", "glow").Effect:GetShown()
end

local function SoftPlate()
    return C_NamePlate.GetNamePlateForUnit("softinteract")
end

local function Herb(fields)
    local object = { cursor = "GatherHerbs", inRange = true }
    for key, value in pairs(fields or {}) do
        object[key] = value
    end
    return object
end

test("is off by default and leaves targeting alone", function(world)
    Approach(world, Herb())
    equal(CVar("SoftTargetInteract"), "1", "interact key")
    equal(SoftPlate(), nil, "nameplate")
    equal(Glow(world), nil, "glow")
end)

test("turns on soft targeting all around the player", function(world)
    Enable(world)
    equal(CVar("SoftTargetInteract"), "3", "interact key")
    equal(CVar("SoftTargetIconGameObject"), "1", "object nameplates")
    equal(CVar("SoftTargetInteractArc"), "2", "arc")
    equal(CVar("SoftTargetInteractOnlyInRange"), "0", "out of reach")
    equal(CVar("SoftTargetInteractRange"), "15", "range")
    equal(CVar("SoftTargetIconInteract"), "0", "no interact icon without a glowing object")

    Set(world, "range", 8)
    equal(CVar("SoftTargetInteractRange"), "8", "range setting")
end)

test("makes the nearest herb glow on its nameplate", function(world)
    Enable(world)
    Approach(world, Herb())
    equal(CVar("SoftTargetNameplateInteract"), "1", "nameplate shown")
    equal(CVar("SoftTargetIconInteract"), "1", "interaction icon")
    local plate, category, state = Glow(world)
    expect(plate and plate == SoftPlate(), "glow on the soft target's nameplate")
    equal(category, "herbs", "category")
    equal(state, "ready", "state")
end)

test("dims out of reach and turns grey when it can't be used, once steady", function(world)
    Enable(world)
    local herb = Herb({ inRange = false })
    Approach(world, herb)
    equal(select(3, Glow(world)), "far", "out of reach")

    herb.inRange = true
    world:Elapse(TICK_SECONDS)
    equal(select(3, Glow(world)), "far", "not steady yet")
    world:Elapse(TICK_SECONDS)
    equal(select(3, Glow(world)), "ready", "in reach")

    herb.unable = true
    world:Elapse(TICK_SECONDS * 2)
    equal(select(3, Glow(world)), "locked", "can't be used")
end)

test("glows only on the categories turned on", function(world)
    Enable(world)
    Approach(world, { cursor = "Mine", inRange = true })
    equal(select(2, Glow(world)), "ore", "ore vein")

    Set(world, "ore", false)
    Settle(world)
    equal(Glow(world), nil, "ore turned off")
    equal(CVar("SoftTargetNameplateInteract"), "0", "nameplate hidden")
    equal(SoftPlate(), nil, "no nameplate")

    Approach(world, { cursor = "LootAll", inRange = true })
    equal(Glow(world), nil, "other objects off by default")
    Set(world, "other", true)
    Settle(world)
    equal(select(2, Glow(world)), "other", "other objects")

    Set(world, "other", false)
    Approach(world, { cursor = "LootAll", inRange = true, quest = true })
    equal(select(2, Glow(world)), "quest", "object of an active quest")
    Approach(world, { cursor = "Quest", inRange = true })
    equal(select(2, Glow(world)), "quest", "quest cursor")
end)

test("reads cursors given as atlases", function(world)
    world.cursorAtlases = true
    Enable(world)
    Approach(world, { cursor = "Mine", inRange = true, unable = true })
    local _, category, state = Glow(world)
    equal(category, "ore", "category")
    equal(state, "locked", "state")
end)

test("gives no nameplate to NPCs", function(world)
    Enable(world)
    Approach(world, { gameObject = false, cursor = "Speak", inRange = true })
    equal(CVar("SoftTargetNameplateInteract"), "0", "nameplate CVar")
    equal(CVar("SoftTargetIconInteract"), "0", "no interaction icon")
    equal(SoftPlate(), nil, "no nameplate")
    equal(Glow(world), nil, "glow")
end)

test("follows the soft target and stops when there is none", function(world)
    local tickers = world:TickerCount()
    Enable(world)
    Approach(world, Herb())
    equal(world:TickerCount(), tickers + 1, "ticker while glowing")

    Approach(world, { cursor = "Mine", inRange = true })
    local plate, category = Glow(world)
    equal(category, "ore", "new object")
    expect(plate ~= nil and plate == SoftPlate(), "on the new nameplate")

    Approach(world, nil)
    equal(Glow(world), nil, "glow gone")
    equal(world:TickerCount(), tickers, "ticker stopped")
end)

test("finds the nameplate by its token when the unit doesn't give it", function(world)
    world.softInteractPlateByUnit = false
    Enable(world)
    Approach(world, Herb())
    local plate, category = Glow(world)
    expect(plate ~= nil, "glow shown")
    equal(category, "herbs", "category")
end)

test("hides as combat starts and comes back after it", function(world)
    Enable(world)
    Approach(world, Herb())
    world:EnterCombat()
    equal(Glow(world), nil, "hidden in combat")
    equal(CVar("SoftTargetNameplateInteract"), "0", "nameplate closed before combat")
    Settle(world)
    equal(SoftPlate(), nil, "no nameplate in combat")

    Approach(world, { cursor = "Mine", inRange = true })
    world:Elapse(1)
    equal(Glow(world), nil, "nothing glows in combat")
    equal(#world.combatCVarWrites, 0, "no CVar writes in combat")

    world:LeaveCombat()
    Settle(world)
    equal(select(2, Glow(world)), "ore", "glows again")
end)

test("disabling puts the player's settings back", function(world)
    local tickers = world:TickerCount()
    Enable(world)
    Approach(world, Herb())
    Set(world, "enabled", false)
    Settle(world)
    equal(CVar("SoftTargetInteract"), "1", "interact key")
    equal(CVar("SoftTargetIconGameObject"), "0", "object nameplates")
    equal(CVar("SoftTargetInteractArc"), "0", "arc")
    equal(CVar("SoftTargetInteractOnlyInRange"), "1", "out of reach")
    equal(CVar("SoftTargetInteractRange"), "10", "range")
    equal(CVar("SoftTargetNameplateInteract"), "0", "nameplate")
    equal(CVar("SoftTargetIconInteract"), "1", "interaction icon")
    equal(Glow(world), nil, "glow")
    equal(SoftPlate(), nil, "no nameplate")
    equal(world:TickerCount(), tickers, "ticker stopped")
end)

test("keeps a setting the player changed while it was on", function(world)
    Enable(world)
    C_CVar.SetCVar("SoftTargetInteractArc", "1")
    Set(world, "enabled", false)
    equal(CVar("SoftTargetInteractArc"), "1", "player's arc")
    equal(CVar("SoftTargetInteract"), "1", "the others restored")
end)

test("disabled in combat, puts the settings back after it", function(world)
    Enable(world)
    world.inCombat = true
    Set(world, "enabled", false)
    equal(CVar("SoftTargetInteract"), "3", "unchanged in combat")
    world:LeaveCombat()
    equal(CVar("SoftTargetInteract"), "1", "restored after combat")
end)

test("can glow without the interaction icon", function(world)
    Enable(world)
    Set(world, "icon", false)
    Approach(world, Herb())
    expect(Glow(world) ~= nil, "glows")
    equal(CVar("SoftTargetIconInteract"), "0", "no interaction icon")
end)
