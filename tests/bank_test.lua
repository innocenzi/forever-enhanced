-- Saved Bank: saving, the view, alts, search, opening with the bags, lifecycle.
-- The fake bank: tab 1 (4 slots) holds B1 - B2(20) -, tab 2 (2 slots, in bag
-- GBAG) holds - B3, tab 3 isn't purchased. Bags start open.

local PLAYER = "Player-1-00000001"
local ALT = "Player-1-00000002"

local function Bank(world)
    return world.ns:GetFeature("inventory", "bank")
end

local function Saved(world, key)
    local characters = Bank(world):GetAccountStore().characters
    return characters and characters[key]
end

-- Opens the bank, lets the save run, closes it (which closes the bags).
local function VisitBank(world)
    world:OpenBank()
    world:NextFrame()
    world:CloseBank()
end

local function OpenSavedBank(world)
    world:OpenBags()
    world:ClickSideTab(world:BankSideTab())
end

local function SaveAlt(world, key, name, realm)
    local store = Bank(world):GetAccountStore()
    store.characters = store.characters or {}
    store.characters[key] = {
        name = name,
        class = "WARRIOR",
        realm = realm,
        tabs = { { size = 2, items = { { link = "|Hitem:A1|h[A1]|h", icon = "icon:A1", count = 1, name = "A1" } } } },
        bags = {},
    }
end

