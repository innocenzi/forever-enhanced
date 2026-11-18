-- Lowest value items: marks the bag items worth the least, to know what to
-- destroy when the bags are full. A stack's value is its count times the
-- higher of its sell price and its auction price (Auction prices, unbound
-- items only). Every item tied for the lowest value is marked; locked items
-- and items without a sell price never are, nor are bank items.
--   "onlyWhenFull":      marks only while every slot of the regular bags is
--                        taken (free slots of special bags, like quivers,
--                        don't count);
--   "indicator":         a red glow, a red cross or a coin (bottom-left corner);
--   "excludeReagentBag": leaves the reagent bag out: its items aren't marked
--                        and its free slots don't count.
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   value.lua    bag fullness and the lowest value items
--   buttons.lua  the marks drawn on item buttons

local _, ns = ...

local Cheapest = ns:RegisterFeature("inventory", "cheapest", {
    order = 8,
    enabledByDefault = false,
    settings = {
        { key = "onlyWhenFull", type = "toggle", default = true },
        { key = "indicator", type = "dropdown", default = "glow", options = { "glow", "cross", "coin" } },
        { key = "excludeReagentBag", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true, onlyWhenFull = true, indicator = "glow", excludeReagentBag = true },
    },
})

function Cheapest:OnEnable()
    self.Buttons:Enable()
    ns:RefreshItemButtons()
end

function Cheapest:OnDisable()
    self.Buttons:Disable()
    ns:RefreshItemButtons()
end

function Cheapest:OnSettingChanged()
    ns:RefreshItemButtons()
end
