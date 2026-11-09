-- Item Locking: toggling, click shield, guards, tooltip, indicators, lifecycle.
-- The fake bag starts as: G1 G2 - GJUNK (GJUNK is poor quality).

local function Locking(world)
    return world.ns:GetFeature("inventory", "locking")
end

test("alt shows a shield over items only", function(world)
    world:SetAlt(true)
    expect(world:IsShielded(1), "shield over an item")
    expect(not world:IsShielded(3), "no shield over an empty slot")
    world:SetAlt(false)
    expect(not world:IsShielded(1), "shield dropped when alt is released")
end)

test("alt+click locks and unlocks", function(world)
    world:AltClick(1)
    expect(Locking(world):IsGUIDLocked("G1"), "locked")
    equal(world.env.ForeverEnhancedCharacterDB.inventory.locking.locks.G1, true, "saved per character")
    expect(world.prints[#world.prints]:find("[G1]", 1, true), "announced in chat")

    world:AltClick(1)
    expect(not Locking(world):IsGUIDLocked("G1"), "unlocked")
end)

test("returns a picked-up locked item on the next frame", function(world)
    world:AltClick(1)
    C_Container.PickupContainerItem(0, 1)
    expect(world.cursor ~= nil, "not cleared inside the pickup (that leaves the slot stuck)")
    world:NextFrame()
    equal(world.cursor, nil, "cursor")
    equal(#world.errors, 1, "errors shown")
end)

test("lets unlocked items be picked up", function(world)
    C_Container.PickupContainerItem(0, 2)
    world:NextFrame()
    expect(world.cursor ~= nil, "still on the cursor")
    equal(#world.errors, 0, "errors shown")
end)

test("blocks dropping onto a locked slot", function(world)
    world:AltClick(1)
    C_Container.PickupContainerItem(0, 2)
    world:NextFrame()
    expect(world:IsShielded(1), "locked slot shielded while the cursor holds an item")
    local shield = world:Shield(1)
    shield.scripts.OnReceiveDrag(shield)
    equal(world.errors[#world.errors], world.L["inventory.locking.isLocked"], "error")
    equal(world:Bag(), "G1 G2 - GJUNK", "bag unchanged")
end)

test("blocks selling a locked item at a merchant", function(world)
    world:AltClick(1)
    MerchantFrame.shown = true
    world:Fire("MERCHANT_SHOW")
    expect(world:IsShielded(1), "locked item shielded at the merchant")
    expect(not world:IsShielded(2), "unlocked item not shielded")
    world:ClickShield(1, "RightButton")
    equal(world.errors[#world.errors], world.L["inventory.locking.cannotSell"], "error")
end)

-- Sell All Junk. Junk = poor quality with a sell price; the bag becomes G1 JUNK - GJUNK.
local function WithTwoJunkItems(world)
    world.bags[0][2] = "JUNK"
    world.quality.JUNK = 0
    world:OpenMerchant()
end

test("leaves Sell All Junk to Blizzard when no junk is locked", function(world)
    WithTwoJunkItems(world)
    world:AltClick(1) -- a locked item that isn't junk doesn't matter
    world:ClickSellAllJunk()
    equal(#world.hiddenPopups, 0, "Blizzard's confirmation hidden")
    equal(#world.popups, 0, "our confirmations shown")
end)

test("sells unlocked junk and keeps locked junk", function(world)
    WithTwoJunkItems(world)
    world:AltClick(4)
    world:ClickSellAllJunk()
    equal(world.hiddenPopups[1], "GENERIC_CONFIRMATION", "Blizzard's confirmation replaced")

    local popup = assert(world.popups[1], "our confirmation shown")
    equal(popup.text, world.L["inventory.locking.sellJunkConfirm"], "text")
    equal(popup.text_arg1, 1, "junk items to sell")
    equal(popup.text_arg2, 1, "locked junk kept")
    equal(#world.sold, 0, "nothing sold before accepting")

    popup.callback()
    equal(table.concat(world.sold, " "), "JUNK", "sold")
    equal(world:Bag(), "G1 - - GJUNK", "bag")
end)

test("rechecks junk when the sale is accepted", function(world)
    WithTwoJunkItems(world)
    world:AltClick(4)
    world:ClickSellAllJunk()
    world:AltClick(2) -- locked while the confirmation was up
    world.popups[1].callback()
    equal(#world.sold, 0, "sold")

    world:AltClick(2) -- unlocked again: one junk item to sell
    world:ClickSellAllJunk()
    MerchantFrame.shown = false -- merchant closed before accepting
    assert(world.popups[2], "second confirmation shown").callback()
    equal(#world.sold, 0, "sold after the merchant closed")
end)

test("says so when all junk is locked", function(world)
    world:OpenMerchant()
    world:AltClick(4)
    world:ClickSellAllJunk()
    equal(world.hiddenPopups[1], "GENERIC_CONFIRMATION", "Blizzard's confirmation hidden")
    equal(#world.popups, 0, "our confirmations shown")
    equal(world.errors[#world.errors], world.L["inventory.locking.allJunkLocked"], "error")
end)

test("cancels Sell All Junk instead when selling unlocked junk is off", function(world)
    WithTwoJunkItems(world)
    world:AltClick(4)
    world:Setting("inventory.locking.sellUnlockedJunk"):SetValue(false)
    world:ClickSellAllJunk()
    equal(world.hiddenPopups[1], "GENERIC_CONFIRMATION", "Blizzard's confirmation hidden")
    equal(#world.popups, 0, "our confirmations shown")
    equal(world.errors[#world.errors], world.L["inventory.locking.sellJunkBlocked"], "error")
end)

test("ignores junk in bags excluded from Sell All Junk", function(world)
    WithTwoJunkItems(world)
    world:AltClick(4)
    world.excludedFromJunkSell[0] = true -- Blizzard wouldn't sell any of it
    world:ClickSellAllJunk()
    equal(#world.hiddenPopups, 0, "Blizzard's confirmation hidden")
    equal(#world.popups, 0, "our confirmations shown")
end)

test("adds a tooltip line to locked items only", function(world)
    world:AltClick(1)
    local lines = {}
    local tooltip = {
        AddLine = function(_, text)
            table.insert(lines, text)
        end,
    }
    world.tooltipPostCall(tooltip, { guid = "G1" })
    world.tooltipPostCall(tooltip, { guid = "G2" })
    equal(#lines, 1, "tooltip lines")
    expect(lines[1]:find(world.L["inventory.locking.tooltipLine"], 1, true), "line text")
end)

test("draws the chosen indicator style", function(world)
    world:AltClick(1)
    local indicator = world:Setting("inventory.locking.indicator")

    equal(world:Indicator(1), "QuestSharing-Padlock 13x16 BOTTOMLEFT+shadow", "padlock")
    equal(world:Indicator(2), "", "unlocked item")
    indicator:SetValue("center")
    equal(world:Indicator(1), "bankslot-icon-lock 24x24 CENTER", "center")
    indicator:SetValue("corner")
    equal(world:Indicator(1), "bankslot-icon-lock 20x20 TOPRIGHT", "corner")
    indicator:SetValue("none")
    equal(world:Indicator(1), "hidden", "none")
    indicator:SetValue("padlock")
    equal(world:Indicator(1), "QuestSharing-Padlock 13x16 BOTTOMLEFT+shadow", "back to padlock")
end)

test("turning the feature off undoes everything and keeps locks", function(world)
    world:AltClick(1)
    MerchantFrame.shown = true
    world:Fire("MERCHANT_SHOW")

    world:Setting("inventory.locking.enabled"):SetValue(false)
    expect(not world:IsShielded(1), "shield removed")
    equal(world:Indicator(1), "hidden", "indicator")
    expect(not Locking(world):IsGUIDLocked("G1"), "public API reports unlocked while inactive")
    equal(world.eventRegistry["MerchantFrame.SellAllJunkButtonClicked"], nil, "junk guard unregistered")
    C_Container.PickupContainerItem(0, 1)
    world:NextFrame()
    expect(world.cursor ~= nil, "cursor guard off")
    ClearCursor()

    world:Setting("inventory.locking.enabled"):SetValue(true)
    expect(Locking(world):IsGUIDLocked("G1"), "lock kept")
    expect(world:IsShielded(1), "shield back at the merchant")
end)
