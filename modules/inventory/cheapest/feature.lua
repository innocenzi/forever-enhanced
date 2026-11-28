-- Lowest value items: marks the bag items worth the least, to know what to
-- destroy when the bags are full. A stack's value is its count times the
-- higher of its sell price and its auction price (Auction prices, unbound
-- items only). Every item tied for the lowest value is marked; locked items
-- and items without a sell price never are, nor are bank items.
--   "onlyWhenFull":      marks only while every slot of the regular bags is
--                        taken (free slots of special bags, like quivers,
--                        don't count);
--   "indicator":         a red glow, a red cross or a coin (bottom-left corner);
--   "ignore":            a dropdown of checkboxes (all checked by default) of
--                        items never marked; the others are ranked without
--                        them, so the cheapest of the rest is marked instead:
--     food           food or drink (inventory.food's data, whether or not that
--                    feature is on);
--     questItems     items an item objective of the quest log asks for
--                    (quests.helpers' index: nothing while its objectives and
--                    leftovers parts are both off);
--     tools          tools profession spells need on hand (data.lua) and
--                    fishing poles;
--     reagents       reagents of recipes this character knows
--                    (professions.reagents' known recipes: nothing while that
--                    feature is off);
--     classReagents  reagents and tools of the player's class spells (data.lua:
--                    Ankh, Soul Shard, Earth Totem) and ammo;
--     actionBars     items on an action slot;
--     marks          items marked for the auction house, bank or mail
--                    (inventory.marks, while that mark is on);
--     notes          items with a note (inventory.marks, while notes are on);
--   "excludeReagentBag": leaves the reagent bag out: its items aren't marked
--                        and its free slots don't count (a setting of its own,
--                        not an "ignore" option, for that second part).
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   data.lua     generated: profession tools and class reagents (tools/cheapest.ts)
--   value.lua    bag fullness and the lowest value items
--   buttons.lua  the marks drawn on item buttons

local _, ns = ...

-- What "ignore" can leave out, in menu order (value.lua tests each).
local IGNORE_OPTIONS = { "food", "questItems", "tools", "reagents", "classReagents", "actionBars", "marks", "notes" }
local IGNORE_ALL = {}
for _, option in ipairs(IGNORE_OPTIONS) do
    IGNORE_ALL[option] = true
end

local Cheapest = ns:RegisterFeature("inventory", "cheapest", {
    page = "bags",
    order = 5,
    enabledByDefault = false,
    settings = {
        { key = "onlyWhenFull", type = "toggle", default = true },
        { key = "indicator", type = "dropdown", default = "glow", options = { "glow", "cross", "coin" } },
        { key = "ignore", type = "multiselect", default = IGNORE_ALL, options = IGNORE_OPTIONS },
        { key = "excludeReagentBag", type = "toggle", default = true },
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