test("saves the bank when it opens", function(world)
    VisitBank(world)
    local saved = Saved(world, PLAYER)
    expect(saved, "saved under the player's GUID")
    equal(saved.name, "Hylmew", "name")
    equal(saved.class, "MAGE", "class")
    equal(saved.realm, "Forever", "realm")
    equal(#saved.tabs, 2, "purchased tabs")
    equal(saved.tabs[1].size, 4, "tab size")
    equal(saved.tabs[1].items[1].name, "B1", "first item")
    equal(saved.tabs[1].items[2], nil, "empty slot")
    equal(saved.tabs[1].items[3].count, 20, "stack count")
    expect(saved.bags[2].link:find("[GBAG]", 1, true), "bank bag")
    equal(saved.bags[3].purchased, false, "bag slot not purchased")
end)

test("saves changes while the bank is open, not after", function(world)
    world:OpenBank()
    world:NextFrame()
    world.bags[6][2] = "B4"
    world:Fire("BAG_UPDATE_DELAYED")
    world:NextFrame()
    equal(Saved(world, PLAYER).tabs[1].items[2].name, "B4", "change saved")

    world:CloseBank()
    world:Fire("BAG_UPDATE_DELAYED")
    world:NextFrame()
    equal(Saved(world, PLAYER).tabs[1].items[1].name, "B1", "kept after closing")
end)

test("shows the saved bank from the tab on the bags", function(world)
    VisitBank(world)
    OpenSavedBank(world)

    expect(world:IsSavedBankShown(), "shown")
    expect(world:BankSideTab().checked, "tab checked")
    equal(world.env.UIPanelWindows.ForeverEnhancedSavedBankFrame.area, "left", "a left UI panel")
    equal(world:SavedBank().title, world.L["inventory.bank.frameTitle"]:format("Hylmew"), "title")
    equal(world:SavedBank().portraitClass, "MAGE", "portrait")
    equal(world:SavedBankSlots(), "B1 - B2(20) - - B3", "slots")
    equal(world:SavedBankBags(), "GBAG x", "bank bags")

    world:ClickSideTab(world:BankSideTab())
    expect(not world:IsSavedBankShown(), "tab closes it")
    expect(not world:BankSideTab().checked, "tab unchecked")
end)

test("saved items show their tooltip and take modified clicks", function(world)
    VisitBank(world)
    OpenSavedBank(world)
    local button = world:SavedBankButton(3)
    button.scripts.OnEnter(button)
    expect(world.tooltip:find("[B2]", 1, true), "tooltip")
    button.scripts.OnClick(button, "LeftButton")
    expect(world.modifiedClicks[1]:find("[B2]", 1, true), "modified click")
    equal(world.pickups, 0, "nothing picked up")

    local empty = world:SavedBankButton(2)
    empty.scripts.OnClick(empty, "LeftButton")
    equal(#world.modifiedClicks, 1, "empty slot ignores clicks")
end)

test("says when this character has no saved bank", function(world)
    OpenSavedBank(world)
    expect(world:IsSavedBankShown(), "opens anyway")
    equal(world:SavedBankSlots(), "", "no slots")
    expect(world:SavedBankShowsText(world.L["inventory.bank.empty"]), "empty state")
    for _, texture in ipairs(world.textures) do
        if texture.owner == world:SavedBank() and texture.atlas == "bank-divider" then
            expect(not texture.shown, "no bag row divider")
        end
    end
end)

test("lists the alts of the same realm and forgets them", function(world)
    VisitBank(world)
    SaveAlt(world, ALT, "Zed", "Forever")
    SaveAlt(world, "Player-2-00000003", "Elsewhere", "Other")
    OpenSavedBank(world)

    local menu = world:SavedBankMenu()
    equal(menu[1].kind, "radio", "player entry")
    expect(menu[1].text:find("Hylmew", 1, true), "player first")
    expect(menu[1].isSelected(), "player selected")
    expect(menu[2].text:find("Zed", 1, true), "alt of the same realm")
    equal(menu[3].kind, "divider", "no alt of another realm")

    menu[2].select()
    equal(world:SavedBank().title, world.L["inventory.bank.frameTitle"]:format("Zed"), "alt title")
    equal(world:SavedBankSlots(), "A1 -", "alt slots")

    local forget = menu[4]
    equal(forget.text, world.L["inventory.bank.forget"], "forget submenu")
    equal(#forget.children, 1, "only alts can be forgotten")
    forget.children[1].callback()
    local popup = world.popups[#world.popups]
    equal(popup.text, world.L["inventory.bank.forgetConfirm"], "confirmation")
    equal(popup.text_arg1, "Zed", "confirmation name")
    popup.callback()
    equal(Saved(world, ALT), nil, "alt forgotten")
    equal(world:SavedBank().title, world.L["inventory.bank.frameTitle"]:format("Hylmew"), "back to the player")
    equal(#world:SavedBankMenu(), 1, "only the player left")
end)

test("filters saved items with the bags' search, both ways", function(world)
    VisitBank(world)
    OpenSavedBank(world)

    world:SearchBags("b2")
    equal(world:SavedBankSlots(), "~B1 - B2(20) - - ~B3", "filtered by the bags' search")
    equal(world:SavedBankSearchBox():GetText(), "b2", "search box follows")

    local box = world:SavedBankSearchBox()
    box.text = "B3"
    box:RunScript("OnTextChanged", true)
    equal(world.itemSearch, "B3", "bags follow")
    equal(world:SavedBankSlots(), "~B1 - ~B2(20) - - B3", "filtered by our search")

    world.itemTypes.B1 = { "Armor", "Cloth", "INVTYPE_HEAD" }
    world:SearchBags("head")
    equal(world:SavedBankSlots(), "B1 - ~B2(20) - - ~B3", "matches the equipment slot")

    world:SearchBags("")
    equal(world:SavedBankSlots(), "B1 - B2(20) - - B3", "search cleared")
end)

test("opens with the bags when asked, and always closes with them", function(world)
    VisitBank(world)
    world:OpenBags()
    expect(not world:IsSavedBankShown(), "off by default")
    world:CloseBags()

    world:Setting("inventory.bank.openWithBags"):SetValue(true)
    world:OpenBags()
    expect(world:IsSavedBankShown(), "opens with the bags")
    world:CloseBags()
    expect(not world:IsSavedBankShown(), "closes with the bags")
    expect(not world:BankSideTab().shown, "tab hidden with the bags")
end)

test("gives way to Blizzard's bank", function(world)
    world:Setting("inventory.bank.openWithBags"):SetValue(true)
    OpenSavedBank(world)
    world:ClickSideTab(world:BankSideTab())
    world:CloseBags()

    world:OpenBank()
    expect(not world:IsSavedBankShown(), "not opened with the bank's bags")
    expect(not world:BankSideTab().shown, "tab hidden at the bank")
    world:CloseBank()

    world:OpenBags()
    expect(world:IsSavedBankShown(), "opens again away from the bank")
    world:OpenBank()
    expect(not world:IsSavedBankShown(), "closed when the bank opens")
end)

test("opens and closes in combat", function(world)
    world.inCombat = true
    OpenSavedBank(world)
    expect(world:IsSavedBankShown(), "shown in combat")
    world:ClickSideTab(world:BankSideTab())
    expect(not world:IsSavedBankShown(), "hidden in combat")
end)

test("splits a large bank into pages", function(world)
    world.bagSizes[6] = 90
    VisitBank(world)
    OpenSavedBank(world)
    local tabs = {}
    for _, frame in ipairs(world.frames) do
        if frame.template == "LargeSideTabButtonTemplate" and frame.parent == world:SavedBank() and frame.shown then
            table.insert(tabs, frame)
        end
    end
    equal(#tabs, 2, "page tabs")
    expect(tabs[1].checked and not tabs[2].checked, "first page")
    equal(select(2, world:SavedBankSlots():gsub("%S+", "")), 88, "slots on the first page")

    world:ClickSideTab(tabs[2])
    expect(tabs[2].checked, "second page")
    equal(world:SavedBankSlots(), "- - - B3", "the last 2 slots of tab 1, then tab 2")
end)

test("turning the feature off hides everything and stops saving", function(world)
    OpenSavedBank(world)
    world:Setting("inventory.bank.enabled"):SetValue(false)
    expect(not world:IsSavedBankShown(), "view hidden")
    expect(not world:BankSideTab().shown, "tab hidden")
    equal(world.eventRegistry["ContainerFrame.OpenBag"], nil, "bag callbacks removed")

    VisitBank(world)
    equal(Saved(world, PLAYER), nil, "nothing saved while off")

    world:Setting("inventory.bank.enabled"):SetValue(true)
    world:OpenBags()
    expect(world:BankSideTab().shown, "tab back")
end)

-- Bank count in tooltips. B1 (5) and B3 (7) are the same item, linen.
local function SetUpLinen(world)
    world.itemIDs.B1, world.itemIDs.B3 = "linen", "linen"
    world.counts.B1, world.counts.B3 = 5, 7
end

local function BankLine(world, count)
    return world.L["inventory.bank.tooltipLine"]:format(count)
end

test("item tooltips count the item across the saved bank", function(world)
    SetUpLinen(world)
    VisitBank(world)
    local lines = world:ItemTooltip({ id = "linen" })
    equal(#lines, 1, "lines")
    equal(lines[1], BankLine(world, 12), "count across tabs")
    equal(#world:ItemTooltip({ id = "G1" }), 0, "nothing for items the bank lacks")
end)

test("no bank count before the bank was ever saved", function(world)
    equal(#world:ItemTooltip({ id = "B2" }), 0, "lines")
end)

test("the bank count follows changes at the bank", function(world)
    SetUpLinen(world)
    world:OpenBank()
    world:NextFrame()
    world.bags[7][2] = nil
    world:Fire("BAG_UPDATE_DELAYED")
    world:NextFrame()
    equal(world:ItemTooltip({ id = "linen" })[1], BankLine(world, 5), "count after a change")
end)

test("the bank count sits with the lock line", function(world)
    world.bags[0][1] = "L1"
    world.itemIDs.L1 = "linen"
    SetUpLinen(world)
    world:AltClick(1)
    VisitBank(world)
    local lines = world:ItemTooltip({ guid = "L1", id = "linen" })
    equal(#lines, 2, "both lines")
    equal(lines[2], BankLine(world, 12), "bank count")
end)

test("no bank count with the option or the feature off", function(world)
    VisitBank(world)
    world:Setting("inventory.bank.tooltipCount"):SetValue(false)
    equal(#world:ItemTooltip({ id = "B2" }), 0, "option off")
    world:Setting("inventory.bank.tooltipCount"):SetValue(true)
    equal(#world:ItemTooltip({ id = "B2" }), 1, "option on")
    world:Setting("inventory.bank.enabled"):SetValue(false)
    equal(#world:ItemTooltip({ id = "B2" }), 0, "feature off")
end)
