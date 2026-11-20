-- Blizzard's objective tracker back after combat. Once the map's taint has reached
-- the tracker (feature.lua), its updates run tainted, and in combat one throws on
-- the player's secret auras (ShouldShowMawBuffs, in its scenario module) and stops
-- halfway: sections out of place, a gap under a header. Its next-frame update
-- (DirtiableMixin) clears the container's dirty flag only once the update returns,
-- and MarkDirty schedules one only while the flag is clear: after the error, no
-- update ever runs again, and the tracker stays as the error left it until a /reload.
--
-- So on the frame after combat ends, a container still dirty runs the update its
-- next frame would have (its own dirtyCallback, which clears the flag), from our
-- code. Only when that flag was written from tainted code: a clean tracker's update
-- never throws, and running it from our code would taint it. One already pending
-- runs before ours on that frame (RunNextFrame is C_Timer.After(0)) and clears the
-- flag; one marked later on the same frame runs a second time, harmlessly.
--
-- Installed on the feature's first enable, for the rest of the session: the tracker
-- stays tainted until a /reload, turned off or not (feature.lua).

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")

local Tracker = {}
Seamless.Tracker = Tracker

local installed = false

local function Unstick()
    local seen = {}
    for _, container in pairs(ObjectiveTrackerManager.moduleToContainerMap) do
        if not seen[container] then
            seen[container] = true
            if container.dirty and not issecurevariable(container, "dirty") then
                securecallfunction(container.dirtyCallback)
            end
        end
    end
end

local listener = ns:CreateEventListener({
    PLAYER_REGEN_ENABLED = function()
        C_Timer.After(0, Unstick)
    end,
})

function Tracker:Enable()
    if not installed then
        installed = true
        listener:Start()
    end
end

-- Nothing: once installed, the tracker is unstuck after combat for the rest of the session.
function Tracker:Disable() end
