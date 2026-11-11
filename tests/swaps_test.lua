-- Ability Swaps: our secure button over Backstab casts Ambush on key down and
-- Backstab on key up, takes the button's keys only on pages holding a swap,
-- mutes the cast meant to fail, shows Ambush while it can be cast, and is set
-- up out of combat only (see Secure frames in tests/wow.lua).

local BACKSTAB, BACKSTAB_RANK_2, AMBUSH, SINISTER_STRIKE, GARROTE = 53, 2589, 8676, 1752, 703
local STEALTH_BAR = 1
local AMBUSH_ICON = 132282

local function Name(spellID)
    return C_Spell.GetSpellName(spellID)
end

-- A Rogue with Backstab on the main bar's first button (key 1) and Ambush in
-- the same place on the Stealth bar.
local function Rogue(world)
    world.player.class = "ROGUE"
    world:PlaceSpell(1, BACKSTAB)
    world:PlaceSpell(73, AMBUSH)
    world:Bind("1", "ACTIONBUTTON1")
    world:NextFrame()
end

local function Enable(world)
    world:Setting("combat.swaps.enabled"):SetValue(true)
    world:NextFrame()
end

local function Press(world, key)
    world:PressKey(key)
    world:Elapse(2)
end

local function Casts(world)
    return table.concat(world.casts, ", ")
end

test("is off by default", function(world)
    Rogue(world)
    world:SetSpellUsable(AMBUSH, true)
    Press(world, "1")
    equal(Casts(world), Name(BACKSTAB), "casts")
    equal(world:Overlay(ActionButton1), nil, "overlay")
end)

