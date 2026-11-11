-- Combo Points on Nameplates: shows the player's combo points under the
-- nameplate of each unit holding some (Forever has no class bar on
-- nameplates), for any class that builds them (Rogues, Druids in Cat Form).
--
-- Files of this slice:
--   feature.lua  registration and lifecycle (this file)
--   locales.lua  strings
--   bar.lua      a bar of points on each nameplate whose unit holds some

local _, ns = ...

local ComboPoints = ns:RegisterFeature("combat", "combopoints", {
    order = 2,
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true },
    },
})

function ComboPoints:OnEnable()
    self.Bars:Enable()
end

function ComboPoints:OnDisable()
    self.Bars:Disable()
end
