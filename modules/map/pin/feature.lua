-- Map pin: two parts acting on the map pin (the user waypoint), each behind its
-- toggle.
--
-- "commands": TomTom's /way, /wayb and /cway set the map pin from the
-- commands guides hand out, for players without TomTom. Each command is left
-- alone when another addon (TomTom) already owns it. "track" also tracks it.
--
-- "arrival": removes the map pin once the player gets within "range" of it,
-- tracked or not, with Blizzard's "destination reached" message ("announce").
--
-- Files of this slice:
--   feature.lua   registration, schema and lifecycle (this file)
--   locales.lua   strings
--   parser.lua    reads "[zone] x y [description]" and finds zones by name
--   commands.lua  the slash commands and their registration
--   arrival.lua   distance to the pin, checked on a ticker while a pin exists

local _, ns = ...

local Pin = ns:RegisterFeature("map", "pin", {
    order = 2,
    settings = {
        { key = "commands", type = "toggle", default = true },
        { key = "track", type = "toggle", default = true, requires = { commands = true } },
        { key = "arrival", type = "toggle", default = true },
        { key = "range", type = "slider", default = 30, min = 5, max = 100, step = 5, requires = { arrival = true } },
        { key = "announce", type = "toggle", default = true, requires = { arrival = true } },
    },
    presets = {
        minimal = { enabled = true, announce = false },
        enhanced = { enabled = true },
    },
})

-- The commands part: registered while it runs.
local CommandsPart = {}

function CommandsPart:Enable()
    Pin.Commands:Register()
end

function CommandsPart:Disable()
    Pin.Commands:Unregister()
end

function Pin:SyncParts()
    self:SyncPart("commands", CommandsPart)
    self:SyncPart("arrival", self.Arrival)
end

function Pin:OnEnable()
    self:SyncParts()
end

function Pin:OnDisable()
    self:SyncParts()
end

function Pin:OnSettingChanged(key)
    self:SyncParts()
    if key == "range" and self:IsPartActive("arrival") then
        self.Arrival:Rearm()
    end
end
