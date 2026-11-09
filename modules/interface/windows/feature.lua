-- Movable Windows: drag UI panels and bags by their title bar (optionally only
-- while holding a modifier). Positions are saved for the whole account and
-- re-applied whenever Blizzard lays the windows out again. Shift Right Click on
-- a title bar puts the window back where Blizzard places it.
--
-- Files of this slice:
--   feature.lua    registration, schema and lifecycle (this file)
--   locales.lua    strings
--   store.lua      saved positions, by frame name
--   placement.lua  every change to a window's anchors (saved positions, drags,
--                  resets, undoing), deferred in combat
--   handles.lua    drag handles laid over the title bars: player input only
--   tracking.lua   which frames are movable, hooks on Blizzard's layout code

local _, ns = ...

local Windows = ns:RegisterFeature("interface", "windows", {
    order = 1,
    settings = {
        { key = "modifier", type = "dropdown", default = "none", options = { "none", "shift", "ctrl", "alt" } },
    },
})

function Windows:OnEnable()
    self.Handles:ShowAll()
    self.Tracking:Enable()
end

function Windows:OnDisable()
    self.Handles:HideAll()
    self.Placement:RestoreAll()
end
