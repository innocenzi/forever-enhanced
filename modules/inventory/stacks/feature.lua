-- Item stacks: while Shift is held and the tooltip shows an item (from the
-- bags, the bank, equipped gear, a merchant, loot...), every other bag and bank
-- slot is dimmed like Blizzard's bag search does, empty slots included, so only
-- that item's stacks stay lit. An item the bags and bank don't hold dims them all.
--
-- Files of this slice:
--   feature.lua  registration and lifecycle (this file)
--   locales.lua  strings
--   buttons.lua  the shown item and the dimming drawn on item buttons

local _, ns = ...

local Stacks = ns:RegisterFeature("inventory", "stacks", {
    page = "bags",
    order = 2,
})

function Stacks:OnEnable()
    self.Buttons:Enable()
    ns:RefreshItemButtons()
end

function Stacks:OnDisable()
    self.Buttons:Disable()
    ns:RefreshItemButtons()
end
