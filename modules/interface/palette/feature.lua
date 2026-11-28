-- Command palette: a key the player binds opens a search box over commands
-- (Blizzard's windows, the interface's toggles, other features' windows);
-- typing filters them, Up and Down pick one, Enter runs it.
--
-- Our code never opens Blizzard's windows (they would run tainted): while the
-- palette is open, an override binding maps Enter to the picked command's key
-- binding, and the palette lets Enter through to the bindings, so the game
-- runs it from the key press. The palette takes every other key. Override
-- bindings and key passthrough can't change in combat: the palette doesn't
-- open then, and closes as combat starts.
--
-- Commands come from every feature through ns:AddCommand (core/commands.lua).
--
-- Files of this slice:
--   feature.lua   registration, schema and lifecycle (this file)
--   locales.lua   strings
--   commands.lua  Blizzard's commands
--   search.lua    titles and search words, matching and ranking
--   store.lua     recently run commands
--   window.lua    the palette: text, results, keys, the Enter override

local _, ns = ...

local BINDING = "FOREVERENHANCED_PALETTE"

local Palette = ns:RegisterFeature("interface", "palette", {
    order = 4,
    settings = {
        { key = "key", type = "binding", binding = BINDING },
    },
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true },
    },
})

Palette.BINDING = BINDING

-- The key binding's action (Bindings.xml).
function Palette:OnBinding()
    if not self:IsActive() then
        return
    end
    if InCombatLockdown() then
        ns:Error(ERR_NOT_IN_COMBAT)
        return
    end
    self.Window:Toggle()
end

function Palette:OnDisable()
    self.Window:Close()
end

-- The key binding's name, in the player's language once it's known.
ns:CreateEventListener({
    PLAYER_LOGIN = function(listener)
        listener:Unregister("PLAYER_LOGIN")
        _G["BINDING_NAME_" .. BINDING] = ns.L["interface.palette.binding"]
    end,
}):Start()
