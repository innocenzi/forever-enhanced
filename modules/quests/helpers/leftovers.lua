-- Leftover quest items (the "leftovers" part): a quest item is a leftover once
-- every quest known to use it is completed and none is in the log.
--
-- The client has no quest database (no objectives, no required items), so
-- which quests use an item is learned as the player plays, account-wide, and
-- only for quest items (meat or cloth a quest asks for have other uses):
--   * the turn-in window lists the items a quest takes (QUEST_PROGRESS);
--   * the log's item objectives name the items they need (Needs, by name),
--     matched against the quest items in the bags;
--   * items that arrive with an accepted quest: counts taken when the quest
--     window opens (QUEST_DETAIL), compared for a moment after QUEST_ACCEPTED
--     (quests accepted without the window, like escorts, are missed);
--   * items that start a quest (the bag API knows which).
-- Repeatable quests are never flagged completed, so their items never show.
--
-- Leftovers in the bags show a check mark, bottom-left (top-left holds the
-- item marks, the top the lock, bottom-right the count), on our own frame.

local _, ns = ...

local Helpers = ns:GetFeature("quests", "helpers")

local Leftovers = {}
Helpers.Leftovers = Leftovers

-- How long after QUEST_ACCEPTED new quest items count as given by the quest.
local GIVEN_SECONDS = 2

local MARK_ATLAS = "UI-LFG-ReadyMark"
local MARK_SIZE = 14

-- The account store: items[itemID] = { [questID] = true }, titles[questID] =
-- the quest's title when last seen (the client knows titles of quests in the
-- log only).
local function GetStore()
    local store = Helpers:GetAccountStore()
    store.items = store.items or {}
    store.titles = store.titles or {}
    return store
end

local function IsQuestItem(itemID)
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == Enum.ItemClass.Questitem
end

-- Records that quest `questID` uses item `itemID`, if it's a quest item.
local function Link(itemID, questID, title)
    if not itemID or not questID or questID == 0 or not IsQuestItem(itemID) then
        return
    end
    local store = GetStore()
    store.items[itemID] = store.items[itemID] or {}
    store.items[itemID][questID] = true
    title = title or C_QuestLog.GetTitleForQuestID(questID)
    if title and title ~= "" then
        store.titles[questID] = title
    end
end

-- Public API: the quests of a leftover item, sorted, or nil while it may still be needed.
function Leftovers:GetCompletedQuests(itemID)
    local quests = itemID and GetStore().items[itemID]
    if not quests or next(quests) == nil then
        return nil
    end
    local completed = {}
    for questID in pairs(quests) do
        if C_QuestLog.GetLogIndexForQuestID(questID) or not C_QuestLog.IsQuestFlaggedCompleted(questID) then
            return nil
        end
        table.insert(completed, questID)
    end
    table.sort(completed)
    return completed
end

-- The quest's title, or nil when it was never seen.
function Leftovers:GetTitle(questID)
    local title = C_QuestLog.GetTitleForQuestID(questID)
    if title and title ~= "" then
        return title
    end
    return GetStore().titles[questID]
end

-- Bag mark --------------------------------------------------------------------

-- Per Blizzard item button: our mark frame.
local marks = setmetatable({}, { __mode = "k" })

local function CreateMark(button)
    local frame = CreateFrame("Frame", nil, button)
    frame:SetAllPoints()
    frame:SetFrameLevel(button:GetFrameLevel() + 1)
    local icon = frame:CreateTexture(nil, "OVERLAY", nil, 5)
    icon:SetAtlas(MARK_ATLAS)
    icon:SetSize(MARK_SIZE, MARK_SIZE)
    icon:SetPoint("BOTTOMLEFT", 2, 2)
    return frame
end

local function ShowMark(button, shown)
    local mark = marks[button]
    if shown and not mark then
        mark = CreateMark(button)
        marks[button] = mark
    end
    if mark then
        mark:SetShown(shown)
    end
end

ns:AddItemButtonHandler(Helpers, {
    part = "leftovers",
    Update = function(button, itemLocation, guid)
        local shown = guid ~= nil
            and Helpers:GetSetting("leftoverMark")
            and Leftovers:GetCompletedQuests(C_Item.GetItemID(itemLocation)) ~= nil
        ShowMark(button, shown)
    end,
})

-- Learning --------------------------------------------------------------------

