-- Item marks: the item menu (Alt Right Click) marks where an item goes, by
-- item ID, so every copy of it shows that destination's icon. Each mark is a
-- part behind its toggle:
--   "junk":    Mark as junk: Sell All Junk Items and the merchant's auto
--              selling sell it (locked copies are kept); the junk coin, at
--              merchants like Blizzard's on poor items, or always ("junkCoin");
--   "auction": Mark for auction house, the auctioneer's icon in bags and bank;
--   "bank":    Mark for bank, the banker's icon in the bags; Deposit moves them
--              to the bank (bank feature, "marked" transfer).
-- An item has one destination at most: marking one removes the others. Locked
-- items show no icon. "altClick" picks what Alt Left Click does: lock the item
-- (Item locking, by default) or one of the marks.
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   store.lua    each item ID's destination and public API
--   junk.lua     adds items marked as junk to the junk Sell All Junk sells
--   buttons.lua  icons, Alt Left Click and the item menu entries

local _, ns = ...

-- Destinations, in menu order; each is a part behind the toggle of the same key.
local DESTINATIONS = { "junk", "auction", "bank" }

local Marks = ns:RegisterFeature("inventory", "marks", {
    order = 4,
    settings = {
        { key = "junk", type = "toggle", default = true },
        {
            key = "junkCoin",
            type = "dropdown",
            default = "merchant",
            options = { "merchant", "always" },
            requires = { junk = true },
        },
        { key = "auction", type = "toggle", default = true },
        { key = "bank", type = "toggle", default = true },
        { key = "altClick", type = "dropdown", default = "lock", options = { "lock", "junk", "auction", "bank" } },
    },
    presets = {
        minimal = { enabled = true, junkCoin = "merchant" },
        enhanced = { enabled = true, junkCoin = "always" },
    },
})

Marks.DESTINATIONS = DESTINATIONS

local parts = {}

local function GetPart(destination)
    if not parts[destination] then
        parts[destination] = {
            Enable = function()
                ns:RefreshItemButtons()
                ns:RefreshJunk()
            end,
            Disable = function()
                Marks.Buttons:HideAll(destination)
                ns:RefreshItemButtons()
                ns:RefreshJunk()
            end,
        }
    end
    return parts[destination]
end

function Marks:SyncParts()
    for _, destination in ipairs(DESTINATIONS) do
        self:SyncPart(destination, GetPart(destination))
    end
end

function Marks:OnEnable()
    self:SyncParts()
end

function Marks:OnDisable()
    self:SyncParts()
end

function Marks:OnSettingChanged(key)
    self:SyncParts()
    if key == "junkCoin" then
        ns:RefreshItemButtons()
    end
end
