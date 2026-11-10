-- The soft targeting CVars the glow needs, put back as the player had them
-- when it's disabled. SoftTargetLowPriorityIcons is left alone: it would put
-- icons on chairs and the like.

local _, ns = ...

local ObjectGlow = ns:GetFeature("interface", "glow")

local CVars = {}
ObjectGlow.CVars = CVars

local FIXED = {
    -- Soft interact targeting with mouse and keyboard too (Enum.SoftTargetEnableFlags.Any).
    SoftTargetInteract = "3",
    -- World objects can get a nameplate.
    SoftTargetIconGameObject = "1",
    -- Picked all around the player, not only in front.
    SoftTargetInteractArc = "2",
    -- Also objects out of reach, which glow dimmer.
    SoftTargetInteractOnlyInRange = "0",
}
local RANGE = "SoftTargetInteractRange"
local NAME_PLATE = "SoftTargetNameplateInteract"
local ICON = "SoftTargetIconInteract"

local override = ns:CreateCVarOverride(ObjectGlow)

function CVars:Apply()
    for name, value in pairs(FIXED) do
        override:Set(name, value)
    end
    override:Set(RANGE, tostring(ObjectGlow:GetSetting("range")))
end

-- The game's nameplate on the soft target, which the glow hangs on, and the
-- interaction icon on it: only on objects that glow, so NPCs and corpses get
-- neither. Blizzard reads the icon CVar when the soft target changes or its
-- nameplate is added, so it is set before the nameplate shows.
function CVars:SetGlowing(glowing)
    override:Set(NAME_PLATE, glowing and "1" or "0")
    override:Set(ICON, (glowing and ObjectGlow:GetSetting("icon")) and "1" or "0")
end

function CVars:Restore()
    override:Restore()
end
