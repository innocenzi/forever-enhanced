-- Reserved slots: "Reserve this slot" in the item menu (Alt Right Click) gives
-- a bag or bank slot to that item (by item ID). When more of the item arrives
-- (looted, bought, deposited) or the bags or bank are cleaned up, a stack of it
-- goes back to its slot, swapping out whatever took it. An empty reserved slot
-- shows the item's icon, faded; its menu (Alt Right Click) frees it.
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   store.lua    reservations and public API
--   buttons.lua  item buttons: faded icon, menu entry
--   restore.lua  moves reserved items to their slot

local _, ns = ...

local Slots = ns:RegisterFeature("inventory", "slots", {
    page = "bags",
    order = 3,
    settings = {
        { key = "showIcon", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = true, showIcon = true },
        enhanced = { enabled = true, showIcon = true },
    },
})

function Slots:OnEnable()
    ns:RefreshItemButtons()
    self.Restore:Enable()
end

function Slots:OnDisable()
    self.Restore:Disable()
    self.Buttons:HideAll()
    ns:RefreshItemButtons()
end

function Slots:OnSettingChanged(key)
    if key == "showIcon" then
        ns:RefreshItemButtons()
    end
end
