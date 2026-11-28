-- Core: registry, saved variables, settings panel, lifecycle and locales.

local function Locking(world)
    return world.ns:GetFeature("inventory", "locking")
end

test("builds the settings panel from the registered schemas", function(world)
    local root, bags = world.categories[1], world.categories[2]
    expect(root.registered, "root category registered as an AddOn category")
    equal(#world.categories, 1 + #world.ns.PAGES, "categories")
    equal(bags.name, world.L["core.pages.bags"], "page subcategory name")

    local dropdown -- Item Locking's indicator
    for _, initializer in ipairs(bags.items) do
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

test("drops unknown keys and resets unknown options and out-of-range slider values", function(world)
    local db = world.env.ForeverEnhancedDB.modules.inventory.features.locking
    local tracking = world.env.ForeverEnhancedDB.modules.quests.features.tracking
    db.stale = 1
    db.indicator = "removed-style"
    equal(tracking.count, 5, "slider default")
    tracking.count = 99
    world.ns.Database:Initialize()
    equal(db.stale, nil, "unknown key")
    equal(db.indicator, "padlock", "unknown option")
    equal(tracking.count, 5, "out of range")
end)

-- The panel's subcategory of `page`, and the features shown on it (their
-- Enable checkboxes), by locale key.
local function Page(world, page)
    local features = {}
    for _, module in world.ns:EnumerateModules() do
        for _, feature in ipairs(module.sortedFeatures) do
            features[world:Setting(feature:GetLocaleKey("enabled"))] = feature:GetLocaleKey()
        end
    end
    for _, category in ipairs(world.categories) do
        if category.name == world.L["core.pages." .. page] then
            local shown = {}
            for _, item in ipairs(category.items) do
                if item.setting and features[item.setting] then
                    table.insert(shown, features[item.setting])
                end
            end
            return category, shown
        end
    end
end

-- The quests page initializer bound to quests.tracking.<key>.
local function QuestsInitializer(world, key)
    local setting = world:Setting("quests.tracking." .. key)
    for _, initializer in ipairs(Page(world, "quests").items) do
        if initializer.setting == setting then
            return initializer
        end
    end
end

test("labels slider values with the locale's format", function(world)
    local slider = QuestsInitializer(world, "range").slider
    equal(slider.minValue, 100, "min")
    equal(slider.formatter(500), world.L["quests.tracking.range.format"]:format(500), "value label")
    equal(QuestsInitializer(world, "count").slider.formatter(5), "5", "plain number without a format")
end)

test("a setting that requires another sits under it and greys out", function(world)
    world:Setting("quests.tracking.enabled"):SetValue(true)
    local range = QuestsInitializer(world, "range")
    equal(range:GetParentInitializer(), QuestsInitializer(world, "scope"), "parent")
    equal(range.parentInitializer, nil, "parent field the settings search reads left untouched")
    equal(QuestsInitializer(world, "scope"):GetIndent(), 15, "settings one step in")
    equal(range:GetIndent(), 30, "nested settings one step further")
    expect(not range.predicate(), "greyed out unless the scope is 'range'")
    world:Setting("quests.tracking.scope"):SetValue("range")
    expect(range.predicate(), "editable with the scope set to 'range'")
    world:Setting("quests.tracking.enabled"):SetValue(false)
    expect(not range.predicate(), "greyed out with the feature off")
end)

-- The row of a setting, on whichever page.
local function Row(world, path)
    local setting = world:Setting(path)
    for _, category in ipairs(world.categories) do
        for _, initializer in ipairs(category.items) do
            if initializer.setting == setting then
                return initializer
            end
        end
    end
end

test("a setting that needs another feature greys out without it, saying what it needs", function(world)
    local row = assert(Row(world, "inventory.transfers.autoDeposit"), "row")
    expect(row.predicate(), "editable with Item marks' Bank on")
    world:Setting("inventory.marks.bank"):SetValue(false)
    expect(not row.predicate(), "greyed out with the bank mark off")
    world:Setting("inventory.marks.bank"):SetValue(true)
    world:Setting("inventory.marks.enabled"):SetValue(false)
    expect(not row.predicate(), "greyed out with Item marks off")
    world:Setting("inventory.marks.enabled"):SetValue(true)
    world:Setting("inventory.transfers.enabled"):SetValue(false)
    expect(not row.predicate(), "greyed out with its own feature off")

    local hint = world.L["core.needsSetting"]:format(world.L["inventory.marks.bank"], world.L["inventory.marks.title"])
    equal(
        row.tooltip,
        world.L["inventory.transfers.autoDeposit.tooltip"] .. "\n\n" .. hint,
        "tooltip ends with the hint"
    )
    local followed = table.concat(row.evaluateStateCVars, " ")
    equal(followed, "ForeverEnhanced.inventory.marks.enabled ForeverEnhanced.inventory.marks.bank", "follows them")
    equal(Row(world, "inventory.transfers.autoRefill").evaluateStateCVars, nil, "rows without needs follow nothing")
end)

test("a text setting uses our text row and takes its default from the locale", function(world)
    local setting = world:Setting("quests.announce.template")
    local row
    for _, initializer in ipairs(Page(world, "quests").items) do
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

test("every page shows the features that name it, whatever their module", function(world)
    for index, page in ipairs(world.ns.PAGES) do
        local category, features = Page(world, page)
        equal(world.categories[index + 1], category, page .. " in panel order")
        expect(#features > 0, page .. " shows features")
    end

    local _, combat = Page(world, "combat")
    expect(tContains(combat, "inventory.food"), "a feature shows on its page, not its module's")
    local _, professions = Page(world, "professions")
    expect(tContains(professions, "interface.glow"), "the nearest object's glow with the professions")

    local shown = 0
    for _, page in ipairs(world.ns.PAGES) do
        shown = shown + #select(2, Page(world, page))
    end
    local registered = 0
    for _, module in world.ns:EnumerateModules() do
        registered = registered + #module.sortedFeatures
    end
    equal(shown, registered, "every feature on exactly one page")
end)

test("a feature names a known page and a free place on it", function(world)
    local ok, message = pcall(world.ns.RegisterFeature, world.ns, "combat", "unknown", { page = "nowhere", order = 1 })
    expect(not ok and message:find("unknown page"), "unknown page refused")
    ok, message = pcall(world.ns.RegisterFeature, world.ns, "combat", "taken", { page = "combat", order = 1 })
    expect(not ok and message:find("order already taken"), "taken order refused")
end)

test("a feature without settings is one checkbox at the top of its page", function(world)
    local combat = Page(world, "combat")
    expect(combat, "page")

    local ranks = combat.items[1]
    equal(ranks.setting, world:Setting("combat.ranks.enabled"), "first row")
    equal(ranks.setting.name, world.L["combat.ranks.title"], "named after the feature")
    equal(ranks.tooltip, world.L["combat.ranks.description"], "its description as tooltip")
    equal(combat.items[2].setting, world:Setting("combat.combopoints.enabled"), "second row")
end)

test("a feature's action is a button beside its checkbox", function(world)
    local row, category = world:SettingsButton(world.L["combat.swaps.title"])
    equal(category.name, world.L["core.pages.combat"], "on its page")
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

    equal(modules.quests.features.announce.hideQuestie, nil, "moved settings leave their old feature")
    equal(modules.quests.features.helpers.hideAnnouncements, true, "and stay on where they were in effect")
end, {
    savedVariables = function()
        return {
            modules = {
                inventory = { enabled = false, features = { locking = { enabled = true } } },
                quests = {
                    enabled = true,
                    features = {
                        helpers = { enabled = true },
                        announce = { enabled = true, hideQuestie = true },
                    },
                },
                interface = {
                    enabled = true,
                    features = { swaps = { enabled = true }, windows = { modifier = "alt" } },
                },
            },
        }
    end,
})

test("a moved feature's saved data follows it", function(world)
    local character = world.env.ForeverEnhancedCharacterDB
    equal(character.interface.swaps, nil, "character data leaves the old module")
    equal(character.combat.swaps.marker, "character", "and is in the new one")
    local stores = world.env.ForeverEnhancedDB.stores
    equal(stores.interface.ranks, nil, "account data leaves the old module")
    equal(stores.combat.ranks.marker, "account", "and is in the new one")
end, {
    savedVariables = function()
        return { stores = { interface = { ranks = { marker = "account" } } } }
    end,
    characterSavedVariables = function()
        return { interface = { swaps = { marker = "character" } } }
    end,
})

test("nearby quest tracking moves to its own feature with its settings and pins", function(world)
    local quests = world.env.ForeverEnhancedDB.modules.quests.features
    equal(quests.helpers.nearby, nil, "part toggle dropped")
    equal(quests.helpers.count, nil, "settings leave Quest helpers")
    equal(quests.tracking.enabled, true, "on where it was in effect")
    equal(quests.tracking.count, 8, "settings kept")
    equal(quests.tracking.keepManual, true, "toggles kept")
    equal(quests.tracking.scope, "anywhere", "the closest scope became anywhere")
    expect(world.ns:GetFeature("quests", "tracking"):IsActive(), "and in effect")
    local character = world.env.ForeverEnhancedCharacterDB.quests
    equal(character.helpers.pins, nil, "pins leave Quest helpers")
    expect(character.tracking.pins[42], "and follow the feature")
end, {
    savedVariables = function()
        return {
            modules = {
                quests = {
                    features = {
                        helpers = { enabled = true, nearby = true, count = 8, keepManual = true, scope = "closest" },
                    },
                },
            },
        }
    end,
    characterSavedVariables = function()
        return { quests = { helpers = { pins = { [42] = true } } } }
    end,
})

test("nearby quest tracking stays off where Quest helpers was off", function(world)
    local quests = world.env.ForeverEnhancedDB.modules.quests.features
    equal(quests.tracking.enabled, false, "off")
    equal(quests.tracking.scope, "zone", "settings kept")
end, {
    savedVariables = function()
        return {
            modules = { quests = { features = { helpers = { enabled = false, nearby = true, scope = "zone" } } } },
        }
    end,
})

test("two-option dropdowns carry over to their toggles", function(world)
    local modules = world.env.ForeverEnhancedDB.modules
    equal(modules.inventory.features.merchant.repairFunds, nil, "old repair key dropped")
    equal(modules.inventory.features.merchant.guildFunds, true, "guild funds first")
    equal(modules.professions.features.reagents.professions, nil, "old reagents key dropped")
    equal(modules.professions.features.reagents.onlyMine, true, "only the player's professions")
end, {
    savedVariables = function()
        return {
            modules = {
                inventory = { features = { merchant = { repairFunds = "guild" } } },
                professions = { features = { reagents = { professions = "mine" } } },
            },
        }
    end,
})

test("the bank's parts carry over to Saved bank and the transfer buttons", function(world)
    local features = world.env.ForeverEnhancedDB.modules.inventory.features
    equal(features.bank.savedBank, nil, "saved bank toggle dropped")
    equal(features.bank.transfers, nil, "transfers toggle dropped")
    equal(features.bank.autoRefill, nil, "transfer settings left the saved bank")
    equal(features.bank.openWithBags, true, "saved bank settings kept")
    equal(features.bank.reagentMark, "icon", "dropdown kept")
    equal(features.transfers.enabled, false, "transfers off, as its part was")
    equal(features.transfers.autoRefill, true, "refill followed")
    equal(features.transfers.autoSort, true, "sort followed")
    expect(world.ns:GetFeature("inventory", "bank"):IsActive(), "saved bank on")
    local alt = world.ns:GetFeature("inventory", "bank").Store:Get("alt-guid")
    equal(alt and alt.name, "Zed", "saved banks still readable")
end, {
    savedVariables = function()
        return {
            modules = {
                inventory = {
                    features = {
                        bank = {
                            enabled = true,
                            savedBank = true,
                            openWithBags = true,
                            reagentMark = "icon",
                            transfers = false,
                            autoRefill = true,
                            autoSort = true,
                        },
                    },
                },
            },
            stores = { inventory = { bank = { characters = { ["alt-guid"] = { name = "Zed", tabs = {} } } } } },
        }
    end,
})

test("a saved bank part that was off turns Saved bank off", function(world)
    local features = world.env.ForeverEnhancedDB.modules.inventory.features
    equal(features.bank.enabled, false, "saved bank off")
    equal(features.transfers.enabled, true, "transfers on")
    equal(features.transfers.autoDeposit, true, "deposit followed")
end, {
    savedVariables = function()
        return {
            modules = {
                inventory = {
                    features = { bank = { savedBank = false, transfers = true, autoDeposit = true } },
                },
            },
        }
    end,
})

test("a bank that was off turns both bank features off", function(world)
    local features = world.env.ForeverEnhancedDB.modules.inventory.features
    equal(features.bank.enabled, false, "saved bank off")
    equal(features.transfers.enabled, false, "transfers off")
end, {
    savedVariables = function()
        return {
            modules = {
                inventory = { features = { bank = { enabled = false, savedBank = true, transfers = true } } },
            },
        }
    end,
})

test("the Wowhead link leaves Item marks for a feature of its own", function(world)
    local features = world.env.ForeverEnhancedDB.modules.inventory.features
    equal(features.marks.wowhead, nil, "left Item marks")
    equal(features.wowhead.enabled, true, "on, as it was")
    expect(world.ns:GetFeature("inventory", "wowhead"):IsActive(), "active")
end, {
    savedVariables = function()
        return {
            modules = { inventory = { features = { marks = { enabled = true, wowhead = true } } } },
        }
    end,
})

test("a Wowhead link that had no effect stays off", function(world)
    local features = world.env.ForeverEnhancedDB.modules.inventory.features
    equal(features.wowhead.enabled, false, "Item marks was off")
end, {
    savedVariables = function()
        return {
            modules = { inventory = { features = { marks = { enabled = false, wowhead = true } } } },
        }
    end,
})

test("the Wowhead link is a checkbox at the top of the Bags page, off by default", function(world)
    local bags = Page(world, "bags")
    local found = false
    for _, item in ipairs(bags.items) do
        if item.setting == world:Setting("inventory.wowhead.enabled") then
            found = true
            equal(item.setting.name, world.L["inventory.wowhead.title"], "named after the feature")
            break
        end
        expect(not item.header, "before the first section")
    end
    expect(found, "on the Bags page")
    expect(not world.ns:GetFeature("inventory", "wowhead"):IsActive(), "off by default")
end)

test("a moved setting that had no effect stays off", function(world)
    local quests = world.env.ForeverEnhancedDB.modules.quests.features
    equal(quests.announce.hideQuestie, nil, "left its old feature")
    equal(quests.helpers.hideAnnouncements, false, "off in the new one")
end, {
    savedVariables = function()
        return {
            modules = { quests = { features = { announce = { enabled = false, hideQuestie = true } } } },
        }
    end,
})

test("hiding Questie announcements carries over to hiding quest addon announcements", function(world)
    local helpers = world.env.ForeverEnhancedDB.modules.quests.features.helpers
    equal(helpers.hideQuestie, nil, "old key dropped")
    equal(helpers.hideAnnouncements, true, "kept on")
    expect(world.ns:GetFeature("quests", "helpers"):IsPartActive("hideAnnouncements"), "and in effect")
end, {
    savedVariables = function()
        return {
            modules = { quests = { features = { helpers = { enabled = true, hideQuestie = true } } } },
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
    equal(world.categories[2].name, world.L["core.pages.bags"], "settings panel in that language")
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

local function Feature(world, moduleId, id)
    return world.ns:GetFeature(moduleId, id)
end

-- The Quick setup row `rowId`: its definition, setting and dropdown.
local function QuickRow(world, rowId)
    local row = world.ns.QuickSetup:GetRow(rowId)
    local setting = world:Setting("quickSetup." .. rowId)
    for _, item in ipairs(world.categories[1].items) do
        if item.setting == setting then
            return row, setting, item
        end
    end
end

-- The dropdown's options as it opens now: their values in order.
local function OptionValues(dropdown)
    local values = {}
    for _, option in ipairs(dropdown.getOptions()) do
        table.insert(values, option.value)
    end
    return table.concat(values, " ")
end

test("the root page shows the language, then the Quick setup rows", function(world)
    local root = world.categories[1]
    local rows = world.ns.QuickSetup.ROWS
    equal(#root.items, 3 + #rows, "rows")
    equal(root.items[1].header, world.L["core.general"], "header")
    equal(root.items[2].setting, world:Setting("language"), "language")
    equal(root.items[3].header, world.L["core.quickSetup"], "Quick setup header")
    equal(root.items[3].tooltip, world.L["core.quickSetup.tooltip"], "its tooltip")
    for index, row in ipairs(rows) do
        local item = root.items[3 + index]
        equal(item.setting, world:Setting("quickSetup." .. row.id), row.id .. " in order")
        equal(item.setting.name, world.L["core.quickSetup." .. row.id], row.id .. " label")
        equal(item.template, "ForeverEnhancedSettingsDropdownControlTemplate", row.id .. " our dropdown")
    end

    local language = root.items[2]
    equal(language.tooltip, world.L["core.language.tooltip"], "language tooltip")
    equal(#language.options, 3, "language options")
    equal(language.options[1].value, "auto", "client language first")
    equal(language.options[1].label, world.L["core.language.auto"], "its label")
    equal(language.options[2].label, "English", "named in its own language")
    equal(language.options[3].label, "Français", "named in its own language")
end)

test("a fresh install shows each row's default answer, with no Custom", function(world)
    local QuickSetup = world.ns.QuickSetup
    for _, row in ipairs(QuickSetup.ROWS) do
        local _, setting, dropdown = QuickRow(world, row.id)
        equal(setting:GetValue(), QuickSetup:GetDefaultAnswer(row), row.id)
        equal(setting:GetDefaultValue(), QuickSetup:GetDefaultAnswer(row), row.id .. " default")
        equal(#dropdown.getOptions(), #row.answers, row.id .. " lists its answers only")
    end
end)

test("an answer's tooltip says what it does, then what it turns on", function(world)
    local _, _, dropdown = QuickRow(world, "merchant")
    local both = dropdown.options[3]
    equal(both.value, "both", "answers in order")
    equal(both.label, world.L["core.quickSetup.merchant.both"], "label")
    local expected = table.concat({
        world.L["core.quickSetup.merchant.both.tooltip"],
        "",
        GREEN_FONT_COLOR:WrapTextInColorCode(world.L["inventory.merchant.autoSellJunk"]),
        GREEN_FONT_COLOR:WrapTextInColorCode(world.L["inventory.merchant.autoRepair"]),
    }, "\n")
    equal(both.tooltip, expected, "tooltip")
    equal(dropdown.options[1].tooltip, world.L["core.quickSetup.merchant.none.tooltip"], "nothing turned on")

    local _, _, tracker = QuickRow(world, "tracker")
    expect(
        tracker.options[2].tooltip:find(world.L["quests.tracking.title"], 1, true),
        "a feature turned on is named by its title"
    )
end)

test("picking any answer makes its row show it, and only it", function(world)
    local QuickSetup = world.ns.QuickSetup
    for _, row in ipairs(QuickSetup.ROWS) do
        local _, setting = QuickRow(world, row.id)
        for _, answer in ipairs(row.answers) do
            for _, other in ipairs(row.answers) do
                setting:SetValue(other.id)
                setting:SetValue(answer.id)
                local matching = QuickSetup:GetMatchingAnswers(row)
                equal(table.concat(matching, " "), answer.id, row.id .. ": " .. answer.id .. " after " .. other.id)
            end
        end
    end
end)

test("picking an answer sets its options through the settings", function(world)
    local _, setting = QuickRow(world, "merchant")
    setting:SetValue("both")
    equal(world:Setting("inventory.merchant.autoSellJunk"):GetValue(), true, "auto sell junk")
    equal(world:Setting("inventory.merchant.autoRepair"):GetValue(), true, "auto repair")
    setting:SetValue("sell")
    equal(world:Setting("inventory.merchant.autoRepair"):GetValue(), false, "auto repair off again")

    local _, bars = QuickRow(world, "bars")
    bars:SetValue("food")
    expect(Feature(world, "inventory", "food"):IsActive(), "food on action bars on")
    expect(Feature(world, "combat", "ranks"):IsActive(), "rank upgrades kept")
    bars:SetValue("none")
    expect(not Feature(world, "combat", "ranks"):IsActive(), "rank upgrades off")

    local _, tracker = QuickRow(world, "tracker")
    tracker:SetValue("nearby")
    expect(Feature(world, "quests", "tracking"):IsActive(), "nearby tracking on")
    equal(world:Setting("quests.tracking.keepManual"):GetValue(), true, "keeps quests tracked by hand")

    local _, errors = QuickRow(world, "errors")
    errors:SetValue("combat")
    expect(Feature(world, "combat", "errors"):IsActive(), "errors hidden")
    equal(world:Setting("combat.errors.combat"):GetValue(), true, "only in combat")
    errors:SetValue("always")
    equal(world:Setting("combat.errors.combat"):GetValue(), false, "all the time")
end)

test("an answer that needs its feature turns it on", function(world)
    world:Setting("inventory.merchant.enabled"):SetValue(false)
    world:Setting("quests.helpers.enabled"):SetValue(false)

    local _, merchant = QuickRow(world, "merchant")
    equal(merchant:GetValue(), "none", "nothing sold while the merchant feature is off")
    merchant:SetValue("sell")
    expect(Feature(world, "inventory", "merchant"):IsActive(), "merchant feature on")
    equal(world:Setting("inventory.merchant.autoSellJunk"):GetValue(), true, "auto sell junk")

    local _, questie = QuickRow(world, "questie")
    questie:SetValue("hide")
    expect(Feature(world, "quests", "helpers"):IsPartActive("hideAnnouncements"), "announcements hidden")
end)

test("a row reads what is in effect, not what is saved", function(world)
    local _, merchant = QuickRow(world, "merchant")
    merchant:SetValue("both")
    world:Setting("inventory.merchant.enabled"):SetValue(false)
    equal(merchant:GetValue(), "none", "auto selling saved but off with its feature")

    world:Setting("inventory.merchant.enabled"):SetValue(true)
    equal(merchant:GetValue(), "both", "back on with it")
end)

test("a row matching none of its answers shows Custom", function(world)
    local row, merchant, dropdown = QuickRow(world, "merchant")
    world:Setting("inventory.merchant.autoRepair"):SetValue(true)
    equal(merchant:GetValue(), "custom", "repair without selling")
    equal(OptionValues(dropdown), "none sell both custom", "Custom listed after the answers")

    local custom = dropdown.getOptions()[4]
    equal(custom.label, world.L["core.quickSetup.custom"], "label")
    local page = world.L["core.pages." .. world.ns.QuickSetup:GetPage(row).id]
    local expected = table.concat({
        world.L["core.quickSetup.custom.tooltip"]:format(page),
        "",
        GRAY_FONT_COLOR:WrapTextInColorCode(world.L["inventory.merchant.autoSellJunk"]),
        GREEN_FONT_COLOR:WrapTextInColorCode(world.L["inventory.merchant.autoRepair"]),
    }, "\n")
    equal(custom.tooltip, expected, "where the options are, and which are on")

    merchant:SetValue("custom")
    equal(world:Setting("inventory.merchant.autoRepair"):GetValue(), true, "picking Custom changes nothing")

    merchant:SetValue("none")
    equal(OptionValues(dropdown), "none sell both", "Custom gone once an answer matches")
end)

test("a setting an answer leaves out doesn't count", function(world)
    local _, bars = QuickRow(world, "bars")
    bars:SetValue("food")
    world:Setting("inventory.food.buffFood"):SetValue(true)
    equal(bars:GetValue(), "food", "buff food isn't the row's")

    world:Setting("inventory.food.pick"):SetValue("cheapest")
    equal(bars:GetValue(), "custom", "the cheapest food isn't the best")
end)

test("Quick setup rows are checked against the schemas at load", function(world)
    local QuickSetup = world.ns.QuickSetup
    local values = QuickSetup:GetRow("merchant").answers[2].values
    local function Loads()
        return pcall(function()
            world.ns.Database:Initialize()
        end)
    end
    expect(Loads(), "the shipped rows are valid")

    table.insert(values, { "inventory.merchant.bogus", true })
    expect(not Loads(), "unknown setting")
    values[#values] = { "inventory.food.pick", "removed-style" }
    expect(not Loads(), "value outside the options")
    values[#values] = { "inventory.merchant.enabled", "yes" }
    expect(not Loads(), "wrong type")
    values[#values] = { "combat.ranks.enabled", true }
    expect(not Loads(), "a path of another row")
    values[#values] = { "map.pin.enabled", true }
    expect(not Loads(), "a feature of another page")
    table.remove(values)
    expect(Loads(), "valid again")
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

-- Each swap costs the client a few milliseconds, so a round's swaps go out a few per frame.
test("sends a round's moves a few per frame", function(world)
    world.bagSizes[0] = 10
    world.bags[0] = { "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10" }
    local planned = false
    local mover = world.ns:CreateMover({
        maxMovesPerKey = 1,
        Plan = function()
            if planned then
                return {}
            end
            planned = true
            local moves = {}
            for pair = 1, 5 do
                local from, to = 2 * pair - 1, 2 * pair
                table.insert(moves, { from = { bagID = 0, slot = from }, to = { bagID = 0, slot = to }, key = pair })
            end
            return moves
        end,
    })
    local pickupsPerFrame = {}
    local NextFrame = world.NextFrame
    function world:NextFrame(...)
        table.insert(pickupsPerFrame, self.pickups)
        return NextFrame(self, ...)
    end
    world.pickups = 0
    mover:Start()
    world:Elapse(5)
    equal(table.concat(world.bags[0], " "), "A2 A1 A4 A3 A6 A5 A8 A7 A10 A9", "bag")
    equal(pickupsPerFrame[1], 8, "pickups after the first frame (four swaps)")
    equal(pickupsPerFrame[2], 10, "pickups after the second frame")
    expect(not mover:IsRunning(), "run ended")
end)

-- A multiselect: Lowest value items' "ignore", its options all checked by default.
local IGNORE = "inventory.cheapest.ignore"

local function IgnoreRow(world)
    for _, initializer in ipairs(world.categories[2].items) do
        if initializer.setting == world:Setting(IGNORE) then
            return initializer
        end
    end
end

test("a multiselect is a dropdown of checkboxes over the saved selection", function(world)
    local row = IgnoreRow(world)
    expect(row, "a row on the Bags page")
    equal(row.template, "ForeverEnhancedSettingsDropdownControlTemplate", "our dropdown row")
    equal(#row.options, 8, "options")
    expect(row.options[1].checkbox, "checkboxes")
    equal(row.options[1].label, world.L[IGNORE .. ".food"], "option label")
    equal(row.options[1].tooltip, world.L[IGNORE .. ".food.tooltip"], "option tooltip")
    expect(row.options[1].displayCheckboxTooltip, "option tooltip shown in the menu")
    equal(row.getSelectionTextFunc({}), NONE, "nothing checked reads None")
    equal(row.getSelectionTextFunc({ {} }), nil, "otherwise Blizzard's list of labels")

    local db = Feature(world, "inventory", "cheapest").db
    equal(world:Setting(IGNORE):GetValue(), 255, "every option checked by default")
    world:CheckSettingOption(IGNORE, world.L[IGNORE .. ".tools"], false)
    equal(db.ignore.tools, false, "unchecked")
    equal(db.ignore.food, true, "the others kept")
    equal(world:Setting(IGNORE):GetValue(), 251, "its bit cleared")
end)

test("a saved selection fills missing options and drops unknown ones", function(world)
    local features = world.env.ForeverEnhancedDB.modules.inventory.features
    features.cheapest.ignore = { food = false, tools = "yes", removed = true }
    world.ns.Database:Initialize()
    local ignore = features.cheapest.ignore
    equal(ignore.food, false, "kept")
    equal(ignore.tools, true, "mistyped: its default")
    equal(ignore.notes, true, "missing: its default")
    equal(ignore.removed, nil, "unknown option dropped")

    features.cheapest.ignore = "food"
    world.ns.Database:Initialize()
    equal(features.cheapest.ignore.food, true, "not a table: the default")
end)

test("setting a multiselect from code sets its whole selection", function(world)
    local Cheapest = Feature(world, "inventory", "cheapest")
    world.ns.SettingsPanel:SetValue(IGNORE, { food = true })
    equal(Cheapest.db.ignore.food, true, "listed")
    equal(Cheapest.db.ignore.tools, false, "left out: unchecked")
    equal(world:Setting(IGNORE):GetValue(), 1, "its mask")
end)
