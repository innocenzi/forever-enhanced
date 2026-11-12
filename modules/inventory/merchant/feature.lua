-- Merchant: "Mark as junk" in the item menu (Alt Right Click) marks an item,
-- by item ID, so every copy of it is junk: Sell All Junk Items sells it (locked
-- copies are kept), and it shows the junk coin (at merchants like Blizzard's
-- on poor items, or always on all junk). When a merchant opens, sells
-- the junk Sell All Junk Items would sell and repairs all items, from guild
-- funds first if the player chose so.
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   junk.lua     sells the junk
--   repair.lua   repairs all items, once the junk money arrives if needed
--   marks.lua    junk marks (markJunk part) and public API
--   buttons.lua  junk coin and the item menu entry

local _, ns = ...

local Merchant = ns:RegisterFeature("inventory", "merchant", {
    order = 2,
    enabledByDefault = false,
    settings = {
        { key = "autoSellJunk", type = "toggle", default = true },
        { key = "autoRepair", type = "toggle", default = true },
        {
            key = "repairFunds",
            type = "dropdown",
            default = "player",
            options = { "player", "guild" },
            requires = { autoRepair = true },
        },
        { key = "markJunk", type = "toggle", default = true },
        {
            key = "junkCoin",
            type = "dropdown",
            default = "merchant",
            options = { "merchant", "always" },
            requires = { markJunk = true },
        },
        { key = "announce", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = true, markJunk = true, junkCoin = "merchant", autoSellJunk = false, autoRepair = false },
        enhanced = { enabled = true, markJunk = true, junkCoin = "always", autoSellJunk = true, autoRepair = true },
    },
})

local listener = ns:CreateEventListener({
    MERCHANT_SHOW = function()
        Merchant.Repair:Start(Merchant.Junk:Sell())
    end,
    PLAYER_MONEY = function()
        Merchant.Repair:Retry()
    end,
    MERCHANT_CLOSED = function()
        Merchant.Repair:Cancel()
    end,
})

function Merchant:Announce(message)
    if self:GetSetting("announce") then
        ns:Print(message)
    end
end

function Merchant:OnEnable()
    listener:Start()
    self:SyncPart("markJunk", self.Marks)
end

function Merchant:OnDisable()
    listener:Stop()
    self.Repair:Cancel()
    self:SyncPart("markJunk", self.Marks)
end

function Merchant:OnSettingChanged(key, value)
    self:SyncPart("markJunk", self.Marks)
    if key == "junkCoin" then
        ns:RefreshItemButtons()
    end
    if key == "autoRepair" and not value then
        self.Repair:Cancel()
    end
end
