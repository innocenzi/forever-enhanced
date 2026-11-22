-- Every quest of the log on Blizzard's continent maps. On a continent Blizzard's
-- quest pins show only the super-tracked quest (or the one whose details are
-- open), though the game places every quest there (C_QuestLog.GetQuestsOnMap):
-- this shows the others, as the seamless view does (pins.lua), with Blizzard's quest
-- marker and tooltip. A click follows the quest and opens its zone.
-- Our own pins and provider, as map.friends', not Blizzard's quest pins: those run
-- Blizzard's quest code from ours (its refresh fills a quest cache Blizzard's
-- own provider reads, hovering one writes the quest highlight the quest log
-- reads, clicking one super-tracks), which would taint Blizzard's map, quest log
-- and tracker (feature.lua, TAINT). Its events come from a listener of ours, not
-- through the map. The quest log's hovered quest (POIButtonHighlightManager) is
-- only read, never written.
-- Also what the view's markers share with these pins: which quests show, their
-- marker, tooltip and click.

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")
local Geometry, Waypoint = Seamless.Geometry, Seamless.Waypoint

local Quests = {}
Seamless.Quests = Quests

local PIN_TEMPLATE = "ForeverEnhancedQuestPinTemplate"
-- How often the pins follow the quest log's hovered quest.
local HIGHLIGHT_TICK = 0.1

local provider = CreateFromMixins(MapCanvasDataProviderMixin)
local added = false

-- Blizzard's quest marker (its POI button, Blizzard_POIButton), drawn by us: a background
-- by the quest's classification (its super-tracked look for the quest followed), and over
-- it the quest in progress, or ready to turn in. Each at its atlas's own size, as Blizzard's.
local BASIC = {
    background = "UI-QuestPoi-QuestNumber",
    turnIn = "UI-QuestIcon-TurnIn-Normal",
    highlight = "UI-QuestPoi-InnerGlow",
}
local CAMPAIGN = {
    background = "UI-QuestPoiCampaign-QuestNumber",
    turnIn = "UI-QuestPoiCampaign-QuestBangTurnIn",
    highlight = "UI-QuestPoiCampaign-InnerGlow",
}
local MARKERS = {
    [Enum.QuestClassification.Legendary] = {
        background = "UI-QuestPoiLegendary-QuestNumber",
        turnIn = "UI-QuestPoiLegendary-QuestBangTurnIn",
        highlight = "UI-QuestPoiLegendary-InnerGlow",
    },
    [Enum.QuestClassification.Campaign] = CAMPAIGN,
    [Enum.QuestClassification.Calling] = {
        background = CAMPAIGN.background,
        turnIn = "UI-DailyQuestPoiCampaign-QuestBangTurnIn",
        highlight = CAMPAIGN.highlight,
    },
    [Enum.QuestClassification.Recurring] = {
        background = "UI-QuestPoiRecurring-QuestNumber",
        turnIn = "UI-QuestPoiRecurring-QuestBangTurnIn",
        highlight = "UI-QuestPoiRecurring-InnerGlow",
    },
    [Enum.QuestClassification.Important] = {
        background = "UI-QuestPoiImportant-QuestNumber",
        turnIn = "UI-QuestPoiImportant-QuestBangTurnIn",
        highlight = "UI-QuestPoiImportant-InnerGlow",
    },
    [Enum.QuestClassification.Meta] = {
        background = "UI-QuestPoiWrapper-QuestNumber",
        turnIn = "UI-QuestPoiWrapper-QuestBangTurnIn",
        highlight = "UI-QuestPoiWrapper-InnerGlow",
    },
}

-- Whether quests show on the map at all: the map's own filter, "Quest Objectives" (as Blizzard's).
function Quests:AreShown()
    return GetCVarBool("questPOI")
end

-- Whether a quest of the log gets a marker, as on Blizzard's map (its ShouldShowQuest): its
-- data loaded, and not a bonus objective.
function Quests:IsQuestShown(questID)
    return HaveQuestData(questID) and not QuestUtils_IsQuestBonusObjective(questID)
end

