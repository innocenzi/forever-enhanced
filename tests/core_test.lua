-- Core: registry, saved variables, settings panel, lifecycle and locales.

local function Locking(world)
    return world.ns:GetFeature("inventory", "locking")
end

test("builds the settings panel from the registered schemas", function(world)
    local root, inventory = world.categories[1], world.categories[2]
    expect(root.registered, "root category registered as an AddOn category")
    equal(#world.categories, 7, "categories")
    equal(inventory.name, world.L["inventory.title"], "module subcategory name")

    local dropdown -- Item Locking's indicator
    for _, initializer in ipairs(inventory.items) do
        if initializer.setting == world:Setting("inventory.locking.indicator") then
            dropdown = initializer
        end
    end
    expect(dropdown, "indicator dropdown exists")
    equal(#dropdown.options, 4, "dropdown options")
    equal(dropdown.options[2].label, world.L["inventory.locking.indicator.center"], "option label")
end)

-- Blizzard's pages reuse frames of its templates, which addon rows leave tainted.
test("settings rows use our own templates", function(world)
    for _, category in ipairs(world.categories) do
        for index, item in ipairs(category.items) do
            local where = category.name .. " row " .. index
            expect(item.template, where .. " has a template")
            expect(item.template:find("^ForeverEnhanced"), where .. " uses our template: " .. item.template)
        end
    end
end)

test("fills schema defaults", function(world)
    local db = world.env.ForeverEnhancedDB.modules.inventory
    equal(db.features.locking.enabled, true, "feature enabled by default")
    equal(world.env.ForeverEnhancedDB.modules.quests.features.announce.enabled, false, "unless it opts out")
    equal(world:Setting("quests.announce.enabled").default, false, "the panel's default too")
    equal(db.features.locking.indicator, "padlock", "dropdown default")
    equal(db.features.locking.keepInPlace, true, "toggle default")
end)

test("drops unknown keys and resets unknown options", function(world)
    local db = world.env.ForeverEnhancedDB.modules.inventory.features.locking
    db.stale = 1
    db.indicator = "removed-style"
    world.ns.Database:Initialize()
    equal(db.stale, nil, "unknown key")
    equal(db.indicator, "padlock", "unknown option")
end)

-- The quests page initializer bound to quests.helpers.<key>.
local function QuestsInitializer(world, key)
    local setting = world:Setting("quests.helpers." .. key)
    for _, initializer in ipairs(world.categories[3].items) do
        if initializer.setting == setting then
            return initializer
        end
    end
end

test("resets slider values outside their bounds", function(world)
    local db = world.env.ForeverEnhancedDB.modules.quests.features.helpers
    equal(db.count, 5, "slider default")
    db.count = 99
    world.ns.Database:Initialize()
    equal(db.count, 5, "out of range")
end)

test("labels slider values with the locale's format", function(world)
    local slider = QuestsInitializer(world, "range").slider
    equal(slider.minValue, 100, "min")
    equal(slider.formatter(500), world.L["quests.helpers.range.format"]:format(500), "value label")
    equal(QuestsInitializer(world, "count").slider.formatter(5), "5", "plain number without a format")
end)

test("a setting that requires another sits under it and greys out", function(world)
    world:Setting("quests.helpers.nearby"):SetValue(true)
    local range = QuestsInitializer(world, "range")
    equal(range:GetParentInitializer(), QuestsInitializer(world, "scope"), "parent")
    equal(range.parentInitializer, nil, "parent field the settings search reads left untouched")
    expect(not range.predicate(), "greyed out unless the scope is 'range'")
    world:Setting("quests.helpers.scope"):SetValue("range")
    expect(range.predicate(), "editable with the scope set to 'range'")
    world:Setting("quests.helpers.nearby"):SetValue(false)
    expect(not range.predicate(), "greyed out with the setting above its parent off")
    world:Setting("quests.helpers.nearby"):SetValue(true)
    world:Setting("quests.helpers.enabled"):SetValue(false)
    expect(not range.predicate(), "greyed out with the feature off")
end)

test("a text setting uses our text row and takes its default from the locale", function(world)
    local setting = world:Setting("quests.announce.template")
    local row
    for _, initializer in ipairs(world.categories[3].items) do
        if initializer.setting == setting then
            row = initializer
        end
    end
    expect(row, "text row registered on the quests page")
    equal(row.template, "ForeverEnhancedSettingsTextControlTemplate", "row template")
    equal(row.tooltip, world.L["quests.announce.template.tooltip"], "tooltip")
    expect(not row.predicate(), "greyed out with its feature off by default")
    world:Setting("quests.announce.enabled"):SetValue(true)
    expect(row.predicate(), "editable with its feature on")

    local default = world.L["quests.announce.template.default"]
    local db = world.env.ForeverEnhancedDB.modules.quests.features.announce
    equal(setting:GetDefaultValue(), default, "default")
    equal(db.template, default, "saved default")

    db.template = " "
    world.ns.Database:Initialize()
    equal(db.template, default, "blank text")
end)

test("activates features at login", function(world)
    expect(Locking(world):IsActive(), "locking is active")
end)

test("feature toggle runs the lifecycle", function(world)
    world:Setting("inventory.locking.enabled"):SetValue(false)
    expect(not Locking(world):IsActive(), "inactive after disabling")
    world:Setting("inventory.locking.enabled"):SetValue(true)
    expect(Locking(world):IsActive(), "active after enabling")
end)

test("the root page holds the general settings only", function(world)
    local root = world.categories[1]
    equal(#root.items, 3, "rows")
    equal(root.items[1].header, world.L["core.general"], "header")
    equal(root.items[2].setting, world:Setting("language"), "language")
    equal(root.items[3].setting, world:Setting("preset"), "preset")
end)

test("a feature without settings is one checkbox at the top of its page", function(world)
    local combat = world.categories[5]
    equal(combat.name, world.L["combat.title"], "page")

    local ranks = combat.items[1]
    equal(ranks.setting, world:Setting("combat.ranks.enabled"), "first row")
    equal(ranks.setting.name, world.L["combat.ranks.title"], "named after the feature")
    equal(ranks.tooltip, world.L["combat.ranks.description"], "its description as tooltip")
    equal(combat.items[2].setting, world:Setting("combat.combopoints.enabled"), "second row")
end)

test("a feature's action is a button beside its checkbox", function(world)
    local row, category = world:SettingsButton(world.L["combat.swaps.title"])
    equal(category.name, world.L["combat.title"], "on its module's page")
    equal(row.template, "ForeverEnhancedSettingsCheckboxWithButtonControlTemplate", "our checkbox with button row")
    expect(row.setting == world:Setting("combat.swaps.enabled"), "the feature's checkbox")
    equal(row.tooltip, world.L["combat.swaps.description"], "its description as tooltip")
    equal(row.data.buttonText, world.L["combat.swaps.edit"], "button text")
    expect(row.data.clickRequiresSet, "the button is usable only while checked")

    local swaps = world.ns:GetFeature("combat", "swaps")
    local clicked
    swaps.OnAction = function(_, key)
        clicked = key
    end
    row.data.OnButtonClick()
    equal(clicked, "edit", "calls OnAction with its key")
end)

test("settings of earlier versions are brought up to date", function(world)
    local modules = world.env.ForeverEnhancedDB.modules
    equal(modules.inventory.enabled, nil, "module toggles dropped")
    equal(modules.inventory.features.locking.enabled, false, "a module turned off turned its features off")
    expect(not Locking(world):IsActive(), "and they stay inactive")
    equal(modules.quests.features.helpers.enabled, true, "features of other modules kept")

    equal(modules.interface.features.swaps, nil, "moved features leave their old module")
    equal(modules.combat.features.swaps.enabled, true, "and keep their settings in the new one")
    equal(modules.interface.features.windows.modifier, "alt", "features that stayed keep theirs")
end, {
    savedVariables = function()
        return {
            modules = {
                inventory = { enabled = false, features = { locking = { enabled = true } } },
                quests = { enabled = true, features = { helpers = { enabled = true } } },
                interface = {
                    enabled = true,
                    features = { swaps = { enabled = true }, windows = { modifier = "alt" } },
                },
            },
        }
    end,
})

local ENABLE = { enUS = "Enable", frFR = "Activer" }

-- The supported locale the client isn't running.
local function OtherLocale(locale)
    return locale == "frFR" and "enUS" or "frFR"
end

test("follows the client language by default", function(world)
    equal(world.env.ForeverEnhancedDB.language, "auto", "saved default")
    equal(world.L["core.enable"], ENABLE[world.env.TEST_LOCALE], "core.enable")
    equal(world.L["missing.key"], "missing.key", "missing keys render as the key")
end)

test("a chosen language wins over the client's", function(world)
    local other = OtherLocale(world.env.TEST_LOCALE)
    equal(world.L["core.enable"], ENABLE[other], "core.enable")
    equal(world.categories[2].name, world.L["inventory.title"], "settings panel in that language")
    equal(world:Setting("language").tbl.language, other, "kept")
end, {
    savedVariables = function(locale)
        return { language = OtherLocale(locale) }
    end,
})

test("an unknown language resets to the client's", function(world)
    equal(world.env.ForeverEnhancedDB.language, "auto", "reset")
    equal(world.L["core.enable"], ENABLE[world.env.TEST_LOCALE], "core.enable")
end, {
    savedVariables = function()
        return { language = "deDE" }
    end,
})

test("the language dropdown opens the root page", function(world)
    local root = world.categories[1]
    local dropdown = root.items[2]
    equal(dropdown.setting, world:Setting("language"), "first setting")
    equal(dropdown.tooltip, world.L["core.language.tooltip"], "tooltip")
    equal(#dropdown.options, 3, "options")
    equal(dropdown.options[1].value, "auto", "client language first")
    equal(dropdown.options[1].label, world.L["core.language.auto"], "its label")
    equal(dropdown.options[2].label, "English", "named in its own language")
    equal(dropdown.options[3].label, "Français", "named in its own language")
end)

test("changing the language offers to reload", function(world)
    world:Setting("language"):SetValue(OtherLocale(world.env.TEST_LOCALE))
    local popup = world.popups[#world.popups]
    expect(popup, "confirmation shown")
    equal(popup.text, world.L["core.language.reloadConfirm"], "confirmation text")
    expect(not world.reloaded, "waits for the player")
    popup.callback()
    expect(world.reloaded, "reloads once accepted")
end)

test("a text setting left at its default follows the language", function(world)
    local db = world.env.ForeverEnhancedDB.modules.quests.features.announce
    local clientDefault = db.template
    world.env.ForeverEnhancedDB.language = OtherLocale(world.env.TEST_LOCALE)
    world.ns.Database:Initialize()
    expect(db.template ~= clientDefault, "no longer the client language's default")
    equal(db.template, world.L["quests.announce.template.default"], "the chosen language's default")

    db.template = "{quest} done"
    world.env.ForeverEnhancedDB.language = "auto"
    world.ns.Database:Initialize()
    equal(db.template, "{quest} done", "a custom text is kept")
end)

-- The root page's preset dropdown.
local function PresetDropdown(world)
    local setting = world:Setting("preset")
    for _, item in ipairs(world.categories[1].items) do
        if item.setting == setting then
            return item
        end
    end
end

-- Picks the preset and accepts the confirmation.
local function ApplyPreset(world, presetId)
    world:Setting("preset"):SetValue(presetId)
    world.popups[#world.popups].callback()
end

local function Feature(world, moduleId, id)
    return world.ns:GetFeature(moduleId, id)
end

test("the preset dropdown lists the presets after a placeholder", function(world)
    local dropdown = PresetDropdown(world)
    expect(dropdown, "dropdown on the root page")
    equal(dropdown.tooltip, world.L["core.presets.tooltip"], "tooltip")
    equal(#dropdown.options, 3, "options")
    equal(dropdown.options[1].value, "none", "placeholder first")
    equal(dropdown.options[1].label, world.L["core.presets.none"], "its label")
    equal(dropdown.options[2].value, "minimal", "presets in order")
    equal(dropdown.options[2].label, world.L["core.presets.minimal"], "preset label")
    equal(dropdown.options[3].tooltip, world.L["core.presets.enhanced.tooltip"], "preset tooltip")
end)

test("picking a preset asks first and keeps the placeholder", function(world)
    world:Setting("preset"):SetValue("enhanced")
    local popup = world.popups[#world.popups]
    expect(popup, "confirmation shown")
    equal(popup.text, world.L["core.presets.confirm"]:format(world.L["core.presets.enhanced"]), "text")
    equal(world:Setting("preset"):GetValue(), "none", "dropdown still shows its placeholder")
    expect(not Feature(world, "inventory", "merchant"):IsActive(), "waits for the player")

    popup.callback()
    expect(Feature(world, "inventory", "merchant"):IsActive(), "applied once accepted")

    local count = #world.popups
    world:Setting("preset"):SetValue("none")
    equal(#world.popups, count, "the placeholder asks nothing")
end)

test("the enhanced preset turns every feature on", function(world)
    world:Setting("interface.windows.enabled"):SetValue(false)
    ApplyPreset(world, "enhanced")

    for _, module in world.ns:EnumerateModules() do
        for _, feature in ipairs(module.sortedFeatures) do
            expect(feature:IsActive(), feature:GetLocaleKey() .. " active")
        end
    end
    local modules = world.env.ForeverEnhancedDB.modules
    equal(modules.inventory.features.bank.openWithBags, true, "bank opens with bags")
    equal(modules.quests.features.helpers.nearby, true, "nearby tracking")
end)

test("the minimal preset turns chatty features off and keeps what it doesn't list", function(world)
    ApplyPreset(world, "enhanced")
    world:Setting("interface.windows.modifier"):SetValue("alt")
    ApplyPreset(world, "minimal")

    expect(not Feature(world, "inventory", "merchant"):IsActive(), "merchant off")
    expect(not Feature(world, "quests", "announce"):IsActive(), "announcements off")
    expect(not Feature(world, "interface", "glow"):IsActive(), "glow off")
    expect(Feature(world, "inventory", "locking"):IsActive(), "locking on")

    local modules = world.env.ForeverEnhancedDB.modules
    equal(modules.quests.features.helpers.nearby, false, "nearby tracking off")
    equal(modules.inventory.features.locking.announce, false, "locking quiet")
    equal(modules.map.features.waypoint.announce, false, "waypoint quiet")
    equal(modules.interface.features.windows.modifier, "alt", "unlisted setting kept")
    equal(modules.inventory.features.bank.openWithBags, true, "unlisted setting kept")
end)

test("preset values are checked against the schemas", function(world)
    local presets = Feature(world, "inventory", "locking").presets
    local function Loads()
        return pcall(function()
            world.ns.Database:Initialize()
        end)
    end
    expect(Loads(), "the shipped presets are valid")

    presets.minimal.bogus = true
    expect(not Loads(), "unknown setting")
    presets.minimal.bogus = nil

    presets.minimal.indicator = "removed-style"
    expect(not Loads(), "value outside the options")
    presets.minimal.indicator = nil

    presets.minimal.enabled = "yes"
    expect(not Loads(), "wrong type")
    presets.minimal.enabled = true

    presets.custom = {}
    expect(not Loads(), "unknown preset")
end)

-- Chat messages look like the game's system messages, where the player shows them.
test("prints like a system message in the tabs that show them", function(world)
    world.ns:Print("Hello")
    local line = ChatFrame1.lines[#ChatFrame1.lines]
    equal(line.text, "Hello", "no prefix")
    equal(line.id, ChatTypeInfo.SYSTEM.id, "system chat type")
    equal(("%s %s %s"):format(line.r, line.g, line.b), "1 1 0", "system color")
    equal(#ChatFrame2.lines, 0, "combat log lines")

    ChatFrame1.messageTypeList = { "SAY" }
    ChatFrame2.messageTypeList = { "SYSTEM" }
    world.ns:Print("Moved")
    equal(ChatFrame1.lines[#ChatFrame1.lines].text, "Hello", "not in a tab without system messages")
    equal(ChatFrame2.lines[#ChatFrame2.lines].text, "Moved", "in the tab with system messages")

    ChatFrame2.messageTypeList = {}
    world.ns:Print("Nowhere")
    equal(ChatFrame1.lines[#ChatFrame1.lines].text, "Nowhere", "main tab when no tab shows them")
end)
