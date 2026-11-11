-- Bank: two parts, each behind its toggle.
--
-- "savedBank": every bank visit saves a copy of the character bank, viewable
-- anywhere in a read-only copy of Blizzard's bank frame, for this character
-- and the alts on the same ruleset. Opened from a side tab on the bags, or with
-- the bags when "openWithBags" is on. At a banker, Blizzard's bank takes over.
-- With "tooltipCount", item tooltips show how many the saved bank holds;
-- "reagentMark" marks the recipe reagents the saved bank can supply.
--
-- "transfers": at a banker, Deposit and Withdraw buttons move items between
-- the bags and the bank, either onto the other side's partial stacks only, or
-- every item the other side already holds (partial stacks first, then empty
-- slots). Locked items (Item Locking) never move.
--
-- Files of this slice:
--   feature.lua    registration, schema and lifecycle (this file)
--   locales.lua    strings
--   store.lua      saved banks, shared by every character of the account
--   snapshot.lua   saves the bank while a banker is open
--   search.lua     search box, kept in sync with the bags' search
--   view.lua       the saved bank frame
--   tab.lua        side tab on the bags, opening with the bags
--   tooltip.lua    bank count in item tooltips
--   reagents.lua   bank mark on recipe reagent slots
--   transfers.lua  the transfer runner
--   planner.lua    the moves a transfer still needs, from live positions
--   buttons.lua    Deposit / Withdraw buttons and their menus

local _, ns = ...

local Bank = ns:RegisterFeature("inventory", "bank", {
    order = 1,
    settings = {
        { key = "savedBank", type = "toggle", default = true },
        { key = "tooltipCount", type = "toggle", default = true, requires = { savedBank = true } },
        { key = "openWithBags", type = "toggle", default = false, requires = { savedBank = true } },
        {
            key = "reagentMark",
            type = "dropdown",
            default = "line",
            options = { "line", "icon", "count", "none" },
            requires = { savedBank = true },
        },
        { key = "transfers", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true, savedBank = true, openWithBags = true },
    },
})

-- The saved bank part: its components check Bank:IsPartActive("savedBank").
local SavedBank = {}

function SavedBank:Enable()
    Bank.Snapshot:Enable()
    Bank.Search:Enable()
    Bank.Tab:Enable()
    Bank.Reagents:Enable()
end

function SavedBank:Disable()
    Bank.Reagents:Disable()
    Bank.Tab:Disable()
    Bank.View:Close()
    Bank.Search:Disable()
    Bank.Snapshot:Disable()
end

-- "7 in the bank", in gold: the bank count wherever the slice shows it.
function Bank:FormatCount(count)
    return NORMAL_FONT_COLOR:WrapTextInColorCode(ns.L["inventory.bank.countLine"]:format(count))
end

function Bank:SyncParts()
    self:SyncPart("savedBank", SavedBank)
    self:SyncPart("transfers", self.Transfers)
end

function Bank:OnEnable()
    self:SyncParts()
end

function Bank:OnSettingChanged(key)
    self:SyncParts()
    if key == "reagentMark" then
        self.Reagents:Refresh()
    end
end

function Bank:OnDisable()
    self:SyncParts()
end
