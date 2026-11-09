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

test("cancels Sell All Junk only when junk is locked", function(world)
    local onClicked = world.eventRegistry["MerchantFrame.SellAllJunkButtonClicked"]
    onClicked()
    equal(#world.hiddenPopups, 0, "popups hidden without locked junk")

    world:AltClick(4)
    onClicked()
    equal(world.hiddenPopups[1], "GENERIC_CONFIRMATION", "confirmation hidden")
    equal(world.errors[#world.errors], world.L["inventory.locking.sellJunkBlocked"], "error")
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
