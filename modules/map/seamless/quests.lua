-- Every quest of the log on a continent's map. On a continent Blizzard's quest
-- pins (QuestDataProviderMixin) show only the super-tracked quest, though the
-- game places every quest there (C_QuestLog.GetQuestsOnMap); and the stitched
-- map keeps a continent underneath until the view closes in on one zone. So
-- this provider is Blizzard's own, with its pins, tooltips, highlights and
-- spacing, on its own pin template: on a continent it shows the quests
-- Blizzard's leaves out, as Blizzard's shows them on a zone.

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")

local Quests = {}
Seamless.Quests = Quests

local PIN_TEMPLATE = "ForeverEnhancedQuestPinTemplate"

local provider = CreateFromMixins(QuestDataProviderMixin)
local added = false

function provider:GetPinTemplate()
    return PIN_TEMPLATE
end

-- (Blizzard's never drops its super tracking callback: it also runs once the provider is off the map)
function provider:RefreshAllData(...)
    local map = self:GetMap()
    if not map then
        return
    end
    local info = C_Map.GetMapInfo(map:GetMapID())
    if not info or info.mapType ~= Enum.UIMapType.Continent or not Seamless.db.quests then
        self:RemoveAllData()
        return
    end
    QuestDataProviderMixin.RefreshAllData(self, ...)
end

-- As on a zone, but not the quest Blizzard's own shows on a continent (the super-tracked one,
-- or the one whose details are open, which it'd also add as a waypoint).
function provider:ShouldShowQuest(questID, _, ...)
    if questID == (QuestMapFrame_GetFocusedQuestID() or C_SuperTrack.GetSuperTrackedQuestID()) then
        return false
    end
    return QuestDataProviderMixin.ShouldShowQuest(self, questID, Enum.UIMapType.Zone, ...)
end

function provider:OnRemoved(map)
    EventRegistry:UnregisterCallback("Supertracking.OnChanged", self)
    QuestDataProviderMixin.OnRemoved(self, map)
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
