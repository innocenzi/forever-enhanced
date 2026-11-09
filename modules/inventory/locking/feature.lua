-- Item Locking: Alt+Left-click a bag or bank item to lock that exact item
-- (by GUID). A locked item can't be picked up, right-click is blocked wherever
-- it would sell, mail, trade or auction the item, Sell All Junk keeps it, and
-- sorting leaves it in place.
--
-- Files of this slice:
--   feature.lua     registration, schema and lifecycle (this file)
--   locales.lua     strings
--   store.lua       lock set and public API
--   indicators.lua  lock indicator styles drawn on item buttons
--   buttons.lua     item buttons: indicators and click shield
--   guards.lua      cursor guard
--   junk.lua        Sell All Junk with locked junk
--   sorting.lua     puts locked items back after a sort
--   tooltip.lua     "Locked" tooltip line

local _, ns = ...

local Locking = ns:RegisterFeature("inventory", "locking", {
    order = 1,
    settings = {
        {
            key = "indicator",
            type = "dropdown",
            default = "padlock",
            options = { "padlock", "center", "corner", "none" },
        },
        { key = "keepInPlace", type = "toggle", default = true },
        { key = "sellUnlockedJunk", type = "toggle", default = true },
        { key = "showTooltip", type = "toggle", default = true },
        { key = "announce", type = "toggle", default = true },
    },
})

function Locking:OnEnable()
    self.Buttons:Enable()
    self.Guards:Enable()
    self.Junk:Enable()
    self.Sorting:Enable()
end

function Locking:OnDisable()
    self.Sorting:Disable()
    self.Junk:Disable()
    self.Guards:Disable()
    self.Buttons:Disable()
end

function Locking:OnSettingChanged(key, value)
    if key == "indicator" then
        self.Buttons:Refresh()
    elseif key == "keepInPlace" and not value then
        self.Sorting:Cancel()
    end
end
