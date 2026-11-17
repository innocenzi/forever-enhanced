-- Duplicate macros: the Duplicate button copies the selected macro (name, the
-- icon the player picked, text) into the same tab and selects the copy.

local QUESTION_MARK = 134400
local SINISTER_STRIKE_ICON = 136189

local function AddMacros(world)
    world.macros.account = {
        { name = "Attack", icon = 132090, body = "/startattack" },
        {
            name = "Strike",
            icon = QUESTION_MARK,
            shownIcon = SINISTER_STRIKE_ICON,
            body = "#showtooltip\n/cast Sinister Strike",
        },
    }
    world.macros.character = {
        { name = "Mount", icon = 132261, body = "/cast Riding" },
    }
end

test("duplicates the selected macro and selects the copy", function(world)
    AddMacros(world)
    world:OpenMacros()
    world:SelectMacro(2)
    expect(world:DuplicateMacroButton():IsShown(), "button shown")
    expect(world:DuplicateMacroButton():IsEnabled(), "button enabled")

    world:DuplicateMacro()
    equal(world:MacroNames(), "Attack Strike [Strike]", "copy selected")
    local copy = world.macros.account[3]
    equal(copy.icon, QUESTION_MARK, "the icon the player picked, not the one shown")
    equal(copy.body, "#showtooltip\n/cast Sinister Strike", "text")
end)

test("duplicates into the character tab", function(world)
    AddMacros(world)
    world:OpenMacros(2)
    world:DuplicateMacro()
    equal(world:MacroNames(), "Mount [Mount]", "copy in the character tab")
    equal(#world.macros.account, 2, "account macros untouched")
end)

test("copies the text being edited", function(world)
    AddMacros(world)
    world:OpenMacros()
    world:TypeMacroText("/startattack\n/cast Sinister Strike")
    world:DuplicateMacro()
    equal(world.macros.account[1].body, "/startattack\n/cast Sinister Strike", "original saved")
    equal(world.macros.account[2].body, "/startattack\n/cast Sinister Strike", "copy")
end)

test("is disabled when the tab is full or has no macro", function(world)
    world:OpenMacros(2)
    expect(not world:DuplicateMacroButton():IsEnabled(), "no macro")

    for index = 1, Constants.MacroConsts.MAX_CHARACTER_MACROS do
        world.macros.character[index] = { name = "M" .. index, icon = 132261, body = "" }
    end
    world:OpenMacros(2)
    expect(not world:DuplicateMacroButton():IsEnabled(), "tab full")
    world:DuplicateMacro()
    equal(#world.macros.character, Constants.MacroConsts.MAX_CHARACTER_MACROS, "nothing created")
end)

test("is disabled while the icon picker is open", function(world)
    AddMacros(world)
    world:OpenMacros()
    MacroPopupFrame:Show()
    expect(not world:DuplicateMacroButton():IsEnabled(), "picker open")
    MacroPopupFrame:Hide()
    expect(world:DuplicateMacroButton():IsEnabled(), "picker closed")
end)

test("is disabled in combat and in click binding mode", function(world)
    AddMacros(world)
    world:OpenMacros()
    world:EnterCombat()
    expect(not world:DuplicateMacroButton():IsEnabled(), "in combat")
    local _, lines = world:DuplicateMacroTooltip()
    equal(lines[1], ERR_NOT_IN_COMBAT, "combat reason")
    world:LeaveCombat()
    expect(world:DuplicateMacroButton():IsEnabled(), "after combat")

    world.clickBinding = true
    MacroFrame:UpdateButtons()
    expect(not world:DuplicateMacroButton():IsEnabled(), "click binding")
    local tooltip
    tooltip, lines = world:DuplicateMacroTooltip()
    equal(tooltip, world.L["interface.macros.duplicate.tooltip"], "tooltip")
    equal(lines[1], CLICK_BINDING_BUTTON_DISABLED, "click binding reason")
end)

test("hides the button when disabled", function(world)
    AddMacros(world)
    world:OpenMacros()
    world:Setting("interface.macros.enabled"):SetValue(false)
    expect(not world:DuplicateMacroButton():IsShown(), "hidden")
    world:Setting("interface.macros.enabled"):SetValue(true)
    expect(world:DuplicateMacroButton():IsShown(), "shown")
    expect(world:DuplicateMacroButton():IsEnabled(), "enabled")
end)
