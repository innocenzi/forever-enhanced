-- Friends on the Map: friends who also use the addon show on the world map,
-- and the player shows on theirs. The game only gives positions of the
-- player's group, so each client sends its own, over addon messages, and only
-- while a friend looks at the map: opening the map asks online friends for
-- their position; they answer for as long as it stays open. Only friends
-- (character friends and Battle.net friends) are ever answered.
--
-- "share": answering friends' requests. When off, the player still sees friends.
-- "openmap": also speaking OpenMap's protocol, to see friends who use the
-- OpenMap addon and, while sharing, be seen by them.
--
-- Files of this slice:
--   feature.lua  registration, schema and lifecycle (this file)
--   locales.lua  strings
--   roster.lua   online friends who could run the addon, by GUID, and how to reach them
--   comm.lua     paced channels that only hear friends, and the addon's own protocol
--   sharing.lua  share: answers watching friends with the player's position
--   map.lua      the friends' pins on the world map and the requests behind them
--   openmap.lua  openmap: OpenMap's protocol, on a channel of its own
--   pins.xml     the pin template

local _, ns = ...

local Friends = ns:RegisterFeature("map", "friends", {
    order = 3,
    enabledByDefault = false,
    settings = {
        { key = "share", type = "toggle", default = true },
        { key = "openmap", type = "toggle", default = false },
    },
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true, openmap = true },
    },
})

function Friends:OnEnable()
    self.Roster:Enable()
    self.Comm:Enable()
    self.Map:Enable()
    self:SyncPart("share", self.Sharing)
    self:SyncPart("openmap", self.OpenMap)
end

function Friends:OnDisable()
    self:SyncPart("openmap", self.OpenMap)
    self:SyncPart("share", self.Sharing)
    self.Map:Disable()
    self.Comm:Disable()
    self.Roster:Disable()
end

function Friends:OnSettingChanged()
    self:SyncPart("share", self.Sharing)
    self:SyncPart("openmap", self.OpenMap)
end