test("casts the original on release while the replacement can't be cast", function(world)
    Rogue(world)
    Enable(world)
    Press(world, "1")
    equal(Casts(world), Name(BACKSTAB), "casts")
    equal(#world.uiErrors, 0, "errors shown")
    expect(UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE"), "errors shown again after the click")
    equal(world:SwapShown(ActionButton1), nil, "replacement shown")
end)

test("shows and casts the replacement while it can be cast", function(world)
    Rogue(world)
    Enable(world)
    world:SetSpellUsable(AMBUSH, true)
    world:NextFrame()
    local icon, glow = world:SwapShown(ActionButton1)
    equal(icon, AMBUSH_ICON, "icon")
    expect(glow, "glow")

    Press(world, "1")
    equal(Casts(world), Name(AMBUSH), "casts")
    equal(#world.uiErrors, 0, "the release's global cooldown error is muted")

    world:ClickButton(ActionButton1)
    equal(Casts(world), Name(AMBUSH) .. ", " .. Name(AMBUSH), "mouse click")

    world:SetSpellUsable(AMBUSH, false)
    world:NextFrame()
    equal(world:SwapShown(ActionButton1), nil, "replacement hidden once it can't be cast")
end)

test("tints the replacement blue while short of energy", function(world)
    Rogue(world)
    Enable(world)
    world:SetSpellUsable(AMBUSH, true)
    world:NextFrame()
    equal(select(3, world:SwapShown(ActionButton1)), "white", "enough energy")

    world:SetShortOfPower(AMBUSH, true)
    world:NextFrame()
    local icon, _, tint = world:SwapShown(ActionButton1)
    equal(icon, AMBUSH_ICON, "still shown")
    equal(tint, "blue", "short of energy")

    world:SetShortOfPower(AMBUSH, false)
    world:NextFrame()
    equal(select(3, world:SwapShown(ActionButton1)), "white", "energy back")
end)

test("still shows the original's own errors", function(world)
    Rogue(world)
    Enable(world)
    world.noPowerSpells[BACKSTAB] = true
    Press(world, "1")
    equal(Casts(world), "", "casts")
    equal(#world.uiErrors, 1, "Backstab's error shown, not Ambush's")
end)

test("gives the key back on the Stealth bar, in combat too", function(world)
    Rogue(world)
    Enable(world)
    world:SetSpellUsable(AMBUSH, true)
    world:EnterCombat()

    world:SetBonusBar(STEALTH_BAR)
    expect(not world:Overlay(ActionButton1):IsShown(), "overlay hidden")
    equal(#world.overrides, 0, "key given back")
    Press(world, "1")
    equal(Casts(world), Name(AMBUSH), "Blizzard's button casts the Stealth bar's Ambush")

    world:SetBonusBar(0)
    expect(world:Overlay(ActionButton1):IsShown(), "overlay back")
    world:SetSpellUsable(AMBUSH, false)
    Press(world, "1")
    equal(Casts(world), Name(AMBUSH) .. ", " .. Name(BACKSTAB), "swap back on the main bar")
end)

test("shows the button pressed while the key is held", function(world)
    Rogue(world)
    Enable(world)
    world:KeyDown("1")
    equal(ActionButton1:GetButtonState(), "PUSHED", "held")
    world:KeyUp("1")
    equal(ActionButton1:GetButtonState(), "NORMAL", "released")
end)

test("releases Blizzard's button when Stealth ends during a press", function(world)
    Rogue(world)
    Enable(world)
    world:SetBonusBar(STEALTH_BAR)
    world:SetSpellUsable(AMBUSH, true)
    world:EnterCombat()

    -- Ambush from Stealth: the press goes to Blizzard's button, Stealth ends
    -- with the key held, our overlay takes the key, and the release is lost.
    world:KeyDown("1")
    equal(ActionButton1:GetButtonState(), "PUSHED", "held")
    world:SetBonusBar(0)
    world:KeyUp("1")
    equal(Casts(world), Name(AMBUSH), "casts")
    equal(ActionButton1:GetButtonState(), "NORMAL", "released")
end)

test("releases Blizzard's button when Stealth starts during a press", function(world)
    Rogue(world)
    Enable(world)
    world:EnterCombat()

    -- The press goes to our overlay, Stealth starts with the key held, our
    -- overlay gives the key back, and the release is lost.
    world:KeyDown("1")
    equal(ActionButton1:GetButtonState(), "PUSHED", "held")
    world:SetBonusBar(STEALTH_BAR)
    world:KeyUp("1")
    equal(ActionButton1:GetButtonState(), "NORMAL", "released")
end)

test("swaps any rank, on the other bars and other pages", function(world)
    Rogue(world)
    world:PlaceSpell(61, BACKSTAB_RANK_2)
    world:Bind("2", "MULTIACTIONBAR1BUTTON1")
    world:PlaceSpell(14, SINISTER_STRIKE)
    world:Bind("3", "ACTIONBUTTON2")
    Enable(world)
    world:SetSpellUsable(AMBUSH, true)
    world:SetSpellUsable(GARROTE, true)

    Press(world, "2")
    equal(Casts(world), Name(AMBUSH), "rank 2 on the bottom left bar")

    Press(world, "3")
    equal(Casts(world), Name(AMBUSH), "Sinister Strike is on page 2")
    world:SetActionBarPage(2)
    Press(world, "3")
    equal(Casts(world), Name(AMBUSH) .. ", " .. Name(GARROTE), "page 2")
end)

test("clears the highlight of a newly placed spell once pressed", function(world)
    Rogue(world)
    Enable(world)
    world:MarkNewAction(1)
    expect(ActionButton1.NewActionTexture:IsShown(), "highlighted")
    Press(world, "1")
    expect(not ActionButton1.NewActionTexture:IsShown(), "highlight cleared")
end)

test("follows new keys", function(world)
    Rogue(world)
    Enable(world)
    world:SetSpellUsable(AMBUSH, true)
    world:Bind("Q", "ACTIONBUTTON1")
    world:NextFrame()
    Press(world, "Q")
    equal(Casts(world), Name(AMBUSH), "casts")
end)

test("waits for the end of combat to follow bar changes", function(world)
    Rogue(world)
    Enable(world)
    world:SetSpellUsable(GARROTE, true)
    world:EnterCombat()
    world:PlaceSpell(2, SINISTER_STRIKE)
    world:Bind("2", "ACTIONBUTTON2")
    world:NextFrame()
    equal(world:Overlay(ActionButton2), nil, "no overlay in combat")

    world:LeaveCombat()
    Press(world, "2")
    equal(Casts(world), Name(GARROTE), "casts")
end)

test("lets the player drag the spell away", function(world)
    Rogue(world)
    Enable(world)
    world.lockActionBars = false
    local overlay = world:Overlay(ActionButton1)
    overlay:RunScript("OnDragStart")
    equal(world.cursorAction, BACKSTAB, "picked up")
    world:NextFrame()
    expect(not overlay:IsShown(), "overlay hidden")
end)

test("turning a swap off gives its buttons back", function(world)
    Rogue(world)
    Enable(world)
    world:SetSpellUsable(AMBUSH, true)
    world:Setting("combat.swaps.ambush"):SetValue(false)
    world:NextFrame()
    equal(world:SwapShown(ActionButton1), nil, "replacement shown")
    Press(world, "1")
    equal(Casts(world), Name(BACKSTAB), "casts")
end)

test("turning it off restores the buttons", function(world)
    Rogue(world)
    Enable(world)
    world:SetSpellUsable(AMBUSH, true)
    world:NextFrame()
    world:Setting("combat.swaps.enabled"):SetValue(false)
    world:NextFrame()
    equal(world:SwapShown(ActionButton1), nil, "replacement shown")
    expect(not world:Overlay(ActionButton1):IsShown(), "overlay hidden")
    equal(#world.overrides, 0, "keys given back")
    Press(world, "1")
    equal(Casts(world), Name(BACKSTAB), "casts")
end)

test("turned off in combat, gives the keys back once it ends", function(world)
    Rogue(world)
    Enable(world)
    world:EnterCombat()
    world:Setting("combat.swaps.enabled"):SetValue(false)
    equal(#world.overrides, 1, "keys kept in combat")
    world:LeaveCombat()
    equal(#world.overrides, 0, "keys given back")
end)

test("leaves other classes alone", function(world)
    Rogue(world)
    world.player.class = "MAGE"
    Enable(world)
    equal(world:Overlay(ActionButton1), nil, "overlay")
end)