-- Whether a quest the game places on a map (C_QuestLog.GetQuestsOnMap's entry) gets a marker
-- there: not a map indicator, and shown.
function Quests:ShouldShow(info)
    return not info.isMapIndicatorQuest and self:IsQuestShown(info.questID)
end

-- Follows the quest (super-tracks it, watched first if it isn't), as a click on Blizzard's
-- own marker does: shielded from Blizzard's objective tracker and quest log, as every
-- watch or super tracking change of ours.
function Quests:Follow(questID)
    ns:ShieldObjectiveTracker(function()
        if not QuestUtils_IsQuestWatched(questID) then
            C_QuestLog.AddQuestWatch(questID)
        end
        C_SuperTrack.SetSuperTrackedQuestID(questID)
    end)
end

-- A click on a quest's marker, as on Blizzard's (POIButtonMixin:OnClick): its link in chat
-- (Shift Click with the chat box open), the quest no longer watched (Shift Click on a watched
-- one), or the quest followed. Returns "linked", "unwatched", "followed", or "refused", saying
-- why: in combat, where changing watches or super tracking from our code has Blizzard's open
-- map put its pins up from our code, which the game blocks there.
function Quests:Click(questID)
    if ChatFrameUtil.TryInsertQuestLinkForQuestID(questID) then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        return "linked"
    end
    if InCombatLockdown() then
        ns:Error(ERR_NOT_IN_COMBAT)
        return "refused"
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if IsShiftKeyDown() and QuestUtils_IsQuestWatched(questID) then
        if QuestUtil.CanRemoveQuestWatch() then
            ns:ShieldObjectiveTracker(function()
                C_QuestLog.RemoveQuestWatch(questID)
            end)
        end
        return "unwatched"
    end
    self:Follow(questID)
    return "followed"
end

-- Whether a click with these modifiers is one for the marker (none, or the chat link's).
function Quests:IsMarkerClick()
    return not IsModifierKeyDown() or IsModifiedClick("CHATLINK")
end

-- The quest the quest log's hovered entry lights up on the map, if any (only read).
function Quests:GetLogHighlight()
    return POIButtonHighlightManager:GetQuestID()
end

-- Blizzard's quest tooltip (QuestPinMixin:OnMouseEnter's lines, without its highlight and
-- events) at the cursor, for `owner`. Returns whether it showed (the quest's data loaded).
function Quests:ShowTooltip(owner, questID)
    local title = C_QuestLog.GetTitleForQuestID(questID)
    if not title then
        return false
    end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT", 5, 2)
    GameTooltip:SetText(SetQuestTitleLevelAndDifficultyColor(questID, title))
    QuestUtils_AddQuestTypeToTooltip(GameTooltip, questID, NORMAL_FONT_COLOR)
    GameTooltip_CheckAddQuestTimeToTooltip(GameTooltip, questID)
    local waypointText = questID == C_SuperTrack.GetSuperTrackedQuestID() and C_QuestLog.GetNextWaypointText(questID)
    if waypointText then
        GameTooltip_AddColoredLine(GameTooltip, QUEST_DASH .. waypointText, HIGHLIGHT_FONT_COLOR)
    elseif not C_QuestLog.IsComplete(questID) then
        local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
        if logIndex then
            local drops = GetNumQuestItemDrops(logIndex)
            local count = drops > 0 and drops or GetNumQuestLeaderBoards(logIndex)
            for index = 1, count do
                local text, _, finished
                if drops > 0 then
                    text, _, finished = GetQuestLogItemDrop(index, logIndex)
                else
                    text, _, finished = GetQuestLogLeaderBoard(index, logIndex)
                end
                if text and not finished then
                    GameTooltip:AddLine(QUEST_DASH .. text, 1, 1, 1, true)
                end
            end
        end
    end
    GameTooltip:Show()
    return true
end

-- The marker's textures on `frame` (once): Background, Icon, and Highlight (shown on hover).
function Quests:BuildMarker(frame)
    frame.Background = frame:CreateTexture(nil, "ARTWORK", nil, 0)
    frame.Background:SetPoint("CENTER")
    frame.Icon = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    frame.Icon:SetPoint("CENTER")
    frame.Highlight = frame:CreateTexture(nil, "OVERLAY")
    frame.Highlight:SetPoint("CENTER")
    frame.Highlight:SetBlendMode("ADD")
    frame.Highlight:Hide()
end

-- The marker for `questID` on `frame` (BuildMarker's), the quest followed or not.
function Quests:StyleMarker(frame, questID, followed)
    local marker = MARKERS[C_QuestInfoSystem.GetQuestClassification(questID)] or BASIC
    frame.Background:SetAtlas(marker.background .. (followed and "-SuperTracked" or ""), true)
    frame.Background:SetVertexColor(1, 1, 1)
    if C_QuestLog.IsComplete(questID) then
        frame.Icon:SetAtlas(marker.turnIn, true)
    else
        frame.Icon:SetAtlas(followed and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow", true)
    end
    frame.Icon:Show()
    frame.Highlight:SetAtlas(marker.highlight, true)
end

function provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

-- The pins for the continent shown. Not in combat, where the map can't set up new pins'
-- mouse input from our code: they catch up once it ends.
function provider:RefreshAllData()
    local map = self:GetMap()
    if not map then
        return
    end
    local mapID = map:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not info or info.mapType ~= Enum.UIMapType.Continent or not Seamless.db.quests or not Quests:AreShown() then
        self:RemoveAllData()
        return
    end
    if InCombatLockdown() then
        return
    end
    self:RemoveAllData()
    -- (with a quest's details open, the map shows only that one, Blizzard's)
    if QuestMapFrame_GetFocusedQuestID() then
        return
    end
    -- (the one Blizzard's own shows on a continent)
    local shown = C_SuperTrack.GetSuperTrackedQuestID()
    for _, quest in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
        if quest.questID ~= shown and Quests:ShouldShow(quest) then
            map:AcquirePin(PIN_TEMPLATE, quest.questID, quest.x, quest.y)
        end
    end
end

-- (a map change in combat: the last continent's pins don't stay on the new map)
function provider:OnMapChanged()
    self:RemoveAllData()
    self:RefreshAllData()
end

-- The quest log's hovered quest lights its pin up, as Blizzard's.
local highlighter = CreateFrame("Frame")
highlighter:Hide()
local sinceHighlight, logHighlight = 0, nil
highlighter:SetScript("OnUpdate", function(_, elapsed)
    sinceHighlight = sinceHighlight + elapsed
    if sinceHighlight < HIGHLIGHT_TICK then
        return
    end
    sinceHighlight = 0
    local questID = Quests:GetLogHighlight()
    if questID == logHighlight then
        return
    end
    logHighlight = questID
    for pin in WorldMapFrame:EnumeratePinsByTemplate(PIN_TEMPLATE) do
        pin.Highlight:SetShown(pin.hovered or pin.questID == questID)
    end
end)

local listener = ns:CreateEventListener({
    QUEST_LOG_UPDATE = function()
        provider:RefreshAllData()
    end,
    QUEST_POI_UPDATE = function()
        provider:RefreshAllData()
    end,
    SUPER_TRACKING_CHANGED = function()
        provider:RefreshAllData()
    end,
    PLAYER_REGEN_ENABLED = function()
        provider:RefreshAllData()
    end,
    CVAR_UPDATE = function(_, name)
        if name and name:lower() == "questpoi" then
            provider:RefreshAllData()
        end
    end,
})

function provider:OnShow()
    listener:Start()
    logHighlight = nil
    highlighter:Show()
end

function provider:OnHide()
    listener:Stop()
    highlighter:Hide()
end

-- A click on a pin: the quest followed, and Blizzard's map opened on its zone (out of
-- combat: refused in it), as the seamless view's markers do. Our own script, in place of the
-- canvas's (OnPinMouseUp: its global pin handlers would run from our pin's click).
local function OnPinMouseUp(pin, button, upInside)
    if not upInside or button ~= "LeftButton" then
        return
    end
    local mapID = pin:GetMap():GetMapID()
    -- (in the map pin's mode, a map pin there, as a click on Blizzard's quest pins places)
    if Waypoint:IsPinMode() then
        Waypoint:PlaceOn(mapID, pin.mapX, pin.mapY)
        return
    end
    if not Quests:IsMarkerClick() then
        return
    end
    -- (first: following the quest refreshes the pins, this one then Blizzard's, the pin let go)
    local zone = Geometry:Rect(mapID) and Geometry:ZoneAt(Geometry:ToWorld(mapID, pin.mapX, pin.mapY))
    if Quests:Click(pin.questID) == "followed" and zone then
        C_Map.OpenWorldMap(zone)
    end
end

-- The pin: Blizzard's quest marker and tooltip. quests.xml mixes it into the template.
local PinMixin = CreateFromMixins(MapCanvasPinMixin)
Quests.PinMixin = PinMixin

function PinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_ACTIVE_QUEST")
    self:SetScalingLimits(1, 1.0, 1.2)
    self:SetScript("OnMouseUp", OnPinMouseUp)
    Quests:BuildMarker(self)
end

-- (as map.friends' pins: the game blocks the canvas setting a pin's mouse input in combat
-- from our provider's code; ours keeps what it had)
function PinMixin:CheckMouseButtonPassthrough(...)
    if not InCombatLockdown() then
        MapCanvasPinMixin.CheckMouseButtonPassthrough(self, ...)
    end
end

function PinMixin:OnAcquired(questID, x, y)
    self.questID, self.mapX, self.mapY = questID, x, y
    self.hovered = false
    self:SetPosition(x, y)
    -- (never the quest followed: Blizzard's shows that one)
    Quests:StyleMarker(self, questID, false)
    self.Highlight:SetShown(questID == Quests:GetLogHighlight())
end

function PinMixin:OnMouseEnter()
    self.hovered = true
    self.Highlight:Show()
    Quests:ShowTooltip(self, self.questID)
end

function PinMixin:OnMouseLeave()
    self.hovered = false
    self.Highlight:SetShown(self.questID == Quests:GetLogHighlight())
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

function Quests:Enable()
    if not added then
        added = true
        WorldMapFrame:AddDataProvider(provider)
    end
    if WorldMapFrame:IsShown() then
        provider:OnShow()
        provider:RefreshAllData()
    end
end

function Quests:Disable()
    if added then
        added = false
        if WorldMapFrame:IsShown() then
            provider:OnHide()
        end
        WorldMapFrame:RemoveDataProvider(provider)
    end
end

function Quests:Refresh()
    if added and WorldMapFrame:IsShown() then
        provider:RefreshAllData()
    end
end
