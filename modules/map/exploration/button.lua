-- The button: round like Blizzard's top right map buttons (WorldMapTrackingPinButtonTemplate),
-- in the column under them, in their strata (HIGH: over map.seamless's view too). The map's
-- icon, greyed until the map in view is fully explored, checked once it is; hidden on a map
-- without anything to explore. Its tooltip lists the map's parts, explored or not.
--
-- The map in view is checked a few times a second while Blizzard's map shows (a frame of
-- ours under it): map.seamless's view changes it without Blizzard's map knowing.

local _, ns = ...

local Exploration = ns:GetFeature("map", "exploration")
local Seamless = ns:GetFeature("map", "seamless")
local Progress = Exploration.Progress

local Button = {}
Exploration.Button = Button

local ICON = "Interface\\Icons\\INV_Misc_Map_01"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- The tooltip's list, coloured as the achievement window's criteria (the exploration achievements'
-- areas): done in green, the rest in grey, each after a mark of the same size (the ready check's),
-- so the names line up.
local DONE_MARK = "|A:UI-LFG-ReadyMark:14:14|a "
local MISSING_MARK = "|A:UI-LFG-DeclineMark:14:14|a "
local DONE_COLOR = CreateColor(0, 1, 0)
local MISSING_COLOR = CreateColor(0.6, 0.6, 0.6)
local CHECK_SECONDS = 0.1

local installed = false
local button, icon, check, watcher
local mapID -- the map in view, its progress shown
local hovered = false
local sinceCheck = 0

-- The map in view: the seamless view's while it's up, else Blizzard's.
local function MapInView()
    return Seamless:GetViewedMap() or WorldMapFrame:GetMapID()
end

local function ShowTooltip()
    local progress = mapID and Progress:Of(mapID)
    if not progress then
        GameTooltip:Hide()
        return
    end
    local L = ns.L
    local info = C_Map.GetMapInfo(mapID)
    -- (as Blizzard's map pin button beside it: its title, a value line in gold with the value in
    -- white, a blank line, then the list)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(info and info.name or UNKNOWN, HIGHLIGHT_FONT_COLOR:GetRGB())
    local count = HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(progress.explored .. "/" .. progress.total)
    GameTooltip:AddLine(L["map.exploration.explored." .. progress.kind]:format(count), NORMAL_FONT_COLOR:GetRGB())
    GameTooltip:AddLine(" ")
    for _, entry in ipairs(progress.entries) do
        local done = entry.explored == entry.total
        local name = (done and DONE_MARK or MISSING_MARK) .. entry.name
        local r, g, b = (done and DONE_COLOR or MISSING_COLOR):GetRGB()
        if entry.area then
            GameTooltip:AddLine(name, r, g, b)
        else
            GameTooltip:AddDoubleLine(name, entry.explored .. "/" .. entry.total, r, g, b, r, g, b)
        end
    end
    GameTooltip:Show()
end

-- Shows the map in view's progress (`force`: again, though it's the same map).
local function Update(force)
    local current = MapInView()
    if current == mapID and not force then
        return
    end
    mapID = current
    local progress = mapID and Progress:Of(mapID)
    button:SetShown(progress ~= nil)
    if progress then
        local complete = progress.explored == progress.total
        icon:SetDesaturated(not complete)
        icon:SetAlpha(complete and 1 or 0.6)
        check:SetShown(complete)
    end
    if hovered then
        ShowTooltip()
    end
end

local listener = ns:CreateEventListener({
    MAP_EXPLORATION_UPDATED = function()
        Progress:Reset()
        Update(true)
    end,
})

-- Under the lowest of Blizzard's top right buttons (spaced by their size), else where the first goes.
local function Anchor()
    local map = WorldMapFrame
    local above = map.WorldMapTrackingPinButton or map.WorldMapTrackingOptionsButton
    button:ClearAllPoints()
    if above then
        button:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT")
    else
        button:SetPoint("TOPRIGHT", map:GetCanvasContainer(), "TOPRIGHT", -4, -2)
    end
end

local function Install()
    installed = true
    button = CreateFrame("Button", nil, WorldMapFrame)
    button:SetFrameStrata("HIGH")
    button:SetSize(32, 32)
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(25, 25)
    background:SetPoint("TOPLEFT", 3, -4)
    icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -6)
    local mask = button:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    local border = button:CreateTexture(nil, "OVERLAY", nil, 1)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    check = button:CreateTexture(nil, "OVERLAY", nil, 2)
    check:SetAtlas("UI-LFG-ReadyMark")
    check:SetSize(14, 14)
    check:SetPoint("CENTER", icon, "BOTTOMRIGHT", -2, 2)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button:SetScript("OnEnter", function()
        hovered = true
        ShowTooltip()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        GameTooltip:Hide()
    end)
    Anchor()
    -- (Blizzard's map's child: it only runs while the map shows)
    watcher = CreateFrame("Frame", nil, WorldMapFrame)
    watcher:SetScript("OnUpdate", function(_, elapsed)
        sinceCheck = sinceCheck + elapsed
        if sinceCheck >= CHECK_SECONDS then
            sinceCheck = 0
            Update()
        end
    end)
    watcher:SetScript("OnShow", function()
        Update(true)
    end)
end

function Button:Enable()
    if not installed then
        Install()
    end
    listener:Start()
    Progress:Reset()
    watcher:Show()
    Update(true)
end

function Button:Disable()
    listener:Stop()
    watcher:Hide()
    button:Hide()
    mapID = nil
    if hovered then
        hovered = false
        GameTooltip:Hide()
    end
end

-- The button, for the tests.
function Button:GetFrame()
    return button
end
