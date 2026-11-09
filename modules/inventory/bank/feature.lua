-- Saved Bank: every bank visit saves a copy of the character bank, viewable
-- anywhere in a read-only copy of Blizzard's bank frame, for this character
-- and the alts on the same ruleset. Opened from a side tab on the bags, or with
-- the bags when "openWithBags" is on. At a banker, Blizzard's bank takes over.
-- With "tooltipCount", item tooltips show how many the saved bank holds;
-- "reagentMark" marks the recipe reagents the saved bank can supply.
--
-- Files of this slice:
--   feature.lua   registration, schema and lifecycle (this file)
--   locales.lua   strings
--   store.lua     saved banks, shared by every character of the account
--   snapshot.lua  saves the bank while a banker is open
--   search.lua    search box, kept in sync with the bags' search
--   view.lua      the saved bank frame
--   tab.lua       side tab on the bags, opening with the bags
--   tooltip.lua   bank count in item tooltips
--   reagents.lua  bank mark on recipe reagent slots

local _, ns = ...

local Bank = ns:RegisterFeature("inventory", "bank", {
    order = 2,
    settings = {
        { key = "openWithBags", type = "toggle", default = false },
        { key = "tooltipCount", type = "toggle", default = true },
        {
            key = "reagentMark",
            type = "dropdown",
            default = "line",
            options = { "line", "icon", "count", "none" },
        },
    },
})

-- "7 in the bank", in gold: the bank count wherever the slice shows it.
function Bank:FormatCount(count)
    return NORMAL_FONT_COLOR:WrapTextInColorCode(ns.L["inventory.bank.countLine"]:format(count))
end

function Bank:OnEnable()
    self.Snapshot:Enable()
    self.Search:Enable()
    self.Tab:Enable()
    self.Reagents:Enable()
end

function Bank:OnSettingChanged(key)
    if key == "reagentMark" then
        self.Reagents:Refresh()
    end
end

function Bank:OnDisable()
    self.Reagents:Disable()
    self.Tab:Disable()
    self.View:Close()
    self.Search:Disable()
    self.Snapshot:Disable()
end
