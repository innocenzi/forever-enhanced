-- Core: registry, saved variables, settings panel, lifecycle and locales.

local function Locking(world)
    return world.ns:GetFeature("inventory", "locking")
end

test("builds the settings panel from the registered schemas", function(world)
    local root, inventory = world.categories[1], world.categories[2]
    expect(root.registered, "root category registered as an AddOn category")
    equal(#world.categories, 4, "categories")
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

-- The quests page initializer bound to quests.nearby.<key>.
local function QuestsInitializer(world, key)
    local setting = world:Setting("quests.nearby." .. key)
    for _, initializer in ipairs(world.categories[3].items) do
        if initializer.setting == setting then
            return initializer
        end
    end
end

test("resets slider values outside their bounds", function(world)
    local db = world.env.ForeverEnhancedDB.modules.quests.features.nearby
    equal(db.count, 5, "slider default")
    db.count = 99
    world.ns.Database:Initialize()
    equal(db.count, 5, "out of range")
end)

test("labels slider values with the locale's format", function(world)
    local slider = QuestsInitializer(world, "range").slider
    equal(slider.minValue, 100, "min")
    equal(slider.formatter(500), world.L["quests.nearby.range.format"]:format(500), "value label")
    equal(QuestsInitializer(world, "count").slider.formatter(5), "5", "plain number without a format")
end)

test("a setting that requires another sits under it and greys out", function(world)
    local range = QuestsInitializer(world, "range")
    equal(range.parent, QuestsInitializer(world, "scope"), "parent")
    expect(not range.predicate(), "greyed out unless the scope is 'range'")
    world:Setting("quests.nearby.scope"):SetValue("range")
    expect(range.predicate(), "editable with the scope set to 'range'")
    world:Setting("quests.nearby.enabled"):SetValue(false)
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
    local items = world.categories[2].items
    local lastSetting = items[#items]
    expect(lastSetting.predicate(), "editable by default")
    world.env.ForeverEnhancedDB.modules.inventory.enabled = false
    expect(not lastSetting.predicate(), "greyed out with the module off")
end)

test("client locale wins over the fallback", function(world)
    local expected = world.env.TEST_LOCALE == "frFR" and "Activer" or "Enable"
    equal(world.L["core.enable"], expected, "core.enable")
    equal(world.L["missing.key"], "missing.key", "missing keys render as the key")
end)