-- Counts of quest items taken when the quest window opened, until a moment
-- after it closes (the window closes before the server confirms the quest),
-- and the quest accepted since: { questID, counts, expires }.
local detailCounts
local detailExpires
local accepted
-- The leftovers in the containers at the last scan ("id,id"): the bag marks
-- refresh when it changes.
local lastLeftovers = ""
local queued = false

local function GetContainerIDs()
    local containerIDs = {}
    for _, bagID in ipairs(ns.Containers.BAG_IDS) do
        table.insert(containerIDs, bagID)
    end
    for _, bagID in ipairs(ns.Containers:GetBankContainerIDs()) do
        table.insert(containerIDs, bagID)
    end
    return containerIDs
end

-- Calls func(bagID, slot, info) for each quest item in the bags (and the bank, while open).
local function ForEachQuestItem(containerIDs, func)
    ns.Containers:ForEachSlot(containerIDs, function(bagID, slot)
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and IsQuestItem(info.itemID) then
            func(bagID, slot, info)
        end
    end)
end

local function CountQuestItems()
    local counts = {}
    ForEachQuestItem(ns.Containers.BAG_IDS, function(_, _, info)
        counts[info.itemID] = (counts[info.itemID] or 0) + info.stackCount
    end)
    return counts
end

-- Links the quest items that arrived since the quest window opened to the accepted quest.
local function LinkGiven()
    if not accepted then
        return
    end
    if GetTime() > accepted.expires then
        accepted = nil
        return
    end
    for itemID, count in pairs(CountQuestItems()) do
        if count > (accepted.counts[itemID] or 0) then
            Link(itemID, accepted.questID)
        end
    end
end

local function Scan()
    queued = false
    if not Helpers:IsPartActive("leftovers") then
        return
    end
    LinkGiven()

    local leftovers = {}
    ForEachQuestItem(GetContainerIDs(), function(bagID, slot, info)
        local questInfo = C_Container.GetContainerItemQuestInfo(bagID, slot)
        if questInfo and questInfo.questID then
            Link(info.itemID, questInfo.questID)
        end
        for _, need in ipairs(info.itemName and Helpers.Needs:Find(info.itemName) or {}) do
            Link(info.itemID, need.questID, need.title)
        end
        if Leftovers:GetCompletedQuests(info.itemID) then
            leftovers[info.itemID] = true
        end
    end)

    local ids = {}
    for itemID in pairs(leftovers) do
        table.insert(ids, tostring(itemID))
    end
    table.sort(ids)
    local signature = table.concat(ids, ",")
    if signature ~= lastLeftovers then
        lastLeftovers = signature
        ns:RefreshItemButtons()
    end
end

local function Request()
    if not queued then
        queued = true
        C_Timer.After(0, Scan)
    end
end

-- The turn-in window lists the items the quest takes.
local function OnQuestProgress()
    local questID = GetQuestID()
    for index = 1, GetNumQuestItems() do
        local link = GetQuestItemLink("required", index)
        if link then
            Link(C_Item.GetItemInfoInstant(link), questID, GetTitleText())
        end
    end
    Request()
end

local listener = ns:CreateEventListener({
    QUEST_DETAIL = function()
        detailCounts, detailExpires = CountQuestItems(), nil
    end,
    QUEST_FINISHED = function()
        if detailCounts and not detailExpires then
            detailExpires = GetTime() + GIVEN_SECONDS
        end
    end,
    QUEST_ACCEPTED = function(_, questID)
        if detailCounts and (not detailExpires or GetTime() <= detailExpires) then
            accepted = { questID = questID, counts = detailCounts, expires = GetTime() + GIVEN_SECONDS }
        end
        detailCounts, detailExpires = nil, nil
        Request()
    end,
    QUEST_PROGRESS = OnQuestProgress,
    BAG_UPDATE_DELAYED = Request,
    BANKFRAME_OPENED = Request,
    QUEST_LOG_UPDATE = Request,
    QUEST_TURNED_IN = Request,
    QUEST_REMOVED = Request,
})

function Leftovers:Enable()
    Helpers.Needs:Acquire("leftovers")
    listener:Start()
    lastLeftovers = ""
    Request()
    ns:RefreshItemButtons()
end

function Leftovers:Disable()
    listener:Stop()
    Helpers.Needs:Release("leftovers")
    detailCounts, detailExpires, accepted = nil, nil, nil
    for _, mark in pairs(marks) do
        mark:Hide()
    end
    ns:RefreshItemButtons()
end
