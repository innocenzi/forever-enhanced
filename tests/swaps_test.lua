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

-- The editor ------------------------------------------------------------------------

local KICK, KICK_ICON = 1766, 132219

-- Opens the swaps editor with its button in the settings panel.
local function OpenEditor(world)
    world:SettingsButton(world.L["combat.swaps.title"]).data.OnButtonClick()
    return ForeverEnhancedSwapsEditor
end

-- Drags the spell from the spellbook onto `side` ("original" or "replacement")
-- of the editor's row `index`.
local function Drop(world, editor, index, side, spellID)
    world:PickupSpell(spellID)
    editor.Rows[index][side]:RunScript("OnReceiveDrag")
end

-- The editor's rows, "Original > Replacement" each ("?" for an empty slot).
local function Rows(editor)
    local shown = {}
    for _, row in ipairs(editor.Rows) do
        if row:IsShown() then
            local original, replacement = row.original.spellID, row.replacement.spellID
            table.insert(
                shown,
                (original and Name(original) or "?") .. " > " .. (replacement and Name(replacement) or "?")
            )
        end
    end
    return table.concat(shown, "; ")
end

-- A menu entry's text without its icon.
local function MenuText(entry)
    return (entry.text:gsub("^|T.-|t ", ""))
end

-- Clicks `side` of the editor's row `index` with nothing on the cursor: the
-- spell menu it opens, "Tab: Spell, Spell; Tab: ...".
local function SpellMenu(world, editor, index, side)
    editor.Rows[index][side]:RunScript("OnClick", "LeftButton")
    local tabs = {}
    for _, tab in ipairs(world:ContextMenu()) do
        local spells = {}
        for _, spell in ipairs(tab.children) do
            table.insert(spells, MenuText(spell))
        end
        table.insert(tabs, MenuText(tab) .. ": " .. table.concat(spells, ", "))
    end
    return table.concat(tabs, "; ")
end

-- Picks the spell from the spell menu of `side` of the editor's row `index`.
local function Pick(world, editor, index, side, spellID)
    editor.Rows[index][side]:RunScript("OnClick", "LeftButton")
    for _, tab in ipairs(world:ContextMenu()) do
        for _, spell in ipairs(tab.children) do
            if MenuText(spell) == Name(spellID) then
                return spell.callback()
            end
        end
    end
    error("not in the spell menu: " .. Name(spellID))
end

local function SavedSwaps(world)
    local store = world.env.ForeverEnhancedCharacterDB.combat
    return store and store.swaps and store.swaps.swaps
end

-- A Mage with Sinister Strike on the main bar's first button (key 1).
local function Mage(world)
    world.player.class = "MAGE"
    world:PlaceSpell(1, SINISTER_STRIKE)
    world:Bind("1", "ACTIONBUTTON1")
    Enable(world)
end

test("starts a Rogue with the Ghostly Strike swaps, saved only once edited", function(world)
    Rogue(world)
    Enable(world)
    local editor = OpenEditor(world)
    expect(editor:IsShown(), "editor opened")
    equal(
        Rows(editor),
        ("%s > %s; %s > %s; ? > ?"):format(Name(BACKSTAB), Name(AMBUSH), Name(SINISTER_STRIKE), Name(GARROTE)),
        "rows, then one to add a swap"
    )
    equal(SavedSwaps(world), nil, "defaults not saved")

    OpenEditor(world)
    expect(not editor:IsShown(), "the button closes it again")
end)

