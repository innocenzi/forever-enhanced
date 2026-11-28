-- Command palette: its key opens a search over commands, typing filters,
-- Up and Down pick, and Enter runs the picked one: a key binding or a
-- button click through an override of Enter, which the palette lets through
-- to the bindings (the game runs it from the key press), or our own code.

local KEY = "CTRL-K"
local BINDING = "FOREVERENHANCED_PALETTE"

local function Palette(world)
    return world.ns:GetFeature("interface", "palette")
end

local function Results(world)
    return Palette(world).Window:GetResults()
end

local function IsOpen(world)
    return Palette(world).Window:IsShown()
end

local function Open(world)
    world:Bind(KEY, BINDING)
    world:PressKey(KEY)
end

-- Closes the palette and opens it again, empty.
local function Reopen(world)
    world:PressKey("ESCAPE")
    world:PressKey(KEY)
end

-- The picked command's key once `text` is typed.
local function Picked(world, text)
    world:Type(text)
    local _, picked = Results(world)
    return picked
end

-- Whether the palette, opened empty, lists the command `key`.
local function Listed(world, key)
    Open(world)
    local found = false
    for _, listed in ipairs(Results(world)) do
        found = found or listed == key
    end
    world:PressKey("ESCAPE")
    return found
end

-- A press of Enter, and the frame after its release.
local function Enter(world)
    world:PressKey("ENTER")
    world:NextFrame()
end

local function Ran(world)
    return table.concat(world.ranBindings, ", ")
end

local function OwnOverrides(world)
    local count = 0
    for _, override in ipairs(world.overrides) do
        if override.key == "ENTER" or override.key == "NUMPADENTER" then
            count = count + 1
        end
    end
    return count
end

-- Opening and closing ------------------------------------------------------------------

test("names the key in the key bindings", function(world)
    equal(world.env["BINDING_NAME_" .. BINDING], world.L["interface.palette.binding"], "binding name")
end)

test("the key opens the palette with every Blizzard command, in order", function(world)
    Open(world)
    expect(IsOpen(world), "open")
    local keys, picked = Results(world)
    equal(keys[1], "interface.palette.commands.character", "first")
    equal(keys[2], "interface.palette.commands.spellbook", "second")
    equal(picked, keys[1], "the first one picked")
end)

test("takes every key but Enter while open, and gives them back once closed", function(world)
    world:Bind("M", "TOGGLEWORLDMAP")
    Open(world)
    world:PressKey("M")
    equal(Ran(world), "", "taken")

    world:PressKey("ESCAPE")
    expect(not IsOpen(world), "Escape closes")
    world:PressKey("M")
    equal(Ran(world), "TOGGLEWORLDMAP", "given back")
end)

test("its key closes it again", function(world)
    Open(world)
    world:PressKey(KEY)
    expect(not IsOpen(world), "closed")
    equal(OwnOverrides(world), 0, "no override left")
end)

test("losing the focus (a click elsewhere) closes it", function(world)
    Open(world)
    CreateFrame("EditBox"):SetFocus()
    expect(not IsOpen(world), "closed")
    equal(OwnOverrides(world), 0, "no override left")
end)

test("closes as the player starts moving", function(world)
    Open(world)
    world:Fire("PLAYER_STARTED_MOVING")
    expect(not IsOpen(world), "closed")
    equal(OwnOverrides(world), 0, "no override left")
end)

