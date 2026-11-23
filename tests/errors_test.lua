-- Hide Error Messages: the game's errors (UI_ERROR_MESSAGE) hidden, all of them
-- or only those of chosen spells' casts (until the next frame), always or only
-- in combat; our own errors still shown, the frame given back as it was when
-- the feature is turned off, and the editor of the chosen spells.

local EVENT = "UI_ERROR_MESSAGE"

local function Set(world, key, value)
    world:Setting("combat.errors." .. key):SetValue(value)
end

local function GameError(world)
    world:Fire(EVENT, 0, "Not enough mana")
end

test("hides the game's errors, not ours", function(world)
    Set(world, "enabled", true)
    GameError(world)
    equal(#world.uiErrors, 0, "game errors shown")

    ForeverEnhanced:Error("ours")
    equal(world.errors[#world.errors], "ours", "our error")

    Set(world, "enabled", false)
    GameError(world)
    equal(#world.uiErrors, 1, "game errors shown again once off")
end)

test("hides errors only in combat", function(world)
    Set(world, "enabled", true)
    Set(world, "combat", true)
    GameError(world)
    equal(#world.uiErrors, 1, "shown out of combat")

    world:EnterCombat()
    GameError(world)
    equal(#world.uiErrors, 1, "hidden in combat")

    world:LeaveCombat()
    GameError(world)
    equal(#world.uiErrors, 2, "shown again after combat")
end)

test("keeps the errors another addon hid", function(world)
    UIErrorsFrame:UnregisterEvent(EVENT)
    Set(world, "enabled", true)
    Set(world, "enabled", false)
    expect(not UIErrorsFrame:IsEventRegistered(EVENT), "still unregistered")
end)

-- Chosen spells ---------------------------------------------------------------------

local BACKSTAB, BACKSTAB_RANK_2, SINISTER_STRIKE, KICK = 53, 2589, 1752, 1766

local function Name(spellID)
    return C_Spell.GetSpellName(spellID)
end

-- A Rogue with Backstab on key 1 and Sinister Strike on key 2, both refused
-- (not enough energy) when pressed.
local function Rogue(world)
    world.player.class = "ROGUE"
    world:PlaceSpell(1, BACKSTAB)
    world:PlaceSpell(2, SINISTER_STRIKE)
    world:Bind("1", "ACTIONBUTTON1")
    world:Bind("2", "ACTIONBUTTON2")
    world:SetSpellUsable(BACKSTAB, false)
    world:SetSpellUsable(SINISTER_STRIKE, false)
    world:NextFrame()
end

local function Press(world, key)
    world:PressKey(key)
    world:NextFrame()
end

-- Opens the spells editor with its button beside "Chosen spells only".
local function OpenEditor(world)
    world:SettingsButton(world.L["combat.errors.spells"]).data.OnButtonClick()
    return ForeverEnhancedErrorsEditor
end

-- Drags the spell from the spellbook onto the editor's slot `index`.
local function Drop(world, editor, index, spellID)
    world:PickupSpell(spellID)
    editor.Slots[index]:RunScript("OnReceiveDrag")
end

-- The editor's shown slots, "Spell, Spell, ?" ("?" for the add slot).
local function Slots(editor)
    local shown = {}
    for _, slot in ipairs(editor.Slots) do
        if slot:IsShown() then
            table.insert(shown, slot.spellID and Name(slot.spellID) or "?")
        end
    end
    return table.concat(shown, ", ")
end

-- The character's saved spell IDs, "53, 1766".
local function SavedSpells(world)
    local store = world.env.ForeverEnhancedCharacterDB.combat
    return table.concat(store and store.errors and store.errors.spells or {}, ", ")
end

-- Turns the feature on for chosen spells, with Backstab chosen.
local function ChooseBackstab(world)
    Set(world, "enabled", true)
    Set(world, "spells", true)
    local editor = OpenEditor(world)
    Drop(world, editor, 1, BACKSTAB)
    return editor
end

test("hides the errors of chosen spells only", function(world)
    Rogue(world)
    ChooseBackstab(world)
    expect(UIErrorsFrame:IsEventRegistered(EVENT), "errors shown until a chosen spell is cast")

    Press(world, "1")
    equal(#world.uiErrors, 0, "Backstab's error")
    expect(UIErrorsFrame:IsEventRegistered(EVENT), "errors shown again the next frame")

    Press(world, "2")
    equal(#world.uiErrors, 1, "Sinister Strike's error")
end)

test("hides the errors of every rank of a chosen spell", function(world)
    Rogue(world)
    world:PlaceSpell(1, BACKSTAB_RANK_2)
    ChooseBackstab(world)
    Press(world, "1")
    equal(#world.uiErrors, 0, "the higher rank's error")
end)

test("hides the errors of chosen spells only in combat", function(world)
    Rogue(world)
    ChooseBackstab(world)
    Set(world, "combat", true)
    Press(world, "1")
    equal(#world.uiErrors, 1, "shown out of combat")

    world:EnterCombat()
    Press(world, "1")
    equal(#world.uiErrors, 1, "hidden in combat")
end)

test("chooses spells with the button beside Chosen spells only", function(world)
    local row = world:SettingsButton(world.L["combat.errors.spells"])
    expect(row.setting == world:Setting("combat.errors.spells"), "the toggle's checkbox")
    equal(row.template, "ForeverEnhancedSettingsCheckboxWithButtonControlTemplate", "our checkbox with button row")
    equal(row.data.buttonText, world.L["combat.errors.choose"], "button text")
    expect(row.data.clickRequiresSet, "the button is usable only while checked")
    expect(not row.predicate(), "greyed out while the feature is off")
    Set(world, "enabled", true)
    expect(row.predicate(), "usable once on")
end)

test("keeps chosen spells while every error is hidden", function(world)
    Rogue(world)
    local editor = ChooseBackstab(world)
    Set(world, "spells", false)
    expect(not editor:IsShown(), "editor closed")
    Press(world, "2")
    equal(#world.uiErrors, 0, "every error hidden")

    Set(world, "enabled", false)
    Press(world, "1")
    equal(#world.uiErrors, 1, "errors shown once off")
    equal(SavedSpells(world), tostring(BACKSTAB), "spells kept")
end)

test("edits the chosen spells", function(world)
    Rogue(world)
    local editor = ChooseBackstab(world)
    equal(Slots(editor), Name(BACKSTAB) .. ", ?", "dropped")

    Drop(world, editor, 2, BACKSTAB_RANK_2)
    equal(world.errors[#world.errors], world.L["combat.errors.editor.alreadyChosen"], "another rank refused")

    editor.Slots[2]:RunScript("OnClick", "LeftButton")
    local picked
    for _, tab in ipairs(world:ContextMenu()) do
        for _, spell in ipairs(tab.children) do
            if spell.text:find(Name(KICK), 1, true) then
                picked = spell
            end
        end
    end
    picked.callback()
    equal(Slots(editor), Name(BACKSTAB) .. ", " .. Name(KICK) .. ", ?", "picked from the spellbook")

    editor.Slots[1]:RunScript("OnClick", "RightButton")
    equal(Slots(editor), Name(KICK) .. ", ?", "removed")
    equal(SavedSpells(world), tostring(KICK), "saved for the character")
end)
