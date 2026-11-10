-- The glow: a few twinkling glints over the object, in the color of its
-- category. Bright when it can be used, dimmer out of reach, grey when it
-- can't be used. One frame, moved to whichever nameplate the soft target has
-- (the nameplate floats above the object, so the glints sit below it).
-- A new state shows once seen twice in a row, so the glow doesn't flicker at
-- the edge of reach.

local _, ns = ...

local ObjectGlow = ns:GetFeature("interface", "glow")

local Effect = {}
ObjectGlow.Effect = Effect

local TEXTURE = "InterfaceCooldownstar4"
local GLINT_COUNT = 6
local GLINT_SIZE = 30
local SPREAD_X = 36
local SPREAD_Y = 18
local OFFSET_Y = -40
-- Seconds for a glint to twinkle, and for the group to turn once.
local TWINKLE_SECONDS = 1.2
local TURN_SECONDS = 8

local LOCKED_COLOR = { 0.6, 0.6, 0.6 }
local ALPHAS = { ready = 1, far = 0.45, locked = 0.5 }

local frame
local glints = {}
-- The nameplate it shows on, the object's category (from CATEGORIES) and state.
local plate, category, state, pendingState
local clock = 0

local function Animate(_, elapsed)
    clock = clock + elapsed
    local color = state == "locked" and LOCKED_COLOR or category.color
    local alpha = ALPHAS[state]
    local turn = clock / TURN_SECONDS * 2 * math.pi
    for index, glint in ipairs(glints) do
        -- Spread evenly around an ellipse, each at its own point of its twinkle.
        local share = (index - 1) / GLINT_COUNT
        local angle = turn + share * 2 * math.pi
        local reach = 0.4 + 0.6 * ((index * 0.37) % 1)
        local shine = math.sin(((clock / TWINKLE_SECONDS + share) % 1) * math.pi)
        local size = GLINT_SIZE * (0.4 + 0.6 * shine)
        glint:SetPoint(
            "CENTER",
            frame,
            "CENTER",
            math.cos(angle) * SPREAD_X * reach,
            math.sin(angle) * SPREAD_Y * reach
        )
        glint:SetSize(size, size)
        glint:SetRotation(angle)
        glint:SetVertexColor(color[1], color[2], color[3], alpha * shine)
    end
end

local function Create()
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(1, 1)
    frame:Hide()
    -- Object nameplates can be faded; the glow stays as bright.
    frame:SetIgnoreParentAlpha(true)
    for index = 1, GLINT_COUNT do
        local glint = frame:CreateTexture(nil, "OVERLAY")
        glint:SetTexture(TEXTURE)
        glint:SetBlendMode("ADD")
        glints[index] = glint
    end
    frame:SetScript("OnUpdate", Animate)
end

-- Shows the glow on `newPlate` for an object of `newCategory` in `newState`.
function Effect:Show(newPlate, newCategory, newState)
    if not frame then
        Create()
    end
    if newPlate ~= plate or newCategory ~= category then
        plate, category, state, pendingState = newPlate, newCategory, newState, nil
        frame:SetParent(plate)
        -- Under the nameplate's own content, so its name stays readable.
        frame:SetFrameLevel(math.max(plate:GetFrameLevel() - 1, 0))
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", plate, "CENTER", 0, OFFSET_Y)
        frame:Show()
    elseif newState == pendingState then
        state, pendingState = newState, nil
    else
        pendingState = newState ~= state and newState or nil
    end
end

function Effect:Hide()
    if not plate then
        return
    end
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetParent(UIParent)
    plate, category, state, pendingState = nil, nil, nil, nil
end

-- The nameplate is going away: hide the glow if it's on it.
function Effect:Release(oldPlate)
    if oldPlate == plate then
        self:Hide()
    end
end

-- The nameplate the glow shows on, its category key and state; nil when hidden.
function Effect:GetShown()
    if plate then
        return plate, category.key, state
    end
end
