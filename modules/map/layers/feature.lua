-- Layer swaps: shows the player's layer in the tooltip of the zone name above
-- the minimap, and swaps to another layer from the player frame's menu (Swap
-- layer) or a key binding, through the players who use LayerSwap: the
-- LayerSwap addon's protocol, so the player reaches its hosts, and hosts for
-- its users when "host" is on. Nothing shows otherwise: no window, no chat
-- channel, and only the outcome of a swap in chat.
--
-- With LayerSwap itself loaded, the feature only shows the layer: two addons
-- answering the same asks would invite the same players twice.
--
-- "accept": accepting the invite of the host who answers the player's ask.
-- "host": inviting LayerSwap users who ask for another layer (opt-in: it
-- invites strangers).
--
-- Files of this slice:
--   feature.lua    registration, schema and lifecycle (this file)
--   locales.lua    strings
--   protocol.lua   LayerSwap's messages, layer ids, names and zones
--   comm.lua       paced addon whispers, and who receives them
--   reader.lua     the player's layer, read from creatures around
--   swap.lua       the player's own ask, up to the new layer
--   host.lua       host: inviting the players who ask
--   interface.lua  the menu entry, the tooltip line and the key binding

local _, ns = ...

local Layers = ns:RegisterFeature("map", "layers", {
    order = 6,
    settings = {
        { key = "accept", type = "toggle", default = true },
        { key = "host", type = "toggle", default = false },
    },
    presets = {
        minimal = { enabled = false },
        enhanced = { enabled = true, accept = true, host = false },
    },
})

-- Whether LayerSwap does the swapping: then the feature only shows the layer.
function Layers:StandsDown()
    return C_AddOns.IsAddOnLoaded("LayerSwap")
end

-- The key binding's action (Bindings.xml).
function Layers:OnBinding()
    if self:IsActive() then
        self.Swap:Toggle()
    end
end

function Layers:OnEnable()
    self.Reader:Enable()
    self.Interface:Enable()
    if not self:StandsDown() then
        self.Comm:Enable()
        self.Swap:Enable()
        self:SyncPart("host", self.Host)
    end
end

function Layers:OnDisable()
    self:SyncPart("host", self.Host)
    self.Swap:Disable()
    self.Comm:Disable()
    self.Reader:Disable()
end

function Layers:OnSettingChanged()
    if not self:StandsDown() then
        self:SyncPart("host", self.Host)
    end
end
