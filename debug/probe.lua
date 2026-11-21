-- Temporary probes, written by the debugging skill (.claude/skills/debugging):
-- Lua that only observes the game, run at each load of the UI, its findings
-- in the log. Nothing past this header is ever committed. For example:
--
--   ns:AtLogin("probe.bank", function()
--       ns:Log("probe.bank", BankFrame:IsShown(), ForeverEnhanced:GetFeature("inventory", "bank"):IsActive())
--   end)

local _, ns = ...
