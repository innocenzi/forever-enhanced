-- Junk marking: "Mark as junk" in the item menu (Alt Right Click) marks an
-- item, by item ID, so every copy of it is junk: Sell All Junk Items and the
-- merchant's auto selling sell it (locked copies are kept), and it shows the
-- junk coin.
--
-- Files of this slice:
--   feature.lua  registration and lifecycle (this file)
--   locales.lua  strings
--   store.lua    marked item IDs and public API
--   buttons.lua  junk coin and the item menu entry
--   selling.lua  adds marked items to the junk Sell All Junk sells

local _, ns = ...

local Junk = ns:RegisterFeature("inventory", "junk", {
    order = 4,
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true },
    },
})

function Junk:OnEnable()
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end

function Junk:OnDisable()
    self.Buttons:HideAll()
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end
