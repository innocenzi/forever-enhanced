-- Clear Map Pin on Arrival: removes the map pin (the user waypoint placed from
-- the world map) once the player gets within a set distance of it, tracked or
-- not, optionally with Blizzard's "destination reached" message.
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   arrival.lua  distance to the pin, checked on a ticker while a pin exists

local _, ns = ...

local Waypoint = ns:RegisterFeature("interface", "waypoint", {
    order = 2,
    settings = {
        { key = "range", type = "slider", default = 30, min = 5, max = 100, step = 5 },
        { key = "announce", type = "toggle", default = true },
    },
})

function Waypoint:OnEnable()
    self.Arrival:Enable()
end

function Waypoint:OnDisable()
    self.Arrival:Disable()
end

function Waypoint:OnSettingChanged(key)
    if key == "range" then
        self.Arrival:Rearm()
    end
end
