-- Item buttons (core/itembuttons.lua): the mark of the lowest value bag items,
-- drawn on our own frame laid over the button, in the "indicator" setting's look:
--   glow   Blizzard's new item glow and pulse (NewItemTexture and
--          newitemglowAnim, ContainerFrameItemButtonTemplate), tinted red;
--   cross  a red cross, bottom-left;
--   coin   a copper coin, bottom-left.
-- Bottom-left is the lock padlock's corner (Item locking), free here since
-- locked items are never marked; top-left holds the junk coin and item marks.

local _, ns = ...

local Cheapest = ns:GetFeature("inventory", "cheapest")
local Value = Cheapest.Value

local Buttons = {}
Cheapest.Buttons = Buttons

local GLOW_ATLAS = "bags-glow-white"
local GLOW_COLOR = CreateColor(1, 0.15, 0.15)
local PULSE_SECONDS = 0.5
local PULSE_LOW_ALPHA = 0.2

-- Icon indicators, keyed by the "indicator" dropdown options ("glow" draws the glow).
local ICONS = {
    cross = { atlas = "common-icon-redx", size = 14 },
    coin = { atlas = "coin-copper", size = 14 },
}
local ICON_OFFSET_X, ICON_OFFSET_Y = 2, 2

-- Every dropdown option must have a look.
for _, entry in ipairs(Cheapest.settings) do
    if entry.key == "indicator" then
        for _, option in ipairs(entry.options) do
            assert(option == "glow" or ICONS[option], "no look for indicator: " .. option)
        end
    end
end

-- Per Blizzard item button: { frame, glow, pulse, icon }.
local decorations = setmetatable({}, { __mode = "k" })

-- GUIDs of the items to mark, gathered when the bags or what they're worth change.
local marked = {}
-- Item IDs of bag items whose data wasn't loaded then: { [itemID] = true }.
local unloaded = {}
local refreshQueued = false
-- The quest log at the last QUEST_LOG_UPDATE (ns:GetQuestLogSignature).
local lastQuestLog

local function CreateDecoration(button)
    local frame = CreateFrame("Frame", nil, button)
    frame:SetAllPoints()
    frame:SetFrameLevel(button:GetFrameLevel() + 1)

    local glow = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    glow:SetAtlas(GLOW_ATLAS, TextureKitConstants.UseAtlasSize)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(GLOW_COLOR:GetRGB())
    glow:SetPoint("CENTER")

    local pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("REPEAT")
    for order, alphas in ipairs({ { 1, PULSE_LOW_ALPHA }, { PULSE_LOW_ALPHA, 1 } }) do
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetTarget(glow)
        fade:SetFromAlpha(alphas[1])
        fade:SetToAlpha(alphas[2])
        fade:SetDuration(PULSE_SECONDS)
        fade:SetOrder(order)
    end

    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 5)
    icon:SetPoint("BOTTOMLEFT", ICON_OFFSET_X, ICON_OFFSET_Y)

    return { frame = frame, glow = glow, pulse = pulse, icon = icon }
end

local function ShowMark(decoration, indicator)
    local icon = ICONS[indicator]
    decoration.glow:SetShown(icon == nil)
    decoration.icon:SetShown(icon ~= nil)
    if icon then
        decoration.pulse:Stop()
        decoration.icon:SetAtlas(icon.atlas)
        decoration.icon:SetSize(icon.size, icon.size)
    elseif not decoration.pulse:IsPlaying() then
        decoration.pulse:Play()
    end
    decoration.frame:Show()
end

local function Update(button, itemLocation, guid)
    local shown = guid ~= nil and marked[guid] == true and ns.Containers:IsBag((itemLocation:GetBagAndSlot()))
    local decoration = decorations[button]
    if shown then
        if not decoration then
            decoration = CreateDecoration(button)
            decorations[button] = decoration
        end
        ShowMark(decoration, Cheapest:GetSetting("indicator"))
    elseif decoration then
        decoration.frame:Hide()
    end
end

-- Item buttons gather the marks again only when told something changed: an
-- item's data loading is such a change. Once per frame, however many load.
local function QueueRefresh()
    if refreshQueued then
        return
    end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if Cheapest:IsActive() then
            ns:RefreshItemButtons()
        end
    end)
end

local listener = ns:CreateEventListener({
    GET_ITEM_INFO_RECEIVED = function(_, itemID)
        if unloaded[itemID] then
            unloaded[itemID] = nil
            QueueRefresh()
        end
    end,
    -- What the "ignore" options leave out changes. Next frame, once the
    -- features keeping that state have read the event (a learned recipe).
    NEW_RECIPE_LEARNED = function()
        if Cheapest:GetSetting("ignore").reagents then
            QueueRefresh()
        end
    end,
    SKILL_LINES_CHANGED = function()
        if Cheapest:GetSetting("ignore").reagents then
            QueueRefresh()
        end
    end,
    ACTIONBAR_SLOT_CHANGED = function()
        if Cheapest:GetSetting("ignore").actionBars then
            QueueRefresh()
        end
    end,
    -- Objective progress doesn't change which items quests ask for.
    QUEST_LOG_UPDATE = function()
        local questLog = ns:GetQuestLogSignature()
        if questLog ~= lastQuestLog then
            lastQuestLog = questLog
            if Cheapest:GetSetting("ignore").questItems then
                QueueRefresh()
            end
        end
    end,
})

function Buttons:Enable()
    lastQuestLog = ns:GetQuestLogSignature()
    listener:Start()
end

function Buttons:Disable()
    listener:Stop()
    marked, unloaded = {}, {}
    for _, decoration in pairs(decorations) do
        decoration.frame:Hide()
    end
end

ns:AddItemButtonHandler(Cheapest, {
    Prepare = function()
        local show = not Cheapest:GetSetting("onlyWhenFull") or Value:IsFull()
        if show then
            marked, unloaded = Value:Collect()
        else
            marked, unloaded = {}, {}
        end
    end,
    Update = Update,
})
