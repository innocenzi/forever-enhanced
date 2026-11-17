-- labels: the macro name Blizzard writes on action bar buttons turns
-- transparent.
--
-- Blizzard only ever sets the label's text (ActionBarActionButtonMixin:Update),
-- never its visibility or alpha, so setting the alpha once per button holds.
-- The buttons are the ones ActionBarButtonEventsFrame lists (every Blizzard
-- action bar button, all created before login), read only. A font string's
-- alpha isn't protected: Blizzard's own range and usability coloring changes
-- these buttons' regions in combat too.

local _, ns = ...

local Macros = ns:GetFeature("interface", "macros")

local Labels = {}
Macros.Labels = Labels

local function SetLabelsAlpha(alpha)
    ActionBarButtonEventsFrame:ForEachFrame(function(button)
        if button.Name then
            button.Name:SetAlpha(alpha)
        end
    end)
end

function Labels:Enable()
    SetLabelsAlpha(0)
end

function Labels:Disable()
    SetLabelsAlpha(1)
end
