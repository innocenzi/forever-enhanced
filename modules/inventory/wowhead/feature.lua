-- Wowhead link: "Wowhead link" in the item menu (Alt Right Click) shows the
-- item's Wowhead page address, ready to copy (off by default). It was a part of
-- Item marks, see core/database.lua.
--
-- Files of this slice:
--   feature.lua  registration and lifecycle (this file)
--   locales.lua  strings
--   link.lua     the dialog and the menu entry

local _, ns = ...

local Wowhead = ns:RegisterFeature("inventory", "wowhead", {
    page = "bags",
    order = 7,
    enabledByDefault = false,
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true },
    },
})

-- The click shield takes Alt clicks only while some feature adds menu entries.
function Wowhead:OnEnable()
    ns:RefreshItemButtons()
end

function Wowhead:OnDisable()
    self.Link:HideDialog()
    ns:RefreshItemButtons()
end
