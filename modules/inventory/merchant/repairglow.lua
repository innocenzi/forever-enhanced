-- The "repairGlow" part: the merchant's Repair All button glows while an
-- equipped item's durability is at or under the player's threshold.
--
-- The glow is a child of the button, so it hides with it: Blizzard hides the
-- repair buttons at merchants who can't repair and on the buyback tab. It keeps
-- glowing on a disabled button (not enough money): the gear is still damaged.

local _, ns = ...

local Merchant = ns:GetFeature("inventory", "merchant")

local RepairGlow = {}
Merchant.RepairGlow = RepairGlow

local GLOW_ATLAS = "bags-glow-orange"
local PULSE_SECONDS = 0.5
local PULSE_LOW_ALPHA = 0.2

-- Our glow on MerchantRepairAllButton, { frame, pulse }, once first shown.
local glow

local function CreateGlow(button)
    local frame = CreateFrame("Frame", nil, button)
    frame:SetAllPoints()
    frame:SetFrameLevel(button:GetFrameLevel() + 1)
    local texture = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    texture:SetAtlas(GLOW_ATLAS, TextureKitConstants.UseAtlasSize)
    texture:SetBlendMode("ADD")
    texture:SetPoint("CENTER")
    local pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    for order, alphas in ipairs({ { 1, PULSE_LOW_ALPHA }, { PULSE_LOW_ALPHA, 1 } }) do
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetTarget(texture)
        fade:SetFromAlpha(alphas[1])
        fade:SetToAlpha(alphas[2])
        fade:SetDuration(PULSE_SECONDS)
        fade:SetOrder(order)
    end
    return { frame = frame, pulse = pulse }
end

local function ShowGlow(shown)
    if shown and not glow then
        glow = CreateGlow(MerchantRepairAllButton)
    end
    if not glow then
        return
    end
    glow.frame:SetShown(shown)
    if shown and not glow.pulse:IsPlaying() then
        glow.pulse:Play()
    end
end

-- Whether an equipped item's durability is at or under the threshold.
local function IsWorn()
    local threshold = Merchant:GetSetting("repairGlowThreshold") / 100
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 and current / maximum <= threshold then
            return true
        end
    end
    return false
end

function RepairGlow:Refresh()
    ShowGlow(Merchant:IsPartActive("repairGlow") and IsWorn())
end

local listener = ns:CreateEventListener({
    MERCHANT_SHOW = function()
        RepairGlow:Refresh()
    end,
    -- Items wear out or get repaired.
    UPDATE_INVENTORY_DURABILITY = function()
        RepairGlow:Refresh()
    end,
    PLAYER_EQUIPMENT_CHANGED = function()
        RepairGlow:Refresh()
    end,
})

function RepairGlow:Enable()
    listener:Start()
    self:Refresh()
end

function RepairGlow:Disable()
    listener:Stop()
    self:Refresh()
end
