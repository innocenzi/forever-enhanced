-- Which frames are movable, and when to put them at their saved position.
--
-- Movable: every frame shown through ShowUIPanel (core and load-on-demand
-- panels, ours included), except full-screen ones and LootFrame (it belongs to
-- Edit Mode), plus bags. The World Map moves only while windowed: maximized, it
-- leaves the panel layout (MaximizeUIPanel) until RestoreUIPanelArea, hooked
-- too, puts it back.
-- Frames are picked up lazily, the first time they are shown. Other features'
-- windows that aren't UI panels (the swaps editor) join through
-- Windows:AddWindow.
--
-- Blizzard's panel manager re-anchors every open panel whenever one opens or
-- closes, ignoring frames the player placed; UpdateContainerFrameAnchors does
-- the same for bags. Hooks on both (and on ShowUIPanel and OnShow, for code
-- that moves a frame as it shows) re-apply the saved positions right after.
-- hooksecurefunc and HookScript can't be undone: installed once, they do
-- nothing while the feature is inactive.

local _, ns = ...

local Windows = ns:GetFeature("interface", "windows")

local Tracking = {}
Windows.Tracking = Tracking

local EXCLUDED = { LootFrame = true }

-- Per movable frame: "panel", "window" (added by another feature) or "bag".
local managed = setmetatable({}, { __mode = "k" })
-- Windows added by other features, picked up whenever the feature enables.
local added = setmetatable({}, { __mode = "k" })
local hooksInstalled = false

local function GetArea(name, frame)
    local attributes = UIPanelWindows[name]
    return attributes and attributes.area or frame:GetAttribute("UIPanelLayout-area")
end

local function IsMovablePanel(frame)
    local name = frame:GetName()
    return name ~= nil and not EXCLUDED[name] and GetArea(name, frame) ~= "full"
end

local function OnFrameShow(frame)
    if Windows:IsActive() then
        Windows.Placement:Apply(frame)
    end
end

local function Attach(frame, kind)
    if not managed[frame] then
        managed[frame] = kind
        frame:HookScript("OnShow", OnFrameShow)
    end
    Windows.Handles:Attach(frame)
end

local function ApplyShownPanels()
    for frame, kind in pairs(managed) do
        if kind ~= "bag" and frame:IsShown() then
            Windows.Placement:Apply(frame)
        end
    end
end

-- Blizzard anchors the first open bag to the screen and stacks every other bag
-- on the one before it, so moving one bag would carry the bags stacked on it.
-- Once Blizzard has placed them, stacked bags are pinned to the screen where
-- they stand, then the saved positions are applied.
local function LayOutBags()
    local bags = { ContainerFrameCombinedBags, unpack(ContainerFrameContainer.ContainerFrames) }
    local isBag, shown = {}, {}
    for _, frame in ipairs(bags) do
        isBag[frame] = true
        if frame:IsShown() then
            Attach(frame, "bag")
            table.insert(shown, frame)
        end
    end

    -- Every corner is read before anything moves.
    local corners = {}
    for _, frame in ipairs(shown) do
        local _, relativeTo = frame:GetPoint(1)
        if isBag[relativeTo] then
            corners[frame] = { frame:GetRight(), frame:GetBottom() }
        end
    end
    for frame, corner in pairs(corners) do
        Windows.Placement:Pin(frame, corner[1], corner[2])
    end

    for _, frame in ipairs(shown) do
        Windows.Placement:Apply(frame)
    end
end

local function InstallHooks()
    hooksInstalled = true
    hooksecurefunc("ShowUIPanel", function(frame)
        if Windows:IsActive() and frame and IsMovablePanel(frame) then
            Attach(frame, "panel")
            Windows.Placement:Apply(frame)
        end
    end)
    hooksecurefunc("UpdateUIPanelPositions", function()
        if Windows:IsActive() then
            ApplyShownPanels()
        end
    end)
    hooksecurefunc("RestoreUIPanelArea", function(frame)
        if Windows:IsActive() and managed[frame] then
            Windows.Placement:Apply(frame)
        end
    end)
    hooksecurefunc("UpdateContainerFrameAnchors", function()
        if Windows:IsActive() then
            LayOutBags()
        end
    end)
end

-- Picks up the windows already open and moves them to their saved position.
function Tracking:Enable()
    if not hooksInstalled then
        InstallHooks()
    end
    for frame in pairs(added) do
        Attach(frame, "window")
    end
    for name in pairs(UIPanelWindows) do
        local frame = _G[name]
        if frame and frame:IsShown() and IsMovablePanel(frame) then -- nil until its addon loads
            Attach(frame, "panel")
        end
    end
    ApplyShownPanels()
    LayOutBags()
end

-- Makes another feature's window movable like the panels: a named frame (its
-- position is saved by name) with a title bar, not shown through ShowUIPanel.
function Windows:AddWindow(frame)
    added[frame] = true
    if self:IsActive() then
        Attach(frame, "window")
    end
end
