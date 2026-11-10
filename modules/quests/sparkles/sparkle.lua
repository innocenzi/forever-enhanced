-- The sparkle on lootable quest items shows while the hidden CVar
-- outlineModeShowLootEffectWhenDisabled is on. Graphics presets switch it off
-- (they rewrite it with graphicsQuality), so after any of those changes it is
-- set again a moment later. Account-synced settings can also arrive a few
-- seconds after entering the world.
-- Measured in game by Forever Loot Sparkles: switching it on shows the sparkle
-- at once, but switching it off only hides it after restarting the game.

local _, ns = ...

local Sparkles = ns:GetFeature("quests", "sparkles")

local Sparkle = {}
Sparkles.Sparkle = Sparkle

local CVAR = "outlineModeShowLootEffectWhenDisabled"
local ON = "1"
local REAPPLY_DELAY_SECONDS = 1
local ENTERING_WORLD_DELAY_SECONDS = 5

-- CVar changes after which the sparkle may be off (lower case: names are case-insensitive).
local RESETTING_CVARS = {
    graphicsquality = true,
    raidgraphicsquality = true,
    [CVAR:lower()] = true,
}

local override = ns:CreateCVarOverride(Sparkles)
local timer

local function Apply()
    override:Set(CVAR, ON)
end

local function CancelTimer()
    if timer then
        timer:Cancel()
        timer = nil
    end
end

local function ApplyLater(seconds)
    CancelTimer()
    timer = C_Timer.NewTimer(seconds, function()
        timer = nil
        Apply()
    end)
end

local listener = ns:CreateEventListener({
    CVAR_UPDATE = function(_, name)
        if RESETTING_CVARS[name:lower()] then
            ApplyLater(REAPPLY_DELAY_SECONDS)
        end
    end,
    PLAYER_ENTERING_WORLD = function()
        ApplyLater(ENTERING_WORLD_DELAY_SECONDS)
    end,
})

function Sparkle:Enable()
    Apply()
    listener:Start()
end

function Sparkle:Disable()
    listener:Stop()
    CancelTimer()
    -- The sparkle stays until a restart: say so when restoring turns it off.
    local hides = C_CVar.GetCVar(CVAR) == ON and override:GetSaved(CVAR) ~= ON
    override:Restore()
    if hides then
        ns:Print(ns.L["quests.sparkles.restart"])
    end
end
