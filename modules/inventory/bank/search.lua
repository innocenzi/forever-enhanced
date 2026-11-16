-- Search box of the saved bank, kept in sync with the bags' search box both
-- ways, like Blizzard's bank search box. Typing here drives the bags' box, so
-- the bags filter too.
--
-- The client only filters items that are really in a container, so saved items
-- are matched here (ns:MatchesItemSearch).

local _, ns = ...

local Bank = ns:GetFeature("inventory", "bank")

local Search = {}
Bank.Search = Search

local searchBox
local needle = ""

function Search:Matches(item)
    local name = item.name or (item.link and item.link:match("%[(.-)%]"))
    return ns:MatchesItemSearch(needle, name, item.itemID or item.link)
end

local function SetNeedle(text)
    text = text:lower()
    if text ~= needle then
        needle = text
        Bank.View:UpdateSearch()
    end
end

function Search:CreateBox(parent)
    searchBox = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
    searchBox:SetSize(110, 20)
    searchBox:HookScript("OnTextChanged", function(box, userInput)
        if userInput then
            BagItemSearchBox:SetText(box:GetText())
        end
        SetNeedle(box:GetText())
    end)
    return searchBox
end

-- Takes the bags' search text (on every search change, and when the view opens).
function Search:Sync()
    local text = BagItemSearchBox:GetText()
    if searchBox and searchBox:GetText() ~= text then
        searchBox:SetText(text)
    end
end

local listener = ns:CreateEventListener({
    INVENTORY_SEARCH_UPDATE = function()
        Search:Sync()
    end,
})

function Search:Enable()
    listener:Start()
end

function Search:Disable()
    listener:Stop()
end