test("refuses to open in combat, and closes as combat starts", function(world)
    world:Bind(KEY, BINDING)
    world:EnterCombat()
    world:PressKey(KEY)
    expect(not IsOpen(world), "not opened")
    equal(world.errors[#world.errors], ERR_NOT_IN_COMBAT, "combat error")
    world:LeaveCombat()

    world:PressKey(KEY)
    expect(IsOpen(world), "opened")
    world:EnterCombat()
    expect(not IsOpen(world), "closed")
    equal(OwnOverrides(world), 0, "no override left")
end)

test("does nothing while the feature is off", function(world)
    world:Setting("interface.palette.enabled"):SetValue(false)
    Open(world)
    expect(not IsOpen(world), "not opened")
end)

test("closes when the feature turns off", function(world)
    Open(world)
    world:Setting("interface.palette.enabled"):SetValue(false)
    expect(not IsOpen(world), "closed")
    equal(OwnOverrides(world), 0, "no override left")
end)

-- Finding commands ---------------------------------------------------------------------

test("ranks again as the text changes", function(world)
    Open(world)
    world:Type("fpsx")
    equal(#Results(world), 0, "no match")
    world:PressKey("BACKSPACE")
    local _, picked = Results(world)
    equal(picked, "interface.palette.commands.fps", "found again")
end)

test("finds commands by keyword, accents and case aside", function(world)
    Open(world)
    local keyword = world.locale == "frFR" and "Réputs" or "REP"
    equal(Picked(world, keyword), "interface.palette.commands.reputation", "keyword")
end)

test("finds commands by their English names and keywords, whatever the language", function(world)
    world.env.BINDING_NAME_TOGGLESPELLBOOK = "Grimoire"
    Open(world)
    equal(Picked(world, "grim"), "interface.palette.commands.spellbook", "the client's name")
    Reopen(world)
    equal(Picked(world, "spellbook"), "interface.palette.commands.spellbook", "the English name")
    Reopen(world)
    equal(Picked(world, "abilities"), "interface.palette.commands.spellbook", "an English keyword")
end)

test("finds our own commands by their English names too", function(world)
    world:Setting("combat.swaps.enabled"):SetValue(true)
    Open(world)
    equal(Picked(world, "spell swaps"), "combat.swaps.commands.edit", "found")
end)

test("the recently run commands come first", function(world)
    Open(world)
    world:Type("fps")
    Enter(world)
    world:PressKey(KEY)
    local keys = Results(world)
    equal(keys[1], "interface.palette.commands.fps", "last run first")
end)

test("search ranks the title's start, then words, then text, then letters", function(world)
    local Search = Palette(world).Search
    local function Score(title, text, alias)
        return Search:Score({ title = title, aliases = { alias } }, text)
    end
    expect(Score("World Map", "wor") > Score("World Map", "map wor"), "start over words")
    expect(Score("World Map", "map wor") > Score("Open the map", "he ma"), "words over text")
    expect(Score("Open the map", "he ma") > Score("Character", "chr"), "text over letters")
    expect(Score("Character", "chr") > 0, "letters")
    equal(Score("Character", "xyz"), 0, "no match")
    expect(Score("Réputation", "REPUT") > 0, "accents and case")
    expect(Score("Bags", "inv", "inventory") > 0, "aliases")
    expect(Score("Inventory", "inv") > Score("Bags", "inv", "inventory"), "title over aliases")
    equal(Score("Bags", "iny", "inventory"), 0, "no letters in aliases")
end)

test("letters in order count only from a word's start", function(world)
    local Search = Palette(world).Search
    equal(Search:Score({ title = "Afficher le compteur d’images par seconde" }, "map"), 0, "no word starts with m")
    expect(Search:Score({ title = "World Map" }, "wmp") > 0, "from the first word")
end)

-- Running commands ---------------------------------------------------------------------

test("Enter runs the picked binding from the key press, then the palette closes", function(world)
    Open(world)
    equal(Picked(world, "spellb"), "interface.palette.commands.spellbook", "found by its binding's name")
    equal(OwnOverrides(world), 2, "Enter and the keypad's Enter run it")

    Enter(world)
    equal(Ran(world), "TOGGLESPELLBOOK", "the game ran the binding")
    expect(not IsOpen(world), "closed")
    equal(OwnOverrides(world), 0, "Enter back to its own binding")
end)

-- Measured: the release of a key the palette let through goes to the
-- bindings, never to the palette.
test("closes on the frame after Enter, its override going once Enter is up", function(world)
    Open(world)
    world:Type("spellb")
    world:KeyDown("ENTER")
    world:NextFrame()
    expect(not IsOpen(world), "closed while Enter is held")
    equal(OwnOverrides(world), 2, "the override waits for the release")
    world:NextFrame()
    equal(OwnOverrides(world), 2, "still held")

    world:KeyUp("ENTER")
    world:NextFrame()
    equal(OwnOverrides(world), 0, "released")
    equal(Ran(world), "TOGGLESPELLBOOK", "ran once")
end)

test("Up and Down pick, and wrap around", function(world)
    Open(world)
    local keys = Results(world)
    world:PressKey("DOWN")
    local _, picked = Results(world)
    equal(picked, keys[2], "down")
    world:PressKey("UP")
    world:PressKey("UP")
    _, picked = Results(world)
    equal(picked, keys[#keys], "up from the first: the last")
    world:PressKey("DOWN")
    _, picked = Results(world)
    equal(picked, keys[1], "down from the last: the first")

    Enter(world)
    equal(Ran(world), "TOGGLECHARACTER0", "ran the picked one")
end)

test("Enter with no result does nothing, and keeps the palette open", function(world)
    world:Bind("ENTER", "OPENCHAT")
    Open(world)
    world:Type("zzqqxx")
    equal(#Results(world), 0, "no results")
    Enter(world)
    equal(Ran(world), "", "chat not opened")
    expect(IsOpen(world), "still open")
end)

test("runs our own code from Enter, and a click of a named button", function(world)
    local palette = Palette(world)
    local ran, clicks = 0, 0
    world.ns:AddCommand(palette, {
        id = "testrun",
        run = function()
            ran = ran + 1
            expect(world.hardware > 0, "from the key press")
        end,
    })
    local button = CreateFrame("Button", "TestPaletteButton")
    button:RegisterForClicks("AnyUp") -- like the micro buttons
    button:SetScript("OnClick", function()
        clicks = clicks + 1
    end)
    world.ns:AddCommand(palette, { id = "testclick", click = "TestPaletteButton" })

    Open(world)
    equal(Picked(world, "testrun"), "interface.palette.commands.testrun", "found")
    equal(OwnOverrides(world), 0, "no override for our code")
    Enter(world)
    equal(ran, 1, "ran")
    expect(not IsOpen(world), "closed")

    world:PressKey(KEY)
    equal(Picked(world, "testclick"), "interface.palette.commands.testclick", "found")
    Enter(world)
    equal(clicks, 1, "clicked on the release")
    expect(not IsOpen(world), "closed")
end)

test("swaps layer from Enter, a key press", function(world)
    world:StandAt(482, 425)
    Open(world)
    equal(Picked(world, world.L["map.layers.swap"]), "map.layers.commands.swap", "found by its binding's name")
    Enter(world)
    equal(#world.whoQueries, 1, "searched")
end)

test("opens a profession's window by casting its spell from Enter", function(world)
    world.professions[5] = { skillLine = 185, spell = 2550, crafting = true }
    local cooking = C_Spell.GetSpellName(2550)
    Open(world)
    equal(Picked(world, cooking), "interface.palette.commands.cooking", "found by its spell's name")
    Reopen(world)
    equal(Picked(world, "food"), "interface.palette.commands.cooking", "and by an English keyword")
    Enter(world)
    equal(world.openedProfession, 185, "window opened")
    equal(table.concat(world.casts, ", "), cooking, "cast from the key press")
    expect(not IsOpen(world), "closed")
    equal(OwnOverrides(world), 0, "no override left")
end)

-- In Forever, Fishing has a crafting window too, opened by a camp spell: the
-- palette names the command like the profession window's tab, and casts the
-- spellbook item's spell by ID.
test("opens Fishing's window, named like its tab, without fishing", function(world)
    world.professions[4] = { skillLine = 356, spell = 1300000, spellName = "Appât appâteur", crafting = true }
    local fishing = GetProfessionInfo(4)
    local title
    for _, entry in ipairs(Palette(world).Search:GetEntries()) do
        if entry.key == "interface.palette.commands.fishing" then
            title = entry.title
        end
    end
    equal(title, fishing, "the profession's name, not its spell's")

    Open(world)
    equal(Picked(world, fishing:gsub("ê", "e")), "interface.palette.commands.fishing", "found by it, accents aside")
    Reopen(world)
    equal(Picked(world, "fish"), "interface.palette.commands.fishing", "and by an English keyword")
    Enter(world)
    equal(world.openedProfession, 356, "window opened")
    equal(world.channel, nil, "not fishing")
end)

-- Commands offered ---------------------------------------------------------------------

test("lists only the commands of active features and parts, when available", function(world)
    local choose = "combat.errors.commands.choose"
    expect(not Listed(world, choose), "feature off")
    world:Setting("combat.errors.enabled"):SetValue(true)
    expect(not Listed(world, choose), "Chosen spells only unchecked")
    world:Setting("combat.errors.spells"):SetValue(true)
    expect(Listed(world, choose), "listed")
end)

test("lists the guild and the pet spellbook only when there is one", function(world)
    expect(not Listed(world, "interface.palette.commands.guild"), "no guild")
    world.inGuild = true
    expect(Listed(world, "interface.palette.commands.guild"), "guild")

    expect(not Listed(world, "interface.palette.commands.petbook"), "no pet")
    world.petSpells = 4
    expect(Listed(world, "interface.palette.commands.petbook"), "pet")
end)

test("lists the player's professions with a crafting window", function(world)
    expect(not Listed(world, "interface.palette.commands.tailoring"), "not learned")
    world.professions[1] = { skillLine = 197, spell = 3908, crafting = true }
    world.professions[2] = { skillLine = 186, spell = 2575, crafting = false }
    expect(Listed(world, "interface.palette.commands.tailoring"), "learned")
    expect(not Listed(world, "interface.palette.commands.mining"), "no crafting window")

    expect(not Listed(world, "interface.palette.commands.poisons"), "no Poisons")
    world.playerSpells[2842] = true
    expect(Listed(world, "interface.palette.commands.poisons"), "a rogue's Poisons")
end)

test("a command needs exactly one action, and an id of its own", function(world)
    local ns, palette = world.ns, Palette(world)
    expect(not pcall(ns.AddCommand, ns, palette, { id = "none" }), "no action")
    expect(not pcall(ns.AddCommand, ns, palette, { id = "both", spell = 2550, run = print }), "two actions")
    expect(not pcall(ns.AddCommand, ns, palette, { id = "fps", binding = "TOGGLEFPS" }), "taken id")
end)
