-- Saved Bank: every bank visit saves a copy of the character bank, viewable
-- anywhere in a read-only copy of Blizzard's bank frame, for this character
-- and the alts on the same ruleset. Opened from a side tab on the bags, or with
-- the bags when "openWithBags" is on. At a banker, Blizzard's bank takes over.
--
-- Files of this slice:
--   feature.lua   registration, schema and lifecycle (this file)
--   locales.lua   strings
--   store.lua     saved banks, shared by every character of the account
--   snapshot.lua  saves the bank while a banker is open
--   search.lua    search box, kept in sync with the bags' search
--   view.lua      the saved bank frame
--   tab.lua       side tab on the bags, opening with the bags

local _, ns = ...

local Bank = ns:RegisterFeature("inventory", "bank", {
    order = 2,
    settings = {
        { key = "openWithBags", type = "toggle", default = false },
    },
})

function Bank:OnEnable()
    self.Snapshot:Enable()
    self.Search:Enable()
    self.Tab:Enable()
end

function Bank:OnDisable()
    self.Tab:Disable()
    self.View:Close()
    self.Search:Disable()
    self.Snapshot:Disable()
end
