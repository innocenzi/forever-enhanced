-- Item marks and notes: what the item menu (Alt Right Click) attaches to an
-- item. Marks say where an item goes, by item ID, so every copy of it shows
-- that destination's icon. Each mark is a part behind its toggle:
--   "junk":    Mark as junk: Sell All Junk Items and the merchant's auto
--              selling sell it (locked copies are kept); the junk coin, at
--              merchants like Blizzard's on poor items, or always ("junkCoin");
--   "auction": Mark for auction house, the auctioneer's icon in bags and bank;
--              marked bag items glow while the auction house is open
--              ("auctionGlow");
--   "bank":    Mark for bank, the banker's icon in the bags; Deposit moves them
--              to the bank (bank feature, "marked" transfer); marked bag items
--              glow while the bank is open ("bankGlow");
--   "mail":    Mark for mail, asking who to send the item to (shown in its
--              tooltip), the mail icon in bags and bank; marked bag items glow
--              while the mailbox is open ("mailGlow") or while trading with
--              their recipient ("mailTradeGlow").
-- Junk excludes the other marks; auction house, bank and mail combine, the
-- item showing the icon of its next stop (the window open for one of its
-- marks, otherwise bank, then mail, then auction house; no bank icon in the
-- bank). Locked items show no icon. "altClick" picks what
-- Alt Left Click does: lock the item (Item locking, by default) or one of the
-- marks.
-- Two more parts, each behind its toggle:
--   "notes":   Add note writes a note on that exact item (by GUID, unlike
--              marks), shown in its tooltip;
--   "wowhead": Wowhead link shows the item's Wowhead page address, ready to
--              copy (off by default).
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   store.lua    each item ID's destinations and public API
--   mail.lua     mail: recipient dialog and tooltip line
--   junk.lua     adds items marked as junk to the junk Sell All Junk sells
--   buttons.lua  icons, Alt Left Click and the marks' item menu entries
--   notes.lua    notes: store, dialog, menu entry and tooltip line
--   wowhead.lua  wowhead: dialog and menu entry

local _, ns = ...

-- Destinations, in menu order; each is a part behind the toggle of the same key.
local DESTINATIONS = { "junk", "auction", "bank", "mail" }

local Marks = ns:RegisterFeature("inventory", "marks", {
    order = 5,
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
        { key = "auctionGlow", type = "toggle", default = true, requires = { auction = true } },
        { key = "bank", type = "toggle", default = true },
        { key = "bankGlow", type = "toggle", default = true, requires = { bank = true } },
        { key = "mail", type = "toggle", default = true },
        { key = "mailGlow", type = "toggle", default = true, requires = { mail = true } },
        { key = "mailTradeGlow", type = "toggle", default = true, requires = { mail = true } },
        { key = "notes", type = "toggle", default = true },
        { key = "wowhead", type = "toggle", default = false },
        {
            key = "altClick",
            type = "dropdown",
            default = "lock",
            options = { "lock", "junk", "auction", "bank", "mail" },
        },
    },
    presets = {
        minimal = {
            enabled = true,
            junkCoin = "merchant",
            auctionGlow = true,
            bankGlow = true,
            mailGlow = true,
            mailTradeGlow = true,
            notes = true,
            wowhead = false,
        },
        enhanced = {
            enabled = true,
            junkCoin = "always",
            auctionGlow = true,
            bankGlow = true,
            mailGlow = true,
            mailTradeGlow = true,
            notes = true,
            wowhead = true,
        },
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
                if destination == "mail" then
                    Marks.Mail:HideDialog()
                end
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
    self:SyncPart("notes", self.Notes)
    self:SyncPart("wowhead", self.Wowhead)
end

function Marks:OnEnable()
    self:SyncParts()
end

function Marks:OnDisable()
    self:SyncParts()
end

function Marks:OnSettingChanged(key)
    self:SyncParts()
    if key == "junkCoin" or key:find("Glow$") then
        ns:RefreshItemButtons()
    end
end
