-- The seamless view: the stitched art in a frame of our own laid over Blizzard's
-- map (WorldMapFrame.ScrollContainer), which it never writes into (feature.lua, TAINT).
-- Two states: Blizzard's map, as Blizzard made it (the view hidden), and the seamless
-- view over it.
--   - Opening: the wheel zooming out on the world, a continent or a zone already at
--     Blizzard's widest view (Blizzard's zoom does nothing there). The view starts
--     exactly on Blizzard's view, fades in, and zooms out that notch.
--   - In the view: the wheel zooms from the whole world down to street level, toward the
--     cursor (the point under it stays put, and the map can be dragged mid-zoom); a drag
--     pans across the whole world, and a little past its edges once zoomed in; a click
--     zooms into the zone or continent under the cursor, a right click out a level; a click
--     on a quest's marker follows the quest and goes to its zone. A map pin (Ctrl Click,
--     or a click with the map's pin button on, under the map pin's cursor) goes on the
--     deepest map under the cursor that takes one, and clicks on the map pin do what they
--     do on Blizzard's (waypoint.lua). The zone label names what's under the cursor, as
--     Blizzard's area label (whose own only shows while Blizzard's map has the mouse).
--   - Handing back: once the view comes to a zone (a click, or the wheel reaching where
--     the zone just fits), Blizzard's map is opened on it (C_Map.OpenWorldMap, from that
--     click or wheel: measured untainted out of combat, refused in combat), the view
--     glides to Blizzard's view of it (the zone fitted and centred), drawing it whole
--     ("returning"), and fades out ("fading"). Out of combat only, but onto the map
--     Blizzard's shows, at any time: zooming back onto where the view opened from, or the
--     right click's map. Blizzard changing its map itself (a quest's details, its
--     dropdown) hands back to that map, or closes the view at once on a map it can't draw
--     (dungeons, battlegrounds).
-- Zoom: 1 = the whole world fits the view.
--
-- From OpenMap's Map/WorldMap.lua (openmap-license.txt).

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")
local Geometry, Art, Arrow = Seamless.Geometry, Seamless.Art, Seamless.Arrow
local Waypoint, Quests, Pins = Seamless.Waypoint, Seamless.Quests, Seamless.Pins

local View = {}
Seamless.View = View

