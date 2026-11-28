-- Settings pages (ns.PAGES): the subcategories of the Options > AddOns panel,
-- grouped by what the player is doing, so a feature is found where they would
-- look for it. A page is independent of the module a feature's code lives in:
-- each feature names its page in RegisterFeature (`page`), and its `order`
-- places it on that page. Saved variables and locale keys stay under the
-- feature's module, so moving a feature to another page needs no migration.
--
-- Strings: core.pages.<id>.

local _, ns = ...

-- In panel order.
ns.PAGES = {
    "bags",
    "bank",
    "trading",
    "quests",
    "map",
    "professions",
    "combat",
    "interface",
}
