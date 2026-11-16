-- Item buttons (core/itembuttons.lua): how often handlers' Prepare and Update
-- run as the bags change and Blizzard redraws them, and the shields meanwhile.
-- The fake bag starts as: G1 G2 - GJUNK, in the combined bags (4 buttons).

-- A handler of Item locking's (on by default) counting its calls.
local function Spy(world)
    local spy = { prepares = 0, updates = 0, drawn = {} }
    world.ns:AddItemButtonHandler(world.ns:GetFeature("inventory", "locking"), {
        Prepare = function()
            spy.prepares = spy.prepares + 1
        end,
        Update = function(button, _, guid)
            spy.updates = spy.updates + 1
            spy.drawn[button] = guid or false
        end,
    })
    world.ns:RefreshItemButtons()
    spy.prepares, spy.updates = 0, 0
    return spy
end

test("a bag change prepares once and redraws each button once", function(world)
    local spy = Spy(world)
    world.bags[0][3] = "G3"
    world:BagsChanged(0)
    world:NextFrame()
    equal(spy.prepares, 1, "prepares")
    equal(spy.updates, 4, "updates")
    equal(spy.drawn[world.buttons[3]], "G3", "new item drawn")
end)

test("Blizzard's redraw before BAG_UPDATE_DELAYED draws the new item at once, once", function(world)
    local spy = Spy(world)
    world.bags[0][3] = "G3"
    world:Fire("BAG_UPDATE", 0)
    world:NextFrame()
    equal(spy.drawn[world.buttons[3]], "G3", "drawn with Blizzard's redraw")
    world:Fire("BAG_UPDATE_DELAYED")
    equal(spy.prepares, 1, "prepares")
    equal(spy.updates, 4, "updates")
end)

test("BAG_UPDATE_DELAYED alone prepares again", function(world)
    local spy = Spy(world)
    world:Fire("BAG_UPDATE_DELAYED")
    equal(spy.prepares, 1, "prepares")
    equal(spy.updates, 4, "updates")
end)

test("Blizzard redrawing unchanged bags redraws no marks", function(world)
    local spy = Spy(world)
    world:Fire("UNIT_QUEST_LOG_CHANGED", "player")
    world:Fire("BAG_NEW_ITEMS_UPDATED")
    ContainerFrameCombinedBags:UpdateItems()
    equal(spy.prepares, 0, "prepares")
    equal(spy.updates, 0, "updates")
end)

test("Blizzard's redraws of separate bags share one Prepare", function(world)
    world:OpenSeparateBags()
    local spy = Spy(world)
    world.bags[0][3] = "G3"
    world:Fire("BAG_UPDATE", 0)
    world:Fire("BAG_UPDATE", 1)
    world:NextFrame()
    ContainerFrame2:UpdateItems()
    world:Fire("BAG_UPDATE_DELAYED")
    equal(spy.prepares, 1, "prepares")
    equal(spy.updates, 4, "updates: the backpack's buttons")
    equal(spy.drawn[world.backpackButtons[3]], "G3", "new item drawn")
end)

test("ns:RefreshItemButtons() always prepares and redraws every button", function(world)
    local spy = Spy(world)
    world.ns:RefreshItemButtons()
    equal(spy.prepares, 1, "prepares")
    equal(spy.updates, 4, "updates")
end)

test("cursor changes redraw shields only", function(world)
    world:AltClick(1)
    local spy = Spy(world)

    world:Fire("CURSOR_CHANGED")
    expect(not world:IsShielded(1), "no item held: no shield")

    C_Container.PickupContainerItem(0, 2)
    expect(world:IsShielded(1), "item held: the locked item is shielded")
    expect(not world:IsShielded(2), "unlocked items aren't")

    ClearCursor()
    expect(not world:IsShielded(1), "shield dropped with the item")
    equal(spy.prepares, 0, "prepares")
    equal(spy.updates, 0, "updates")
end)

test("Alt redraws shields only", function(world)
    local spy = Spy(world)
    world:SetAlt(true)
    expect(world:IsShielded(1), "shield with Alt")
    world:SetAlt(false)
    expect(not world:IsShielded(1), "shield dropped without Alt")
    equal(spy.prepares, 0, "prepares")
    equal(spy.updates, 0, "updates")
end)

test("a shield left up by a missed Alt release drops when hovered", function(world)
    world:SetAlt(true)
    world.alt = false
    local shield = world:Shield(1)
    shield.scripts.OnEnter(shield)
    expect(not world:IsShielded(1), "shield dropped")
end)

test("the item menu's shield drops once the menu closes, without Alt", function(world)
    local spy = Spy(world)
    expect(world:AltRightClick(1), "menu opened")
    expect(world:IsShielded(1), "shield kept up while the menu is open")
    world:CloseContextMenu()
    expect(not world:IsShielded(1), "shield dropped")
    equal(spy.updates, 0, "updates")
end)
