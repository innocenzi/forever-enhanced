-- Merchant: when a merchant opens, sells the junk Sell All Junk Items would
-- sell (locked items are kept) and repairs all items, from guild funds first
-- if the player chose so.
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   junk.lua     sells the junk
--   repair.lua   repairs all items, once the junk money arrives if needed

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
        { key = "announce", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true, autoSellJunk = true, autoRepair = true },
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
end

function Merchant:OnDisable()
    listener:Stop()
    self.Repair:Cancel()
end

function Merchant:OnSettingChanged(key, value)
    if key == "autoRepair" and not value then
        self.Repair:Cancel()
    end
end
