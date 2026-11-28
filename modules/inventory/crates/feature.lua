-- Waylaid crates: Forever's Waylaid Crates list the bundles that fill them in
-- their Use text ("- 20 Wool Cloth", one per line). Each of those lines gets a
-- mark: the ready check when the bags hold enough, the banker icon when the
-- bags and this character's saved bank (Bank feature) do, a question mark
-- otherwise. Components are known by item ID (data.lua), the same in every
-- client language.
--
-- Files of this slice:
--   feature.lua  registration (this file)
--   locales.lua  strings
--   data.lua     generated: crate item ID -> { itemID, count } components
--   tooltip.lua  the marks in item tooltips

local _, ns = ...

ns:RegisterFeature("inventory", "crates", {
    page = "bags",
    order = 6,
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true },
    },
})
