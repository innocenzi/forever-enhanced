-- TomTom /way command: sets the map pin (the user waypoint) from the TomTom
-- commands guides hand out, for players without TomTom: /way, /wayb and /cway.
-- Each command is left alone when another addon (TomTom) already owns it.
--
-- Files of this slice:
--   feature.lua   registration, schema and lifecycle (this file)
--   locales.lua   strings
--   parser.lua    reads "[zone] x y [description]" and finds zones by name
--   commands.lua  the slash commands and their registration

local _, ns = ...

local Way = ns:RegisterFeature("map", "way", {
    order = 2,
    settings = {
        { key = "track", type = "toggle", default = true },
    },
    presets = {
        minimal = { enabled = true },
        enhanced = { enabled = true },
    },
})

function Way:OnEnable()
    self.Commands:Register()
end

function Way:OnDisable()
    self.Commands:Unregister()
end