local WORLD = Geometry.WORLD
-- Frame levels: above every map pin (Blizzard's level manager stops at 9000, other
-- addons' pins with it), under Blizzard's map controls (their own strata, HIGH; but
-- the quest log's toggle and the coordinates panel, raised there while the view shows).
local LEVEL = 9100
local ART_RANGE = 80
local ICON_LEVEL = LEVEL + ART_RANGE + 5
local ARROW_LEVEL = LEVEL + ART_RANGE + 10

local ZOOM_STEP = 1.25 -- each wheel notch
local MAX_ZOOM = 48 -- the deepest zoom
local CITY_ZOOM = 1.5 -- ... times this in a city, whose map is small
local ZOOM_RATE = 14 -- the wheel's approach, per second (in log zoom)
local GLIDE_SECONDS = 0.4
local FADE_SECONDS = 0.15
-- A click zooms into the next map down that's this much bigger than the view, a right
-- click out to the next map up this much smaller.
local CLICK_IN, CLICK_OUT = 1.05, 0.95
-- Room past the world's edges (of its size), gained between zoom 1 and CENTRE_UNTIL:
-- zoomed right out the world is centred, and the wheel zooms at the cursor from the first notch.
local EDGE_SLACK = 0.2
local CENTRE_UNTIL = 1.6
-- A press that moved this far (squared, view pixels: Blizzard's click distance) is a drag, even if it came back.
local CLICK_SLOP = 20
-- How often the group's members follow them, and the zone label the cursor.
local TICK = 0.05
-- Blizzard's area label (AreaLabelFrameTemplate): its scale, and its name's offset from the map's top.
local LABEL_SCALE, LABEL_OFFSET = 0.695, -20

local map, sc
local frame, canvas
local installed = false
-- "hidden": Blizzard's map; "open": the seamless view; "returning": gliding to Blizzard's view;
-- "fading": fading out over it, Blizzard's map taking the input (it may still be gliding)
local state = "hidden"
local view = { u = 0.5, v = 0.5, zoom = 1 }
local anim -- the running zoom: { mode = "anchor" | "glide", ... }
local handOff -- the map being handed back to (returning or fading)
local expected -- the map our own OpenWorldMap is putting up
local press = {} -- button -> { x, y, moved }
-- the world point the cursor carries while the left button is down (`pending`: pressed during a
-- glide, taken once the press turns into a drag or the glide ends)
local grab
local zoomedAt -- GetTime() of Blizzard's last zoom (its wheel's notch changed it)
local sinceTick = 0
local raised = {} -- Blizzard's controls raised over the view -> their own strata
local label -- the zone label's font string
local pinCursor = false -- whether the cursor is the map pin's, set by us

local function Clamp(value, low, high)
    return math.min(math.max(value, low), high)
end

-- Geometry of the view ------------------------------------------------------------------

-- View pixels per world unit when the whole world fits.
local function FitPx()
    local width, height = Geometry:Size()
    return math.min(frame:GetWidth() / width, frame:GetHeight() / height)
end

-- The zoom where the map just fits the view: Blizzard's widest view of it.
local function FitZoom(mapID)
    local width, height = Geometry:Size()
    local left, right, top, bottom = Geometry:Rect(mapID)
    return math.min(frame:GetWidth() / ((right - left) * width), frame:GetHeight() / ((bottom - top) * height))
        / FitPx()
end

-- The map's middle on the world.
local function Middle(mapID)
    local left, right, top, bottom = Geometry:Rect(mapID)
    return (left + right) / 2, (top + bottom) / 2
end

-- The layers fade by how much of the world is in view, its area, not by how far
-- it is from fitting it: a tall or very wide view fits the world across its narrow
-- side and shows much more of it the other way.
local function DetailScale()
    local width, height = Geometry:Size()
    local viewWidth, viewHeight = frame:GetWidth(), frame:GetHeight()
    return math.min(viewWidth / width, viewHeight / height) / math.sqrt(viewWidth * viewHeight / (width * height))
end

-- World units (normalized) per view pixel at `zoom`.
local function PerPx(zoom)
    local width, height = Geometry:Size()
    local px = FitPx() * zoom
    return 1 / (width * px), 1 / (height * px)
end

-- The cursor from the middle of the view, in view pixels (y down).
local function CursorOffset()
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    return x / scale - (frame:GetLeft() + frame:GetWidth() / 2), (frame:GetTop() - frame:GetHeight() / 2) - y / scale
end

local function CursorWorld()
    local sx, sy = CursorOffset()
    local pu, pv = PerPx(view.zoom)
    return view.u + sx * pu, view.v + sy * pv
end

local function MaxZoomAt(u, v)
    return MAX_ZOOM * (Geometry:IsInCity(u, v) and CITY_ZOOM or 1)
end

-- From `low` to `high` less `half` (or their middle when the view is wider than
-- that), opened by `slack` on each side as `t` goes from 0 to 1.
local function Range(low, high, half, slack, t)
    local from, to = low + half, high - half
    local plainFrom, plainTo = from, to
    if from > to then
        plainFrom = (low + high) / 2
        plainTo = plainFrom
    end
    local fullFrom, fullTo = math.min(from, to) - slack, math.max(from, to) + slack
    return plainFrom + (fullFrom - plainFrom) * t, plainTo + (fullTo - plainTo) * t
end

-- The view's art follows it --------------------------------------------------------------

-- (a pan moves the view several times a frame: what's near it is worked out once, next frame)
local follower = CreateFrame("Frame")
follower:Hide()
follower:SetScript("OnUpdate", function(self)
    self:Hide()
    if state == "hidden" then
        return
    end
    local pu, pv = PerPx(view.zoom)
    Art:SetView(view.u, view.v, frame:GetWidth() / 2 * pu, frame:GetHeight() / 2 * pv)
    Pins:Place()
end)

-- Puts the view at (u, v) on the world, at `zoom`, within the pan's reach: the world,
-- and every continent's middle by the zoom it fits at (a continent's map reaches
-- past the world's), where the view opens and hands back on it. The layers' fades follow
-- the zoom when it changes, or with `refresh` (they depend on the view's size too).
local function SetView(u, v, zoom, refresh)
    local width, height = Geometry:Size()
    local pu, pv = PerPx(zoom)
    local t = Clamp((zoom - 1) / (CENTRE_UNTIL - 1), 0, 1)
    local minU, maxU = Range(0, 1, frame:GetWidth() / 2 * pu, EDGE_SLACK, t)
    local minV, maxV = Range(0, 1, frame:GetHeight() / 2 * pv, EDGE_SLACK, t)
    for _, mapID in ipairs(Geometry:Continents()) do
        local fit = FitZoom(mapID)
        local reach = fit > 1 and Clamp((zoom - 1) / (fit - 1), 0, 1) or 1
        local mu, mv = Middle(mapID)
        minU, maxU = math.min(minU, minU + (mu - minU) * reach), math.max(maxU, maxU + (mu - maxU) * reach)
        minV, maxV = math.min(minV, minV + (mv - minV) * reach), math.max(maxV, maxV + (mv - maxV) * reach)
    end
    view.u, view.v = Clamp(u, minU, maxU), Clamp(v, minV, maxV)
    local zoomChanged = refresh or view.zoom ~= zoom
    view.zoom = zoom
    local px = FitPx() * zoom
    canvas:SetScale(px)
    canvas:ClearAllPoints()
    -- (offsets in the canvas's own, scaled, units: its corner is the world's)
    canvas:SetPoint(
        "TOPLEFT",
        frame,
        "TOPLEFT",
        frame:GetWidth() / 2 / px - view.u * width,
        -(frame:GetHeight() / 2 / px - view.v * height)
    )
    if zoomChanged then
        Art:SetZoom(zoom * DetailScale())
    end
    follower:Show()
end

-- Zooming --------------------------------------------------------------------------------

-- The wheel: zoom about the point under the cursor (zooming in never takes it back out).
-- Returns the zoom it's going from and to, and the point it's about.
local function ZoomAtCursor(factor)
    local sx, sy = CursorOffset()
    local pu, pv = PerPx(view.zoom)
    local u, v = view.u + sx * pu, view.v + sy * pv
    local from = anim and anim.mode == "anchor" and anim.target or view.zoom
    local most = MaxZoomAt(u, v)
    if factor > 1 then
        most = math.max(most, from)
    end
    anim = { mode = "anchor", u = u, v = v, sx = sx, sy = sy, target = Clamp(from * factor, 1, most) }
    return from, anim.target, u, v
end

-- Glides the view to a world point at `zoom`, as one zoom about a fixed point.
local function GlideTo(u, v, zoom)
    anim = {
        mode = "glide",
        u0 = view.u,
        v0 = view.v,
        z0 = view.zoom,
        u1 = u,
        v1 = v,
        z1 = Clamp(zoom, 1, MaxZoomAt(u, v)),
        t = 0,
    }
end

local function Animate(elapsed)
    local a = anim
    if a.mode == "anchor" then
        local current = view.zoom
        local logZoom = math.log(current)
            + (math.log(a.target) - math.log(current)) * (1 - math.exp(-elapsed * ZOOM_RATE))
        local zoom = math.exp(logZoom)
        local done = math.abs(math.log(a.target / zoom)) < 0.003
        if done then
            zoom = a.target
        end
        if grab and grab.u then
            -- (dragged mid-zoom: the cursor carries what was under it)
            a.u, a.v = grab.u, grab.v
            a.sx, a.sy = CursorOffset()
        end
        local pu, pv = PerPx(zoom)
        SetView(a.u - a.sx * pu, a.v - a.sy * pv, zoom)
        if done then
            anim = nil
        end
    else
        a.t = math.min(1, a.t + elapsed / GLIDE_SECONDS)
        local e = a.t * a.t * (3 - 2 * a.t)
        local zoom = math.exp(math.log(a.z0) + (math.log(a.z1) - math.log(a.z0)) * e)
        -- the middle moves with 1/zoom: what zooming about one fixed point looks like
        local w = math.abs(a.z1 - a.z0) < 1e-6 and e or (1 / a.z0 - 1 / zoom) / (1 / a.z0 - 1 / a.z1)
        SetView(a.u0 + (a.u1 - a.u0) * w, a.v0 + (a.v1 - a.v0) * w, zoom)
        if a.t >= 1 then
            anim = nil
        end
    end
end

-- Opening and handing back ---------------------------------------------------------------

-- Blizzard's map controls in the map's own strata (the quest log's toggle, the
-- coordinates panel), raised over the view while it shows, put back after. (Their
-- strata is no Lua value of Blizzard's code: changing it taints nothing.)
local function RaiseControls()
    local controls = { map.SidePanelToggle }
    for _, overlay in ipairs(map.overlayFrames or {}) do
        if overlay.CursorCoords then
            table.insert(controls, overlay)
        end
    end
    for _, control in ipairs(controls) do
        if not raised[control] then
            raised[control] = control:GetFrameStrata()
            control:SetFrameStrata("HIGH")
        end
    end
end

local function LowerControls()
    for control, strata in pairs(raised) do
        control:SetFrameStrata(strata)
    end
    wipe(raised)
end

local function Close()
    state = "hidden"
    anim, grab, handOff, expected = nil, nil, nil, nil
    wipe(press)
    frame:Hide()
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    LowerControls()
    Art:SetHandOff(nil)
    Art:Hide()
    Arrow:Hide()
    Pins:Hide()
    label:SetText("")
    if pinCursor then
        pinCursor = false
        ResetCursor()
    end
end

local function Open(mapID)
    RaiseControls()
    state = "open"
    frame:SetAlpha(0)
    frame:Show()
    Art:Show(canvas, LEVEL + 1, ART_RANGE)
    local u, v = Middle(mapID)
    SetView(u, v, FitZoom(mapID), true)
    Pins:Show(frame, ICON_LEVEL)
    View:UpdateArrow()
end

-- Glides the view to Blizzard's view of `mapID`: the map fitted and centred.
local function GlideToMap(mapID)
    local u, v = Middle(mapID)
    GlideTo(u, v, FitZoom(mapID))
end

-- The view goes back to Blizzard's map, on `mapID`: it glides to Blizzard's view of it, drawing
-- it whole, then fades out (fading out already, it glides there as it goes on fading).
local function StartReturn(mapID)
    if state ~= "fading" then
        state = "returning"
    end
    handOff = mapID
    Art:SetHandOff(mapID)
    GlideToMap(mapID)
end

-- Whether the view may hand Blizzard's map back on `mapID`: onto the map Blizzard's shows, or
-- onto a zone, which our own OpenWorldMap puts up (refused in combat).
local function CanHandBack(mapID)
    return mapID == map:GetMapID() or Geometry:IsZone(mapID) and not InCombatLockdown()
end

-- Hands Blizzard's map back on `mapID`: opened there (unless it's on it already), then the
-- view returns to it. Only from a click or the wheel.
local function HandBack(mapID)
    if mapID ~= map:GetMapID() then
        expected = mapID
        C_Map.OpenWorldMap(mapID)
        expected = nil
        if map:GetMapID() ~= mapID then
            return false
        end
    end
    StartReturn(mapID)
    return true
end

-- The glide to Blizzard's view is done: the view fades out, leaving Blizzard's map its input.
local function FadeOut()
    state = "fading"
    frame:EnableMouse(false)
    frame:EnableMouseWheel(false)
end

-- Input ----------------------------------------------------------------------------------

-- The next map down under the cursor: the first that's this much bigger than the view
-- (than where it's gliding to: a second click during a glide goes a level further).
local function NextMapDown(chain)
    local zoom = anim and anim.mode == "glide" and anim.z1 or view.zoom
    for _, mapID in ipairs(chain) do
        if mapID ~= WORLD and Geometry:IsStitchable(mapID) and FitZoom(mapID) > zoom * CLICK_IN then
            return mapID
        end
    end
end

-- The next map up under the cursor: the last that's this much smaller than the view, else the
-- world. (From the view itself, not from where it's gliding to: a second right click during a
-- glide goes to the same map.)
local function NextMapUp(chain)
    local target = WORLD
    for _, mapID in ipairs(chain) do
        if mapID ~= WORLD and Geometry:IsStitchable(mapID) and FitZoom(mapID) < view.zoom * CLICK_OUT then
            target = mapID
        end
    end
    return target
end

-- Goes to a map a click asked for that isn't a zone: handed back if it's the map Blizzard's
-- shows, else the view glides to it.
local function GoToMap(mapID)
    if not (mapID == map:GetMapID() and HandBack(mapID)) then
        GlideToMap(mapID)
    end
end

-- Goes to the zone a click asked for: Blizzard's map handed back on it, or (in combat,
-- which refuses opening Blizzard's map there) the view glides to it, saying why (unless `said`).
local function GoToZone(zone, said)
    if CanHandBack(zone) and HandBack(zone) then
        return
    end
    if InCombatLockdown() and not said then
        ns:Error(ERR_NOT_IN_COMBAT)
    end
    GlideToMap(zone)
end

-- A left click on an icon: the map pin (waypoint.lua), placing one in pin mode, or a quest's
-- marker (its link in chat, or the quest followed and its zone opened). Returns whether it was one.
local function ClickIcon()
    if Pins:IsWaypointUnderCursor() then
        Waypoint:Click()
        return true
    end
    if Waypoint:IsPinMode() then
        Waypoint:PlaceAt(CursorWorld())
        return true
    end
    local questID, qu, qv = Pins:QuestUnderCursor()
    if questID and Quests:IsMarkerClick() then
        local zone = Geometry:ZoneAt(qu, qv)
        local result = Quests:Click(questID)
        -- (refused in combat, saying so: the view still goes to its zone)
        if (result == "followed" or result == "refused") and zone then
            GoToZone(zone, result == "refused")
        end
        return true
    end
    return false
end

-- A click: into the next map down under the cursor (handing back on a zone); a right
-- click: out to the next map up.
local function Click(button)
    if button == "LeftButton" and ClickIcon() then
        return
    end
    if IsModifierKeyDown() then
        return
    end
    local u, v = CursorWorld()
    local chain = Geometry:ChainAt(u, v)
    if button == "RightButton" then
        GoToMap(NextMapUp(chain))
    elseif button == "LeftButton" then
        local target = NextMapDown(chain)
        if target and Geometry:IsZone(target) then
            GoToZone(target)
        elseif target then
            GoToMap(target)
        else
            -- (zoomed in past every map under the cursor: back out to the zone, Blizzard's)
            local zone = Geometry:ZoneAt(u, v)
            if zone and CanHandBack(zone) then
                HandBack(zone)
            elseif zone and InCombatLockdown() then
                ns:Error(ERR_NOT_IN_COMBAT)
            end
        end
    end
end

-- Takes the pending grab: what's under the cursor now.
local function TakeGrab()
    grab.u, grab.v = CursorWorld()
    grab.pending = nil
end

local function OnMouseWheel(_, delta)
    if state == "returning" then
        if delta > 0 then
            return
        end
        -- (zooming back out mid-glide: the view stays, and a drag carries what's under the cursor now)
        state = "open"
        handOff = nil
        Art:SetHandOff(nil)
        if grab then
            TakeGrab()
        end
    end
    local from, to, u, v = ZoomAtCursor(delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP)
    if delta <= 0 then
        return
    end
    -- the wheel reaching where a map just fits, deepest first: handed back there if it may be
    local chain = Geometry:ChainAt(u, v)
    for index = #chain, 1, -1 do
        local mapID = chain[index]
        local fit = Geometry:IsStitchable(mapID) and FitZoom(mapID)
        if fit and fit > from and fit <= to * (1 + 1e-6) and CanHandBack(mapID) then
            HandBack(mapID)
            return
        end
    end
end

local function OnMouseDown(_, button)
    local x, y = CursorOffset()
    press[button] = { x = x, y = y, moved = false }
    if button == "LeftButton" then
        grab = {}
        -- (during a glide: it goes on unless the press turns into a drag, so a click
        -- during it aims from where it's going)
        if anim and anim.mode == "glide" and state == "open" then
            grab.pending = true
        else
            TakeGrab()
        end
    end
end

local function OnMouseUp(_, button)
    local pressed = press[button]
    press[button] = nil
    if button == "LeftButton" then
        grab = nil
    end
    if pressed and not pressed.moved and state == "open" then
        Click(button)
    end
end

-- A press that wandered off and came back isn't a click. (A press during a glide that
-- turns into a drag stops the glide.)
local function TrackPresses()
    for button, pressed in pairs(press) do
        if not pressed.moved then
            local x, y = CursorOffset()
            local dx, dy = x - pressed.x, y - pressed.y
            if dx * dx + dy * dy > CLICK_SLOP then
                pressed.moved = true
                if button == "LeftButton" and grab and grab.pending and state == "open" then
                    if anim and anim.mode == "glide" then
                        anim = nil
                    end
                    TakeGrab()
                end
            end
        end
    end
end

-- The map pin's cursor over the view in pin mode, as over Blizzard's map (whose own cursor
-- handlers only run while it has the mouse).
local function UpdateCursor()
    local wanted = state == "open" and frame:IsMouseMotionFocus() and Waypoint:IsPinMode()
    if wanted then
        pinCursor = true
        SetCursor("MAP_PIN_CURSOR")
    elseif pinCursor then
        pinCursor = false
        ResetCursor()
    end
end

-- The name of `mapID`, with its level range coloured against the player's level, as
-- Blizzard's area label (AreaLabelFrameMixin:OnUpdate).
local function MapLabel(mapID)
    local info = C_Map.GetMapInfo(mapID)
    local name = info and info.name
    local low, high = C_Map.GetMapLevels(mapID)
    if name and low and high and low > 0 and high > 0 then
        local level = UnitLevel("player")
        local color
        if level < low then
            color = GetQuestDifficultyColor(low)
        elseif level > high then
            -- (Blizzard's: zones entirely below the player's level aren't yellow)
            color = GetQuestDifficultyColor(high - 2)
        else
            color = QuestDifficultyColors["difficult"]
        end
        local range = low ~= high and low .. "-" .. high or tostring(high)
        name = name .. RGBTableToColorCode(color) .. " (" .. range .. ")" .. FONT_COLOR_CODE_CLOSE
    end
    return name
end

-- The zone label: what's under the cursor, as Blizzard's map names it: the map a click goes
-- to (its level range), or zoomed in on a zone, the area of it.
local function UpdateLabel()
    local text
    if state == "open" and frame:IsMouseMotionFocus() then
        local u, v = CursorWorld()
        local chain = Geometry:ChainAt(u, v)
        local mapID = NextMapDown(chain)
        if mapID then
            text = MapLabel(mapID)
        else
            local zone = Geometry:ZoneAt(u, v)
            text = zone and MapUtil.FindBestAreaNameAtMouse(zone, Geometry:FromWorld(zone, u, v))
        end
    end
    label:SetText(text or "")
end

local function OnUpdate(_, elapsed)
    TrackPresses()
    if anim then
        Animate(elapsed)
        if not anim and grab and grab.pending then
            TakeGrab()
        end
    elseif grab and grab.u and state == "open" then
        local sx, sy = CursorOffset()
        local pu, pv = PerPx(view.zoom)
        SetView(grab.u - sx * pu, grab.v - sy * pv, view.zoom)
    end
    if state == "returning" and not anim then
        FadeOut()
    end
    -- (fading in as it opens, out once it's returned)
    local alpha, target = frame:GetAlpha(), state == "fading" and 0 or 1
    if alpha ~= target then
        local step = elapsed / FADE_SECONDS
        alpha = target > alpha and math.min(target, alpha + step) or math.max(target, alpha - step)
        frame:SetAlpha(alpha)
        if alpha == 0 and state == "fading" then
            Close()
            return
        end
    end
    -- (every frame, as Blizzard's: the player turns and runs with the map open)
    View:UpdateArrow()
    sinceTick = sinceTick + elapsed
    if sinceTick >= TICK then
        sinceTick = 0
        Pins:UpdateGroup()
        UpdateLabel()
    end
    UpdateCursor()
    -- (the view's own: not under one of Blizzard's controls, nor once it's let the mouse go)
    if frame:IsMouseMotionFocus() then
        Pins:Hover(CursorOffset())
    else
        Pins:Hover(nil)
    end
end

-- Blizzard's map ------------------------------------------------------------------------

-- The wheel on Blizzard's map, after Blizzard's own zoom: zooming out where it already
-- couldn't opens the view. (Blizzard's zoom is instant: its notch changes the scale at once.)
local function OnBlizzardWheel(_, delta)
    if not Seamless:IsActive() or delta >= 0 or zoomedAt == GetTime() then
        return
    end
    -- (fading out after handing back, Blizzard's map already has the mouse: opened again; not
    -- while still gliding to a map Blizzard changed to as it faded)
    if state == "fading" and not anim then
        Close()
    end
    if state ~= "hidden" then
        return
    end
    local mapID = map:GetMapID()
    if not Geometry:IsStitchable(mapID) or not sc:IsAtMinZoom() then
        return
    end
    Open(mapID)
    ZoomAtCursor(1 / ZOOM_STEP)
end

-- Blizzard's map events, read only: its providers are called from Blizzard's own code, one
-- by one (secureexecuterange), so ours never runs inside another's call.
local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:OnHide()
    if state ~= "hidden" then
        Close()
    end
end

function provider:OnCanvasScaleChanged()
    zoomedAt = GetTime()
end

-- Blizzard changed its map while the view is up (a quest's details, its dropdown): handed
-- back there, or closed on a map the view can't draw. (Not our own OpenWorldMap's.)
function provider:OnMapChanged()
    local mapID = map:GetMapID()
    if state == "hidden" or mapID == expected or mapID == handOff then
        return
    end
    if not Geometry:IsStitchable(mapID) then
        Close()
        return
    end
    StartReturn(mapID)
end

local listener = ns:CreateEventListener({
    MAP_EXPLORATION_UPDATED = function()
        Art:RefreshExplored()
    end,
})

-- The player's position on `mapID` (normalized), unless the game keeps it secret.
local function PlayerOn(mapID)
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if position and not issecretvalue(position.x) and not issecretvalue(position.y) then
        return position.x, position.y
    end
end

-- The player's arrow, where they are in view.
function View:UpdateArrow()
    local best = C_Map.GetBestMapForUnit("player")
    local x, y
    if best and Geometry:Rect(best) then
        x, y = PlayerOn(best)
    end
    local facing = GetPlayerFacing()
    if state == "hidden" or not x or not facing or issecretvalue(facing) then
        Arrow:Hide()
        return
    end
    local u, v = Geometry:ToWorld(best, x, y)
    local dx, dy = self:ToView(u, v, Arrow.SIZE)
    if not dx then
        Arrow:Hide()
        return
    end
    Arrow:Show(frame, ARROW_LEVEL, dx, -dy, facing)
end

-- A world point on the view, in view pixels from its middle (y down); nil out of view
-- (by more than `margin` view pixels, for an icon sliding out under its edge).
function View:ToView(u, v, margin)
    local pu, pv = PerPx(view.zoom)
    local dx, dy = (u - view.u) / pu, (v - view.v) / pv
    margin = margin or 0
    if math.abs(dx) > frame:GetWidth() / 2 + margin or math.abs(dy) > frame:GetHeight() / 2 + margin then
        return nil
    end
    return dx, dy
end

-- The view's frame, for the tests.
function View:GetFrame()
    return frame
end

-- The view, for the tests: its middle on the world and its zoom; nil while hidden.
function View:GetView()
    if state ~= "hidden" then
        return view.u, view.v, view.zoom
    end
end

local function Install()
    installed = true
    map = WorldMapFrame
    sc = map.ScrollContainer
    frame = CreateFrame("Frame", nil, map)
    frame:SetPoint("TOPLEFT", sc, "TOPLEFT")
    frame:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT")
    frame:SetFrameLevel(LEVEL)
    frame:SetClipsChildren(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:Hide()
    local backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0, 0, 0, 1)
    local width, height = Geometry:Size()
    canvas = CreateFrame("Frame", nil, frame)
    canvas:SetSize(width, height)
    -- (the zone label, as Blizzard's area label: over the icons and the arrow)
    local labelFrame = CreateFrame("Frame", nil, frame)
    labelFrame:SetFrameLevel(ARROW_LEVEL + 1)
    labelFrame:SetScale(LABEL_SCALE)
    labelFrame:SetSize(400, 128)
    labelFrame:SetPoint("TOP", frame, "TOP")
    label = labelFrame:CreateFontString(nil, "OVERLAY", "WorldMapTextFont")
    label:SetPoint("TOP", labelFrame, "TOP", 0, LABEL_OFFSET)
    frame:SetScript("OnMouseWheel", OnMouseWheel)
    frame:SetScript("OnMouseDown", OnMouseDown)
    frame:SetScript("OnMouseUp", OnMouseUp)
    frame:SetScript("OnUpdate", OnUpdate)
    frame:SetScript("OnSizeChanged", function()
        if state ~= "hidden" then
            SetView(view.u, view.v, view.zoom, true)
        end
    end)
    sc:HookScript("OnMouseWheel", OnBlizzardWheel)
end

function View:Enable()
    if not installed then
        Install()
    end
    map:AddDataProvider(provider)
    listener:Start()
    -- (areas explored while the feature was off)
    Art:RefreshExplored()
end

function View:Disable()
    listener:Stop()
    map:RemoveDataProvider(provider)
    if state ~= "hidden" then
        Close()
    end
end
