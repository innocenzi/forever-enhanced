-- Duplicate macros: a Duplicate button in the macro window, copying the
-- selected macro (name, icon and text) into the same tab.
--
-- Files of this slice:
--   feature.lua  registration and lifecycle (this file)
--   locales.lua  strings
--   button.lua   the button beside New

local _, ns = ...

local Macros = ns:RegisterFeature("interface", "macros", {
    order = 4,
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true },
    },
})

function Macros:OnEnable()
    self.Button:Enable()
end

function Macros:OnDisable()
    self.Button:Disable()
end
