-- Fishing: the key (a click binding of our secure button) casts
-- Fishing, equips the best pole first, reels in while Fishing channels
-- (Interact With Target on the bobber, Interact With Mouseover otherwise),
-- and the weapons go back on after the delay or as combat starts. The server
-- starts the channel and lands equipment changes a moment later (see
-- Equipping and Fishing in tests/wow.lua).

local BINDING = "CLICK ForeverEnhancedFishingButton:LeftButton"
local MAIN_HAND, OFF_HAND = 16, 17
local BOBBER = "GameObject-0-1-0-0-35591-0000000001"
local DELAY = 30

local function Fishing(world)
    return world.ns:GetFeature("professions", "fishing")
end

local function Pole(world, guid, level)
    world.weaponSubclasses[guid] = Enum.ItemWeaponSubclass.Fishingpole
    world.twoHanded[guid] = true
    world.itemLevels[guid] = level
end

-- A sword and a dagger in hand, a pole in the bags (slot 3, slot 4 free), the key on F.
local function Fisher(world)
    world.weaponSubclasses.SWORD = Enum.ItemWeaponSubclass.Sword1H
    world.weaponSubclasses.DAGGER = Enum.ItemWeaponSubclass.Dagger
    world.equipped[MAIN_HAND] = "SWORD"
    world.equipped[OFF_HAND] = "DAGGER"
    Pole(world, "POLE", 5)
    world.bags[0][3] = "POLE"
    world.bags[0][4] = nil
    world:Bind("F", BINDING)
end

-- A key press, and the server's answer.
local function Press(world)
    world:PressKey("F")
    world:Elapse(0.1)
end

local function Casts(world)
    return table.concat(world.casts, ", ")
end

local function Equipped(world)
    return (world.equipped[MAIN_HAND] or "-") .. " " .. (world.equipped[OFF_HAND] or "-")
end

local function SpellName()
    return C_Spell.GetSpellName(7620)
end

test("names the key in the key bindings", function(world)
    equal(_G["BINDING_NAME_" .. BINDING], world.L["professions.fishing.binding"], "binding name")
end)

test("the key setting is a binding row, greyed out with the feature off", function(world)
    local setting = world:Setting("professions.fishing.key")
    local row
    for _, category in ipairs(world.categories) do
        for _, initializer in ipairs(category.items) do
            if initializer.setting == setting then
                row = initializer
            end
        end
    end
    expect(row, "row registered")
    equal(row.template, "ForeverEnhancedSettingsBindingControlTemplate", "row template")
    expect(row.predicate(), "editable")
    world:Setting("professions.fishing.enabled"):SetValue(false)
    expect(not row.predicate(), "greyed out")
    equal(world.ns:GetFeature("professions", "fishing").db.key, nil, "not saved with the settings")
end)

