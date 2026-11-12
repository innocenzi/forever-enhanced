-- Item Locking: Alt Left Click (unless Item marks gives it to a mark) or "Lock"
-- in the item menu (Alt Right Click) locks that exact bag or bank item (by
-- GUID). A locked item can't be picked up, right-click is blocked wherever it
-- would sell, mail, trade or auction the item, Sell All Junk keeps it, and
-- sorting leaves it in place. "Add note" in the item menu writes a note on the
-- item.
--
-- Files of this slice:
--   feature.lua     registration, schema and lifecycle (this file)
--   locales.lua     strings
--   store.lua       lock set, notes and public API
--   notes.lua       note popup
--   indicators.lua  lock indicator styles drawn on item buttons
--   buttons.lua     item buttons: indicators, Alt clicks, menu entry, click shield
--   guards.lua      cursor guard
--   junk.lua        Sell All Junk keeps locked items
--   sorting.lua     puts locked items back after a sort
--   tooltip.lua     "Locked" and note tooltip lines

local _, ns = ...

local Locking = ns:RegisterFeature("inventory", "locking", {
    order = 3,
    settings = {
        {
            key = "indicator",
            type = "dropdown",
            default = "padlock",
            options = { "padlock", "center", "corner", "none" },
        },
        { key = "keepInPlace", type = "toggle", default = true },
        { key = "showTooltip", type = "toggle", default = true },
        { key = "sellUnlockedJunk", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true },
    },
})

function Locking:OnEnable()
    ns:RefreshItemButtons()
    ns:RefreshJunk()
    self.Guards:Enable()
    self.Sorting:Enable()
end

function Locking:OnDisable()
    self.Notes:Disable()
    self.Sorting:Disable()
    self.Guards:Disable()
    self.Indicators:HideAll()
    ns:RefreshItemButtons()
    ns:RefreshJunk()
end

function Locking:OnSettingChanged(key, value)
    if key == "indicator" then
        ns:RefreshItemButtons()
    elseif key == "keepInPlace" and not value then
        self.Sorting:Cancel()
    end
end
