-- Core: registry, saved variables, settings panel, lifecycle and locales.

local function Locking(world)
    return world.ns:GetFeature("inventory", "locking")
end

test("builds the settings panel from the registered schemas", function(world)
    local root, inventory = world.categories[1], world.categories[2]
    expect(root.registered, "root category registered as an AddOn category")
    equal(#world.categories, 2, "categories")
    equal(inventory.name, world.L["inventory.title"], "module subcategory name")

    local dropdown
    for _, initializer in ipairs(inventory.items) do
        if initializer.options then
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