test("removing a swap gives its buttons back", function(world)
    Rogue(world)
    Enable(world)
    world:SetSpellUsable(AMBUSH, true)
    local editor = OpenEditor(world)
    editor.Rows[1].Remove:RunScript("OnClick")
    world:NextFrame()

    equal(Rows(editor), ("%s > %s; ? > ?"):format(Name(SINISTER_STRIKE), Name(GARROTE)), "rows")
    equal(#SavedSwaps(world), 1, "saved")
    equal(world:SwapShown(ActionButton1), nil, "replacement shown")
    Press(world, "1")
    equal(Casts(world), Name(BACKSTAB), "casts")
end)

test("adds a swap dragged onto the editor, for any class", function(world)
    Mage(world)
    local editor = OpenEditor(world)
    equal(Rows(editor), "? > ?", "no swaps")

    Drop(world, editor, 1, "original", SINISTER_STRIKE)
    equal(world.cursorAction, nil, "cursor emptied")
    equal(SavedSwaps(world), nil, "not saved with one spell")
    Drop(world, editor, 1, "replacement", KICK)
    equal(Rows(editor), ("%s > %s; ? > ?"):format(Name(SINISTER_STRIKE), Name(KICK)), "rows")
    equal(SavedSwaps(world)[1].replacement, KICK, "saved once both are in")

    world:NextFrame()
    equal(world:SwapShown(ActionButton1), KICK_ICON, "shown on the bar")
    Press(world, "1")
    equal(Casts(world), Name(KICK), "casts")

    Drop(world, editor, 1, "replacement", AMBUSH)
    equal(SavedSwaps(world)[1].replacement, AMBUSH, "a saved swap changes at once")
end)

test("picks spells from the spellbook's tabs", function(world)
    Mage(world)
    local editor = OpenEditor(world)
    equal(
        SpellMenu(world, editor, 1, "original"),
        ("General: %s; Combat: %s, %s, %s, %s"):format(
            Name(KICK),
            Name(BACKSTAB),
            Name(AMBUSH),
            Name(SINISTER_STRIKE),
            Name(GARROTE)
        ),
        "the shown tabs and their spells, without passives"
    )

    Pick(world, editor, 1, "original", SINISTER_STRIKE)
    Pick(world, editor, 1, "replacement", KICK)
    equal(Rows(editor), ("%s > %s; ? > ?"):format(Name(SINISTER_STRIKE), Name(KICK)), "rows")
    equal(SavedSwaps(world)[1].replacement, KICK, "saved")

    Pick(world, editor, 2, "original", SINISTER_STRIKE)
    equal(world.errors[#world.errors], world.L["combat.swaps.editor.alreadySwapped"], "checked like a drop")
end)

test("refuses what can't be swapped", function(world)
    Rogue(world)
    Enable(world)
    local editor = OpenEditor(world)

    Drop(world, editor, 3, "original", BACKSTAB_RANK_2)
    equal(world.errors[#world.errors], world.L["combat.swaps.editor.alreadySwapped"], "any rank of a replaced spell")
    Drop(world, editor, 3, "original", KICK)
    Drop(world, editor, 3, "replacement", KICK)
    equal(world.errors[#world.errors], world.L["combat.swaps.editor.sameSpell"], "a spell for itself")
    world.cursor = "G1"
    editor.Rows[3].replacement:RunScript("OnReceiveDrag")
    equal(world.errors[#world.errors], world.L["combat.swaps.editor.notSpell"], "an item")
    equal(world.cursor, nil, "cursor emptied")

    equal(#world.errors, 3, "errors")
    equal(SavedSwaps(world), nil, "nothing saved")
    equal(Rows(editor):match("[^;]+$"), (" %s > ?"):format(Name(KICK)), "the swap being added keeps its spell")
end)

test("uses the character's saved swaps", function(world)
    world.env.ForeverEnhancedCharacterDB.combat =
        { swaps = { swaps = { { original = BACKSTAB, replacement = KICK } } } }
    Rogue(world)
    Enable(world)
    world:NextFrame()
    equal(world:SwapShown(ActionButton1), KICK_ICON, "saved swap")
    equal(Rows(OpenEditor(world)), ("%s > %s; ? > ?"):format(Name(BACKSTAB), Name(KICK)), "instead of the defaults")
end)

test("hides a replacement on its own cooldown, and casts the original meanwhile", function(world)
    Mage(world)
    local editor = OpenEditor(world)
    Drop(world, editor, 1, "original", SINISTER_STRIKE)
    Drop(world, editor, 1, "replacement", KICK)
    world:NextFrame()

    world:SetCooldown(KICK, 10)
    world:NextFrame()
    equal(world:SwapShown(ActionButton1), nil, "hidden on cooldown")
    world:PressKey("1")
    equal(Casts(world), Name(SINISTER_STRIKE), "the original")
    equal(#world.uiErrors, 0, "Kick's refusal muted")

    world:Elapse(10)
    equal(world:SwapShown(ActionButton1), KICK_ICON, "back once ready")
    world:PressKey("1")
    world:NextFrame()
    equal(world:SwapShown(ActionButton1), KICK_ICON, "kept through the global cooldown")
end)

test("the editor closes with the settings panel", function(world)
    Rogue(world)
    Enable(world)
    local editor = OpenEditor(world)
    SettingsPanel:Hide()
    expect(not editor:IsVisible(), "hidden with the panel")
end)

test("the editor moves like the other windows", function(world)
    Rogue(world)
    Enable(world)
    local editor = OpenEditor(world)
    local place = world:Anchor(editor)
    world:DragTitle(editor, 300, 400)
    equal(world:Anchor(editor), "TOPLEFT UIParent BOTTOMLEFT 300 400", "dropped")

    OpenEditor(world)
    OpenEditor(world)
    equal(world:Anchor(editor), "TOPLEFT UIParent BOTTOMLEFT 300 400", "reopened where it was left")

    world:Setting("interface.windows.enabled"):SetValue(false)
    equal(world:Anchor(editor), place, "back over the settings panel with movable windows off")
    expect(not world:HasTitleHandle(editor), "no handle while off")
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
