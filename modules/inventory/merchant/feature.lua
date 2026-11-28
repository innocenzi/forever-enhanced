-- Merchant: a search box on the merchant's items (the "search" part), a glow on
-- the Repair All button while the equipment is damaged (the "repairGlow" part),
-- and when a merchant opens, sells the junk Sell All Junk Items would sell
-- (Blizzard's, plus the items marked as junk in Item marks) and repairs all
-- items, from guild funds first if the player chose so.
--
-- Files of this slice:
--   feature.lua     registration, schema and lifecycle (this file)
--   locales.lua     strings
--   junk.lua        sells the junk
--   repair.lua      repairs all items, once the junk money arrives if needed
--   repairglow.lua  the repairGlow part
--   search.lua      the search part: dimming, page arrows and the page jump
--   searchbox.lua   the search part's box

local _, ns = ...

local Merchant = ns:RegisterFeature("inventory", "merchant", {
    page = "trading",
    order = 1,
    settings = {
        { key = "search", type = "toggle", default = true },
        { key = "repairGlow", type = "toggle", default = true },
        {
            key = "repairGlowThreshold",
            type = "slider",
            default = 50,
            min = 5,
            max = 95,
            step = 5,
            requires = { repairGlow = true },
        },
        -- They sell and spend money on their own: the player opts in.
        { key = "autoSellJunk", type = "toggle", default = false },
        { key = "autoRepair", type = "toggle", default = false },
        { key = "guildFunds", type = "toggle", default = false, requires = { autoRepair = true } },
        { key = "announce", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = true, search = true, repairGlow = true, autoSellJunk = false, autoRepair = false },
        enhanced = { enabled = true, search = true, repairGlow = true, autoSellJunk = true, autoRepair = true },
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

function Merchant:SyncParts()
    self:SyncPart("search", self.Search)
    self:SyncPart("repairGlow", self.RepairGlow)
end

function Merchant:OnEnable()
    listener:Start()
    self:SyncParts()
end

function Merchant:OnDisable()
    listener:Stop()
    self.Repair:Cancel()
    self:SyncParts()
end

function Merchant:OnSettingChanged(key, value)
    self:SyncParts()
    if key == "repairGlowThreshold" then
        self.RepairGlow:Refresh()
    elseif key == "autoRepair" and not value then
        self.Repair:Cancel()
    end
end
