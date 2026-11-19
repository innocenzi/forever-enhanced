-- Where the player meets the feature, all inside Blizzard's own UI:
--   * the zone name above the minimap: its tooltip gets one line, the layer
--     ("Layer B"), or the ask while one runs (a post-hook of
--     Minimap_SetTooltip, which fills that tooltip);
--   * the player frame's right-click menu (MENU_UNIT_SELF): Swap layer,
--     Cancel layer swap while an ask waits. Not in instances, which have no
--     layers, nor in a group outside an ask;
--   * a key binding (Bindings.xml), under the addon's header in the AddOns
--     category of the key bindings.
-- The menu and the key are clicks and key presses: the only moments the game
-- lets an addon search for players.
-- Hooks and menu modifiers can't be removed: installed on the first enable,
-- they check the feature first, and run through securecallfunction so their
-- errors stay out of Blizzard's code.

local _, ns = ...

local Layers = ns:GetFeature("map", "layers")

local Interface = {}
Layers.Interface = Interface

local installed = false

local function AddMenuEntry(_, rootDescription)
    if not Layers:IsActive() or Layers:StandsDown() or IsInInstance() then
        return
    end
    local asking = Layers.Swap:IsAsking()
    -- A swap can't start from a group; one running sits in the host's group.
    if not asking and IsInGroup() then
        return
    end
    local key = asking and "map.layers.stop" or "map.layers.swap"
    rootDescription:CreateDivider()
    rootDescription:CreateButton(ns.L[key], function()
        Layers.Swap:Toggle()
    end)
end

local function AddTooltipLine()
    if not Layers:IsActive() or not GameTooltip:IsOwned(MinimapCluster.ZoneTextButton) or IsInInstance() then
        return
    end
    local text
    if Layers.Swap:IsAsking() then
        text = ns.L["map.layers.asking"]
    else
        text = Layers.Reader:GetLabel() or ns.L["map.layers.unknown"]
    end
    GameTooltip_AddNormalLine(GameTooltip, text)
    GameTooltip:Show()
end

function Interface:Enable()
    if installed then
        return
    end
    installed = true
    Menu.ModifyMenu("MENU_UNIT_SELF", function(...)
        securecallfunction(AddMenuEntry, ...)
    end)
    ns:HookSecureFunc("Minimap_SetTooltip", AddTooltipLine)
end

-- The key binding's name, in the player's language once it's known.
ns:CreateEventListener({
    PLAYER_LOGIN = function(listener)
        listener:Unregister("PLAYER_LOGIN")
        _G.BINDING_NAME_FOREVERENHANCED_SWAPLAYER = ns.L["map.layers.swap"]
    end,
}):Start()
