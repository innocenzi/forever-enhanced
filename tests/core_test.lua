-- Core: registry, saved variables, settings panel, lifecycle and locales.

local function Locking(world)
    return world.ns:GetFeature("inventory", "locking")
end

test("builds the settings panel from the registered schemas", function(world)
    local root, inventory = world.categories[1], world.categories[2]
    expect(root.registered, "root category registered as an AddOn category")
    equal(#world.categories, 5, "categories")
    equal(inventory.name, world.L["inventory.title"], "module subcategory name")

    local dropdown -- the first one: Item Locking's indicator
    for _, initializer in ipairs(inventory.items) do
        if initializer.options and not dropdown then
            dropdown = initializer
        end
    end
    expect(dropdown, "indicator dropdown exists")
    equal(#dropdown.options, 4, "dropdown options")
    equal(dropdown.options[2].label, world.L["inventory.locking.indicator.center"], "option label")
end)

test("fills schema defaults", function(world)
    local db = world.env.ForeverEnhancedDB.modules.inventory
    equal(db.enabled, true, "module enabled by default")
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
    equal(range.parent, QuestsInitializer(world, "scope"), "parent")
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

test("module toggle runs the lifecycle of its features", function(world)
    world:Setting("inventory.enabled"):SetValue(false)
    expect(not Locking(world):IsActive(), "inactive with the module off")
    world:Setting("inventory.enabled"):SetValue(true)
    expect(Locking(world):IsActive(), "active with the module back on")
end)

test("feature settings grey out with their module", function(world)
    local announce = world:Setting("inventory.locking.announce")
    local row
    for _, item in ipairs(world.categories[2].items) do
        if item.setting == announce then
            row = item
        end
    end
    expect(row.predicate(), "editable by default")
    world.env.ForeverEnhancedDB.modules.inventory.enabled = false
    expect(not row.predicate(), "greyed out with the module off")
end)

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
