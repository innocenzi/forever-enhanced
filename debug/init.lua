-- Forever Enhanced Debug: the maintainer's debugging addon, junctioned into the
-- game as Interface\AddOns\ForeverEnhancedDebug and never packaged (.pkgmeta).
-- See "Debug addon" in AGENTS.md.
--
-- Files, in load order:
--   init.lua       the namespace (also _G.ForeverEnhancedDebug), shared helpers
--   serialize.lua  values to text
--   log.lua        the log, kept across reloads and sessions
--   api.lua        Log / Events / Hook / Stack, for temporary debugging calls
--   recorder.lua   the last events, dumped with each incident
--   incidents.lua  what went wrong because of the addon: logged with context
--   watches.lua    taint of the Blizzard state our features touch
--   errors.lua     our errors (through BugGrabber) and blocked actions
--   window.lua     /fedebug
--   probe.lua      temporary probes (debugging skill), empty when committed

local _, ns = ...

_G.ForeverEnhancedDebug = ns

-- The addon under watch: its folder name, which the game names in taint
-- messages and blocked actions.
ns.ADDON = "ForeverEnhanced"

function ns:Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Forever Enhanced Debug|r: " .. text)
end
