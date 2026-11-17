-- Macros, Duplicate button and grouped buttons. The Duplicate button
-- copies the selected macro (name, the icon the player picked, text) into the
-- same tab and selects the copy; the layout moves Blizzard's buttons next to
-- what they act on and puts them back when turned off.

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
    equal(tooltip, world.L["interface.macros.duplicate.button.tooltip"], "tooltip")
    equal(lines[1], CLICK_BINDING_BUTTON_DISABLED, "click binding reason")
end)

test("hides the button when disabled", function(world)
    AddMacros(world)
    world:OpenMacros()
    world:Setting("interface.macros.duplicate"):SetValue(false)
    expect(not world:DuplicateMacroButton():IsShown(), "hidden by its toggle")
    world:Setting("interface.macros.duplicate"):SetValue(true)
    expect(world:DuplicateMacroButton():IsShown(), "shown")

    world:Setting("interface.macros.enabled"):SetValue(false)
    expect(not world:DuplicateMacroButton():IsShown(), "hidden with the feature")
    world:Setting("interface.macros.enabled"):SetValue(true)
    expect(world:DuplicateMacroButton():IsShown(), "shown")
    expect(world:DuplicateMacroButton():IsEnabled(), "enabled")
end)

-- Blizzard's XML anchors.
local BLIZZARD_ANCHORS = {
    MacroDeleteButton = "BOTTOMLEFT MacroFrame BOTTOMLEFT 4 4",
    MacroNewButton = "BOTTOMRIGHT MacroFrame BOTTOMRIGHT -82 4",
    MacroSaveButton = "BOTTOM MacroCancelButton TOP 0 15",
    MacroCancelButton = "BOTTOMRIGHT MacroFrameScrollFrame TOPRIGHT 25 10",
}

local function ExpectBlizzardLayout(world, context)
    for name, anchors in pairs(BLIZZARD_ANCHORS) do
        equal(world:MacroButtonAnchors(_G[name]), anchors, context .. ": " .. name)
    end
    expect(MacroCancelButton:IsShown(), context .. ": Cancel shown")
    expect(MacroExitButton:IsShown(), context .. ": Exit shown")
    expect(MacroDeleteButton:IsShown(), context .. ": Delete shown")
    equal(
        world:MacroButtonAnchors(world:DuplicateMacroButton()),
        "RIGHT MacroNewButton LEFT -2 0",
        context .. ": Duplicate"
    )
end

test("groups the buttons by what they act on", function(world)
    AddMacros(world)
    world:OpenMacros()
    equal(world:MacroButtonAnchors(MacroDeleteButton), "LEFT MacroEditButton RIGHT 2 0", "Delete beside Edit")
    equal(world:MacroButtonAnchors(MacroNewButton), "BOTTOMLEFT MacroFrame BOTTOMLEFT 4 4", "New bottom left")
    equal(
        world:MacroButtonAnchors(world:DuplicateMacroButton()),
        "LEFT MacroNewButton RIGHT 2 0",
        "Duplicate after New"
    )
    equal(world:MacroButtonAnchors(MacroSaveButton), "BOTTOMRIGHT MacroFrame BOTTOMRIGHT -5 4", "Save bottom right")
    expect(not MacroCancelButton:IsShown(), "Cancel hidden")
    expect(not MacroExitButton:IsShown(), "Exit hidden")
end)

test("hides Delete along with the macro's details when the tab has none", function(world)
    AddMacros(world)
    world.macros.character = {}
    world:OpenMacros()
    expect(MacroDeleteButton:IsShown(), "macro selected")
    world:OpenMacros(2)
    expect(not MacroEditButton:IsShown() and not MacroDeleteButton:IsShown(), "no macro")
    MacroFrame:ChangeTab(1)
    expect(MacroDeleteButton:IsShown(), "macro selected again")
end)

test("puts Blizzard's layout back when the layout or the feature is disabled", function(world)
    AddMacros(world)
    world.macros.character = {}
    world:OpenMacros(2)
    world:Setting("interface.macros.layout"):SetValue(false)
    ExpectBlizzardLayout(world, "layout off")

    world:Setting("interface.macros.layout"):SetValue(true)
    expect(not MacroCancelButton:IsShown() and not MacroExitButton:IsShown(), "Cancel and Exit hidden again")
    world:Setting("interface.macros.enabled"):SetValue(false)
    ExpectBlizzardLayout(world, "feature off")
end)

test("lays out the window when its addon loads after login", function(world)
    world:Setting("interface.macros.layout"):SetValue(false)
    world:OpenMacros()
    ExpectBlizzardLayout(world, "loaded with the layout off")
    world:Setting("interface.macros.layout"):SetValue(true)
    equal(world:MacroButtonAnchors(MacroNewButton), "BOTTOMLEFT MacroFrame BOTTOMLEFT 4 4", "applied")
end)
