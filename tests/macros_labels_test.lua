-- Macros, names on action bars: every action bar button's macro name label turns
-- transparent, and back when disabled.

local function NameAlphas()
    local alphas = {}
    ActionBarButtonEventsFrame:ForEachFrame(function(button)
        alphas[button.Name:GetAlpha()] = true
    end)
    local list = {}
    for alpha in pairs(alphas) do
        table.insert(list, alpha)
    end
    table.sort(list)
    return table.concat(list, " ")
end

test("hides the macro names on every action bar button", function(world)
    equal(#ActionBarButtonEventsFrame.frames, 24, "main and bottom left bars")
    equal(NameAlphas(), "0", "hidden")

    world:Setting("interface.macros.labels"):SetValue(false)
    equal(NameAlphas(), "1", "shown when disabled")

    world:Setting("interface.macros.labels"):SetValue(true)
    equal(NameAlphas(), "0", "hidden again")
end)
