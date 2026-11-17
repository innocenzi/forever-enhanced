-- Macro icon search: the picker's grid shows the icons matching the search
-- (by file name, or the name of a spell or item of the player's showing them),
-- each once, and Blizzard's selection keeps working through it.
-- Icons (see world.macroIcons): 132090 ability_backstab (Backstab), 136189
-- spell_shadow_ritualofsacrifice (Sinister Strike), 135807 spell_fire_fireball,
-- 135808 spell_fire_fireball02, 135809 spell_fire_firebolt, 134414
-- inv_misc_rune_01, 133784 inv_misc_coin_01.

local QUESTION_MARK = [[INTERFACE\ICONS\INV_MISC_QUESTIONMARK]]
-- The full list, the question mark selected (the default macro icon).
local FULL_LIST = "[" .. QUESTION_MARK .. "] 132090 136189 135807 135808 135809 132090 135807 134414 133784"

test("shows the icons whose file name matches", function(world)
    world:OpenMacroIcons()
    expect(world:MacroIconSearchBox():IsShown(), "search box shown")
    equal(world:MacroIcons(), FULL_LIST, "full list")

    world:SearchMacroIcons("fireball")
    equal(world:MacroIcons(), "135807 135808", "matches, each once")
    equal(MacroPopupFrame.IconSelector.scrolledTo, 1, "scrolled to the top")

    world:SearchMacroIcons("FIRE bolt")
    equal(world:MacroIcons(), "135809", "every word, in any case")

    world:SearchMacroIcons("questionmark")
    equal(world:MacroIcons(), "[" .. QUESTION_MARK .. "]", "icons named by path")

    world:SearchMacroIcons("")
    equal(world:MacroIcons(), FULL_LIST, "full list back")
end)

test("shows the icons of the player's spells and items by their names", function(world)
    world.itemIcons.G1 = 134414
    world.itemIcons.GJUNK = 133784
    world.equipped[16] = "GJUNK"
    world:OpenMacroIcons()

    -- Sinister Strike's icon is spell_shadow_ritualofsacrifice.
    world:SearchMacroIcons(C_Spell.GetSpellName(1752))
    equal(world:MacroIcons(), "136189", "spell")

    -- Bag items are named after their GUIDs.
    world:SearchMacroIcons("g1")
    equal(world:MacroIcons(), "134414", "bag item")

    -- Only equipped now (GJUNK is the last item of the backpack).
    world.bags[0][4] = nil
    world:SearchMacroIcons("gjunk")
    equal(world:MacroIcons(), "133784", "equipped item")
end)

test("selects the clicked match, and keeps the selection when the search changes", function(world)
    world:OpenMacroIcons(135807)
    world:SearchMacroIcons("fire")
    equal(world:MacroIcons(), "[135807] 135808 135809", "selected icon among the matches")

    world:ClickMacroIcon(3)
    equal(world:SelectedMacroIcon(), 135809, "selected")
    equal(world:MacroIcons(), "135807 135808 [135809]", "selection shown")

    world:SearchMacroIcons("fireball")
    equal(world:MacroIcons(), "135807 135808", "selected icon not among the matches")

    world:SearchMacroIcons("")
    equal(world:MacroIcons():match("%[(%d+)%]"), "135809", "selected in the full list")
    equal(MacroPopupFrame.IconSelector.scrolledTo, 6, "scrolled to it")
end)

test("searches again when the icon type changes", function(world)
    world:OpenMacroIcons(135807)
    world:SearchMacroIcons("i")
    world:ChooseMacroIconType("Item")
    equal(world:MacroIcons(), "[135807] 134414 133784", "item icons")
    world:ChooseMacroIconType("Spell")
    equal(world:MacroIcons(), QUESTION_MARK .. " 132090 136189 [135807] 135808 135809", "spell icons")
end)

test("ends the search when the player drops a spell or an item on the picker", function(world)
    world:OpenMacroIcons()
    world:SearchMacroIcons("fireball")
    MacroPopupFrame:SetIconFromMouse(136189)
    equal(world:MacroIconSearchBox():GetText(), "", "search cleared")
    equal(world:MacroIcons():match("%[(%d+)%]"), "136189", "dropped icon selected in the full list")
end)

test("starts each visit with the full list", function(world)
    world:OpenMacroIcons()
    world:SearchMacroIcons("fireball")
    world:CloseMacroIcons()
    equal(world:MacroIconSearchBox():GetText(), "", "search cleared")
    world:OpenMacroIcons()
    equal(world:MacroIcons(), FULL_LIST, "full list")
end)

test("puts the full list back when disabled", function(world)
    world:OpenMacroIcons()
    world:SearchMacroIcons("fireball")
    world:Setting("interface.icons.enabled"):SetValue(false)
    expect(not world:MacroIconSearchBox():IsShown(), "search box hidden")
    equal(world:MacroIcons(), FULL_LIST, "full list")

    world:Setting("interface.icons.enabled"):SetValue(true)
    expect(world:MacroIconSearchBox():IsShown(), "search box shown")
end)

test("reads every icon name of the data", function(world)
    local names = world.ns:GetFeature("interface", "icons").NAMES
    local _, lines = names:gsub("\n", "")
    local _, decoded = names:gsub("[%l%d]+%u[^\n]*", "")
    equal(decoded, lines, "every line decodes")
end)
