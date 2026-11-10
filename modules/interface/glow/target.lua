-- Follows the soft interact target ("softinteract"): whether it is a world
-- object, its category (see CATEGORIES in feature.lua), whether it can be used,
-- and its nameplate. Checked on every change and on a short ticker while an
-- object glows (the player walks in and out of reach without an event).
-- CVars can't change in combat, so the nameplate is hidden as combat starts
-- (otherwise lootable corpses keep an empty one) and nothing glows until it ends.

local _, ns = ...

local ObjectGlow = ns:GetFeature("interface", "glow")

local Target = {}
ObjectGlow.Target = Target

local UNIT = "softinteract"
local TICK_SECONDS = 0.15

local categoriesByKey = {}
-- Cursor file IDs: { category, unable }.
local cursorsByFileID = {}
for _, category in ipairs(ObjectGlow.CATEGORIES) do
    categoriesByKey[category.key] = category
    for _, name in ipairs(category.cursors) do
        for _, prefix in ipairs({ "", "Unable" }) do
            -- nil for a cursor this client doesn't have.
            local fileID = GetFileIDFromPath("Interface\\Cursor\\" .. prefix .. name)
            if fileID then
                cursorsByFileID[fileID] = { category = category, unable = prefix ~= "" }
            end
        end
    end
end
local OTHER = categoriesByKey.other
local QUEST = categoriesByKey.quest

local probe
local ticker
-- Nameplate tokens shown, to find the soft target's when the unit token doesn't give it.
local namePlateUnits = {}

-- From an atlas or path: the category whose keyword it holds, and whether it is an "Unable" cursor.
local function ReadCursorName(name)
    name = name:lower()
    local unable = name:find("unable", 1, true) ~= nil
    for _, category in ipairs(ObjectGlow.CATEGORIES) do
        if category.keyword and name:find(category.keyword, 1, true) then
            return category, unable
        end
    end
    return OTHER, unable
end

-- The object's category and whether it can't be used now.
local function ReadCursor()
    if not probe then
        probe = UIParent:CreateTexture()
        probe:Hide()
    end
    if not SetUnitCursorTexture(probe, UNIT) then
        return OTHER, false
    end
    local texture = probe:GetTexture()
    local known = cursorsByFileID[texture]
    if known then
        return known.category, known.unable
    end
    local name = probe:GetAtlas() or texture
    if type(name) ~= "string" then
        return OTHER, false
    end
    return ReadCursorName(name)
end

-- The soft target's category and state ("ready", "far", or "locked": in
-- reach but can't be used, e.g. a skill too low) when it should glow.
local function Read()
    if not UnitIsGameObject(UNIT) then
        return nil
    end
    local category, unable = ReadCursor()
    if category == OTHER and C_QuestLog.UnitIsRelatedToActiveQuest(UNIT) then
        category = QUEST
    end
    if not ObjectGlow:GetSetting(category.key) then
        return nil
    end
    if not UnitIsInInteractRange(UNIT) then
        return category, "far"
    end
    return category, unable and "locked" or "ready"
end

local function FindNamePlate()
    local plate = C_NamePlate.GetNamePlateForUnit(UNIT)
    if plate then
        return plate
    end
    -- Only the soft target's world object has a nameplate.
    for unit in pairs(namePlateUnits) do
        if UnitIsGameObject(unit) then
            return C_NamePlate.GetNamePlateForUnit(unit)
        end
    end
end

local function Clear()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    ObjectGlow.Effect:Hide()
end

local function Refresh()
    Target:Refresh()
end

function Target:Refresh()
    if InCombatLockdown() then
        Clear()
        return
    end
    local category, state = Read()
    ObjectGlow.CVars:SetGlowing(category ~= nil)
    if not category then
        Clear()
        return
    end
    ticker = ticker or C_Timer.NewTicker(TICK_SECONDS, Refresh)
    -- Without a nameplate yet, the glow follows with NAME_PLATE_UNIT_ADDED.
    local plate = FindNamePlate()
    if plate then
        ObjectGlow.Effect:Show(plate, category, state)
    else
        ObjectGlow.Effect:Hide()
    end
end

local listener = ns:CreateEventListener({
    PLAYER_SOFT_INTERACT_CHANGED = Refresh,
    NAME_PLATE_UNIT_ADDED = function(_, unit)
        namePlateUnits[unit] = true
        Refresh()
    end,
    -- The plate is about to be recycled for another unit.
    NAME_PLATE_UNIT_REMOVED = function(_, unit)
        namePlateUnits[unit] = nil
        ObjectGlow.Effect:Release(C_NamePlate.GetNamePlateForUnit(unit))
    end,
    -- Combat is about to start: the last moment to hide the nameplate.
    PLAYER_REGEN_DISABLED = function()
        Clear()
        ObjectGlow.CVars:SetGlowing(false)
    end,
    PLAYER_REGEN_ENABLED = Refresh,
    -- An object may become (or stop being) part of a quest.
    QUEST_LOG_UPDATE = Refresh,
    -- Account-synced settings can overwrite ours on login.
    PLAYER_ENTERING_WORLD = function()
        ObjectGlow.CVars:Apply()
        Refresh()
    end,
})

function Target:Enable()
    listener:Start()
    self:Refresh()
end

function Target:Disable()
    listener:Stop()
    wipe(namePlateUnits)
    Clear()
end