test("the key setting binds, replaces and clears the key", function(world)
    local setting = world:Setting("professions.fishing.key")
    equal(setting:GetValue(), "", "unbound")

    setting:SetValue("F")
    equal(GetBindingAction("F"), BINDING, "bound")
    equal(setting:GetValue(), "F", "shown")
    equal(world.savedBindings, 1, "bindings saved")
    Fisher(world)
    world.equipped[MAIN_HAND] = "POLE"
    Press(world)
    equal(Casts(world), SpellName(), "the key casts")

    world:Bind("SHIFT-1", "ACTIONBUTTON1")
    setting:SetValue("SHIFT-1")
    equal(GetBindingAction("SHIFT-1"), BINDING, "new key bound")
    equal(GetBindingAction("F"), "", "old key unbound")
    equal(world.warnings[1], KEY_UNBOUND_ERROR:format("ACTIONBUTTON1"), "the game's warning for the action it took")

    setting:SetValue("")
    equal(GetBindingAction("SHIFT-1"), "", "cleared")
    equal(#world.warnings, 1, "no warning")
end)

test("the key setting changes nothing in combat", function(world)
    local setting = world:Setting("professions.fishing.key")
    world:EnterCombat()
    setting:SetValue("F")
    equal(GetBindingAction("F"), "", "unbound")
end)

test("casts Fishing with a pole in hand", function(world)
    Fisher(world)
    world.equipped[MAIN_HAND] = "POLE"
    world.equipped[OFF_HAND] = nil
    Press(world)
    equal(Casts(world), SpellName(), "casts")
    expect(world.channel, "channels")
    equal(#world.equips, 0, "nothing equipped")
end)

test("equips the pole on the first press and casts on the next", function(world)
    Fisher(world)
    Press(world)
    equal(Casts(world), "", "no cast on the first press")
    equal(Equipped(world), "POLE -", "pole in hand")
    equal(world:Bag(), "G1 G2 SWORD DAGGER", "weapons in the bags")
    equal(#world.uiErrors, 0, "no error")

    Press(world)
    equal(Casts(world), SpellName(), "casts on the second press")
end)

test("presses wait for the pole to land", function(world)
    Fisher(world)
    world:PressKey("F")
    world:PressKey("F")
    world:Elapse(0.1)
    equal(#world.equips, 1, "equipped once")
    equal(Casts(world), "", "no cast")
    equal(#world.uiErrors, 0, "no error")
    Press(world)
    equal(Casts(world), SpellName(), "casts once it landed")
end)

test("picks the best pole the character can use", function(world)
    Fisher(world)
    Pole(world, "STRONG", 25)
    Pole(world, "ARCANITE", 50)
    world.bags[0][1] = "STRONG"
    world.bags[0][2] = "ARCANITE"
    world.unusableItems.ARCANITE = true
    Press(world)
    equal(world.equips[1].guid, "STRONG", "highest item level usable")
end)

test("casts without a pole to equip, and the game says why", function(world)
    Fisher(world)
    world.bags[0][3] = nil
    Press(world)
    equal(Casts(world), "", "no cast")
    equal(#world.equips, 0, "nothing equipped")
    equal(world.uiErrors[1], "Requires Fishing Pole", "the game's error")
end)

test("only casts with the pole part off", function(world)
    Fisher(world)
    world:Setting("professions.fishing.swap"):SetValue(false)
    Press(world)
    equal(#world.equips, 0, "nothing equipped")
    equal(world.uiErrors[1], "Requires Fishing Pole", "the cast was tried")
end)

test("reels in with the bobber as soft target, or the mouseover", function(world)
    Fisher(world)
    Press(world)
    Press(world)
    expect(world.channel, "channels")

    Press(world)
    equal(table.concat(world.interactions, ", "), "INTERACTMOUSEOVER", "the bobber out of reach")
    equal(#world.casts, 1, "no second cast")

    world:SoftInteract({ guid = BOBBER })
    world:NextFrame()
    world:NextFrame()
    Press(world)
    equal(world.interactions[2], "INTERACTTARGET", "the bobber as soft target")

    world:SoftInteract({ guid = "GameObject-0-1-0-0-1617-0000000002" })
    world:NextFrame()
    Press(world)
    equal(world.interactions[3], "INTERACTMOUSEOVER", "a herb nearby isn't the bobber")

    world:StopChannel()
    world:Elapse(2)
    Press(world)
    equal(#world.casts, 2, "casts again once the channel ended")
end)

test("soft targets objects while fishing, and puts the CVars back after", function(world)
    Fisher(world)
    Press(world)
    Press(world)
    equal(C_CVar.GetCVar("SoftTargetInteract"), "3", "keyboard soft targeting")
    equal(C_CVar.GetCVar("SoftTargetInteractRange"), "15", "as far as it goes")
    world:StopChannel()
    world:Elapse(DELAY - 1)
    equal(C_CVar.GetCVar("SoftTargetInteract"), "3", "kept between casts")
    world:Elapse(2)
    equal(C_CVar.GetCVar("SoftTargetInteract"), "1", "put back")
    equal(C_CVar.GetCVar("SoftTargetInteractRange"), "10", "range put back")
end)

test("leaves CVars and keys alone for Fishing cast without the key", function(world)
    Fisher(world)
    world:Bind("F", nil)
    world.equipped[MAIN_HAND] = "POLE"
    CastSpellByName(SpellName())
    world:Elapse(0.1)
    expect(world.channel, "channels")
    equal(C_CVar.GetCVar("SoftTargetInteract"), "1", "CVar untouched")
    equal(#world.overrides, 0, "no override")
end)

test("puts the weapons back after the delay, main hand first", function(world)
    Fisher(world)
    Press(world)
    Press(world)
    world:StopChannel()
    world:Elapse(DELAY - 1)
    equal(Equipped(world), "POLE -", "pole kept between casts")
    world:Elapse(2)
    equal(Equipped(world), "SWORD DAGGER", "weapons back")
    equal(world.equips[2].slot, MAIN_HAND, "main hand first")
    equal(world.equips[3].slot, OFF_HAND, "then the off hand")
    equal(world:Bag(), "G1 G2 POLE -", "pole in the bags")
end)

test("the delay counts from the pole going on when not casting", function(world)
    Fisher(world)
    world:Setting("professions.fishing.delay"):SetValue(30)
    Press(world)
    world:Elapse(31)
    equal(Equipped(world), "SWORD DAGGER", "weapons back")
end)

test("no countdown while the line is out", function(world)
    Fisher(world)
    Press(world)
    Press(world)
    world:Elapse(DELAY * 2)
    equal(Equipped(world), "POLE -", "pole kept while channeling")
end)

test("combat puts the weapons back and gives the key back", function(world)
    Fisher(world)
    Press(world)
    Press(world)
    expect(#world.overrides > 0, "key reels in")
    world:EnterCombat()
    equal(#world.overrides, 0, "key given back before the lockdown")
    world:Elapse(0.2)
    equal(Equipped(world), "SWORD DAGGER", "weapons back in combat")

    Press(world)
    equal(#world.equips, 3, "no pole equipped in combat")
    world:LeaveCombat()
    world:Elapse(DELAY + 1)
    equal(#world.equips, 3, "nothing more after combat")
end)

test("leaves the weapons to the player who took the pole off", function(world)
    Fisher(world)
    Press(world)
    C_Item.EquipItemByName("SWORD", MAIN_HAND)
    world:Elapse(0.1)
    equal(Equipped(world), "SWORD -", "the player's choice")
    world:Elapse(DELAY + 1)
    equal(#world.equips, 2, "nothing put back")
    equal(Equipped(world), "SWORD -", "still the player's choice")
end)

test("skips a weapon no longer in the bags", function(world)
    Fisher(world)
    Press(world)
    world.bags[0][3] = nil -- the sword, sold
    world:Elapse(DELAY + 1)
    equal(Equipped(world), "- DAGGER", "the off hand back, taking the pole off")
end)

test("disabling puts the weapons back and the key casts nothing", function(world)
    Fisher(world)
    Press(world)
    Press(world)
    world:Setting("professions.fishing.enabled"):SetValue(false)
    world:Elapse(0.2)
    equal(Equipped(world), "SWORD DAGGER", "weapons back")
    equal(#world.overrides, 0, "key given back")
    equal(C_CVar.GetCVar("SoftTargetInteract"), "1", "CVar put back")
    world:StopChannel()
    Press(world)
    equal(#world.casts, 1, "no cast")
    equal(#world.equips, 3, "no pole")
end)

test("turning the pole part off puts the weapons back", function(world)
    Fisher(world)
    Press(world)
    world:Setting("professions.fishing.swap"):SetValue(false)
    world:Elapse(0.2)
    equal(Equipped(world), "SWORD DAGGER", "weapons back")
end)
