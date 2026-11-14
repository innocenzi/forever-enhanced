-- Hosting the stitched art in Blizzard's map (WorldMapFrame), on the world,
-- continent and zone maps; other maps (dungeons, battlegrounds) stay as
-- Blizzard made them.
--   - Zoom runs from the whole world down to street level, toward the cursor:
--     our own animation (Blizzard eases zoom and pan apart, and the point under
--     the cursor wanders), so that point stays put and the map can be dragged
--     mid-zoom.
--   - The pan reaches the whole world, and a little past its edges once zoomed in.
--   - A click zooms into the zone or continent under the cursor, a right click
--     out a level. Other clicks are left to others (Shift Click, Alt Click), but a
--     map pin (Ctrl Click, or a click with the map's pin button on) over a map the
--     map underneath doesn't reach is placed on that map, where it was clicked.
--   - Once the view has rested, the map underneath becomes the zone (or
--     continent, or world) in its middle, and the view is put back exactly.
--     Never in combat, nor while a quest's details are open (Blizzard closes them
--     as soon as the map isn't the quest's).
-- Zoom: 1 = the whole world fits the view. What this writes into Blizzard's
-- frames, and why: feature.lua (TAINT).
--
-- From OpenMap's Map/WorldMap.lua (openmap-license.txt).

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")
local Geometry, Art, Arrow = Seamless.Geometry, Seamless.Art, Seamless.Arrow

local View = {}
Seamless.View = View

local WORLD = Geometry.WORLD
-- The art's frame levels: above Blizzard's explored areas, under every icon.
local FRAME_LEVEL = "PIN_FRAME_LEVEL_FOREVERENHANCED_SEAMLESS"
local ART_RANGE = 80

local ZOOM_STEP = 1.25 -- each wheel notch, and each zoom level
local MAX_ZOOM = 48 -- the deepest zoom
local CITY_ZOOM = 1.5 -- ... times this in a city, whose map is small
-- The map underneath becomes a zone at ENTER of the zoom where it fits the view,
-- and stays it down to LEAVE of that.
local ENTER, LEAVE = 0.9, 0.7
local ZOOM_RATE = 14 -- the wheel's approach, per second (in log zoom)
local GLIDE_SECONDS = 0.4
-- How long the view rests before the map underneath follows it: a change has
-- Blizzard refresh every map icon (every addon's), so not at every pause of a
-- zoom or a pan (the wheel's zoom runs on through quick notches: this only has to
-- outlast slower ones), but soon enough that the icons keep up with the view.
local SWITCH_AFTER = 0.1
local TICK = 0.05
-- How close Blizzard's easing must be to where it's going for the view to be still:
-- the pan within a view pixel, the zoom within this share.
local SETTLE_PX = 1
local SETTLE_SCALE = 0.001
-- How close our own zoom must be: the wheel's within this (log zoom), a glide this far through.
local ANIM_SETTLE = 0.02
local GLIDE_SETTLE = 0.85
-- Room past the world's edges (of its size), gained between zoom 1 and CENTRE_UNTIL:
-- zoomed right out the world is centred, and the wheel zooms at the cursor from the first notch.
local EDGE_SLACK = 0.2
local CENTRE_UNTIL = 1.6
-- A press that moved this far (squared, Blizzard's click distance) is a drag, even if it came back.
local CLICK_SLOP = 20
local CLICK_PRIORITY = 1000

local map, sc
local installed = false
local active = false -- the art is on the map underneath now
local switching = false -- we're changing the map underneath
local userMoved = false -- the view moved since Blizzard last put up a map (only then is it followed)
local wheelMode, scalingMode -- Blizzard's, put back on other maps
local anim -- the running zoom: { mode = "anchor" | "glide", ... }
local stillFor = 0
local press = {}

local function Clamp(value, low, high)
    return math.min(math.max(value, low), high)
end

-- Geometry of the view ------------------------------------------------------------------

-- View pixels per world unit when the whole world fits.
local function FitPx()
    local width, height = Geometry:Size()
    return math.min(sc:GetWidth() / width, sc:GetHeight() / height)
end

-- The map's canvas units per world unit.
local function CanvasPerWorld(mapID)
    local left, right = Geometry:Rect(mapID)
    return Geometry:ArtSize(mapID) / ((right - left) * Geometry:Size())
end

local function ZoomFor(mapID, scale)
    return scale * CanvasPerWorld(mapID) / FitPx()
end

local function ScaleFor(mapID, zoom)
    return zoom * FitPx() / CanvasPerWorld(mapID)
end

-- The zoom where the map just fits the view.
local function FitZoom(mapID)
    local width, height = Geometry:Size()
    local left, right, top, bottom = Geometry:Rect(mapID)
    return math.min(sc:GetWidth() / ((right - left) * width), sc:GetHeight() / ((bottom - top) * height)) / FitPx()
end

-- The layers fade by how much of the world is in view, its area, not by how far
-- it is from fitting it: a tall or very wide view fits the world across its narrow
-- side and shows much more of it the other way.
local function DetailScale()
    local width, height = Geometry:Size()
    local viewWidth, viewHeight = sc:GetWidth(), sc:GetHeight()
    return math.min(viewWidth / width, viewHeight / height) / math.sqrt(viewWidth * viewHeight / (width * height))
end

-- World units (normalized) per view pixel at `zoom`.
local function PerPx(zoom)
    local width, height = Geometry:Size()
    local px = FitPx() * zoom
    return 1 / (width * px), 1 / (height * px)
end

-- The view: its middle on the world (normalized) and its zoom.
local function CurrentView()
    local mapID = sc.mapID
    local u, v = Geometry:ToWorld(mapID, sc:GetCurrentScrollX() or 0.5, sc:GetCurrentScrollY() or 0.5)
    return u, v, ZoomFor(mapID, sc:GetCanvasScale())
end

-- Puts the view at once (InstantPanAndZoom without its drift toward the last pan).
local function SetView(scale, x, y)
    sc:InstantPanAndZoom(scale, x, y, true)
end

-- The view centred on a world point at `zoom`, at once.
local function ShowWorld(u, v, zoom)
    local mapID = sc.mapID
    local x, y = Geometry:FromWorld(mapID, u, v)
    SetView(ScaleFor(mapID, zoom), x, y)
end

-- The cursor from the middle of the view, in view pixels (y down).
local function CursorOffset()
    local x, y = GetCursorPosition()
    local scale = sc:GetEffectiveScale()
    return x / scale - (sc:GetLeft() + sc:GetWidth() / 2), (sc:GetTop() - sc:GetHeight() / 2) - y / scale
end

local function CursorWorld()
    local u, v, zoom = CurrentView()
    local sx, sy = CursorOffset()
    local pu, pv = PerPx(zoom)
    return u + sx * pu, v + sy * pv
end

local function MaxZoomAt(u, v)
    return MAX_ZOOM * (Geometry:IsInCity(u, v) and CITY_ZOOM or 1)
end

-- Zooming --------------------------------------------------------------------------------

-- The wheel: zoom about the point under the cursor (zooming in never takes it back out).
local function ZoomAtCursor(factor)
    local u, v, zoom = CurrentView()
    local sx, sy = CursorOffset()
    local pu, pv = PerPx(zoom)
    local from = anim and anim.mode == "anchor" and anim.target or zoom
    local most = MaxZoomAt(u + sx * pu, v + sy * pv)
    if factor > 1 then
        most = math.max(most, from)
    end
    anim = {
        mode = "anchor",
        u = u + sx * pu,
        v = v + sy * pv,
        sx = sx,
        sy = sy,
        target = Clamp(from * factor, 1, most),
    }
    userMoved = true
end

-- Glides the view to a world point at `zoom`, as one zoom about a fixed point.
local function GlideTo(u, v, zoom)
    local u0, v0, z0 = CurrentView()
    anim = { mode = "glide", u0 = u0, v0 = v0, z0 = z0, u1 = u, v1 = v, z1 = Clamp(zoom, 1, MaxZoomAt(u, v)), t = 0 }
    userMoved = true
end

local function Animate(elapsed)
    local a = anim
    if a.mode == "anchor" then
        local _, _, current = CurrentView()
        local logZoom = math.log(current)
            + (math.log(a.target) - math.log(current)) * (1 - math.exp(-elapsed * ZOOM_RATE))
        local zoom = math.exp(logZoom)
        local done = math.abs(math.log(a.target / zoom)) < 0.003
        if done then
            zoom = a.target
        end
        local down = sc.mouseButtonInfo.LeftButton.down
        if down and not a.down then
            -- grabbed mid-zoom: what's under the cursor now is what the cursor carries
            local u, v = CurrentView()
            local sx, sy = CursorOffset()
            local pu, pv = PerPx(current)
            a.u, a.v, a.sx, a.sy = u + sx * pu, v + sy * pv, sx, sy
        elseif down then
            a.sx, a.sy = CursorOffset()
        end
        a.down = down
        local pu, pv = PerPx(zoom)
        ShowWorld(a.u - a.sx * pu, a.v - a.sy * pv, zoom)
        if done then
            anim = nil
        end
    else
        a.t = math.min(1, a.t + elapsed / GLIDE_SECONDS)
        local e = a.t * a.t * (3 - 2 * a.t)
        local zoom = math.exp(math.log(a.z0) + (math.log(a.z1) - math.log(a.z0)) * e)
        -- the middle moves with 1/zoom: what zooming about one fixed point looks like
        local w = math.abs(a.z1 - a.z0) < 1e-6 and e or (1 / a.z0 - 1 / zoom) / (1 / a.z0 - 1 / a.z1)
        ShowWorld(a.u0 + (a.u1 - a.u0) * w, a.v0 + (a.v1 - a.v0) * w, zoom)
        if a.t >= 1 then
            anim = nil
        end
    end
end

-- The map underneath ---------------------------------------------------------------------

-- The deepest map under (u, v) the view is close enough to: the world, a continent or a zone.
local function PickMap(u, v, zoom, current)
    local pick = WORLD
    for _, mapID in ipairs(Geometry:ChainAt(u, v)) do
        local share = mapID == current and LEAVE or ENTER
        if mapID ~= WORLD and Geometry:IsStitchable(mapID) and zoom >= FitZoom(mapID) * share then
            pick = mapID
        end
    end
    return pick
end

local function Switch(target)
    local u, v, zoom = CurrentView()
    switching = true
    local ok, err = pcall(map.SetMapID, map, target)
    switching = false
    if not ok then
        geterrorhandler()(err)
        return
    end
    if active then
        local x, y = Geometry:FromWorld(target, u, v)
        SetView(ScaleFor(target, zoom), x, y)
    end
end

-- Whether `current` (or nothing yet) is within `tolerance` of `target`.
local function Within(current, target, tolerance)
    return not current or math.abs(current - target) <= tolerance
end

-- Whether our zoom is as good as done: the wheel's within ANIM_SETTLE of its zoom
-- (its approach slows down for a third of its time over the last few percent), a
-- glide through most of its way.
local function IsAnimSettled()
    if not anim then
        return true
    end
    if anim.mode == "anchor" then
        local _, _, zoom = CurrentView()
        return math.abs(math.log(anim.target / zoom)) < ANIM_SETTLE
    end
    return anim.t >= GLIDE_SETTLE
end

-- Not moving: no zoom running (or nearly done), no drag, Blizzard's own easing as
-- good as done. (After a drag, Blizzard's pan glides on and closes in on where it
-- ends for most of a second, by less than a pixel: still, for the map underneath.)
local function IsSettled()
    if sc.mouseButtonInfo.LeftButton.down or not IsAnimSettled() then
        return false
    end
    local scale = sc.targetScale
    return Within(sc.currentScale, scale, scale * SETTLE_SCALE)
        and Within(sc.currentScrollX, sc.targetScrollX, sc:NormalizeHorizontalSize(SETTLE_PX / scale))
        and Within(sc.currentScrollY, sc.targetScrollY, sc:NormalizeVerticalSize(SETTLE_PX / scale))
end

-- The player's position on `mapID` (normalized), unless the game keeps it secret.
local function PlayerOn(mapID)
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if position and not issecretvalue(position.x) and not issecretvalue(position.y) then
        return position.x, position.y
    end
end

-- The player's arrow, where the map underneath can't show them.
local function UpdateArrow()
    local x, y = PlayerOn(sc.mapID)
    if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        Arrow:Hide()
        return
    end
    local best = C_Map.GetBestMapForUnit("player")
    x, y = nil, nil
    if best and Geometry:Rect(best) then
        x, y = PlayerOn(best)
    end
    local facing = GetPlayerFacing()
    if not x or not facing or issecretvalue(facing) then
        Arrow:Hide()
        return
    end
    local u, v = Geometry:ToWorld(best, x, y)
    local cu, cv, zoom = CurrentView()
    local pu, pv = PerPx(zoom)
    local dx, dy = (u - cu) / pu, (v - cv) / pv
    if math.abs(dx) > sc:GetWidth() / 2 or math.abs(dy) > sc:GetHeight() / 2 then
        Arrow:Hide()
        return
    end
    local level = map:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_GROUP_MEMBER")
    Arrow:Show(sc, level, dx, -dy, facing)
end

local ticker = CreateFrame("Frame")
ticker:Hide()
local sinceTick = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    sinceTick = sinceTick + elapsed
    if sinceTick < TICK then
        return
    end
    local tick = sinceTick
    sinceTick = 0
    if not active then
        return
    end
    UpdateArrow()
    stillFor = IsSettled() and stillFor + tick or 0
    if
        userMoved
        and stillFor >= SWITCH_AFTER
        and not InCombatLockdown()
        and not QuestMapFrame.DetailsFrame.questMapID
    then
        local u, v, zoom = CurrentView()
        local target = PickMap(u, v, zoom, sc.mapID)
        if target ~= sc.mapID then
            Switch(target)
        end
    end
end)

-- The art follows the view ---------------------------------------------------------------

-- (Blizzard reports a pan several times a frame: the art near the view is worked out once, next frame)
local viewFrame = CreateFrame("Frame")
viewFrame:Hide()
viewFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    if not active or not map:IsShown() then
        return
    end
    local u, v, zoom = CurrentView()
    local pu, pv = PerPx(zoom)
    local halfU, halfV = sc:GetWidth() / 2 * pu, sc:GetHeight() / 2 * pv
    Art:Cull(u - halfU, v - halfV, u + halfU, v + halfV)
    -- (on the view, not the canvas: it moves with every pan and zoom, not only the ticker's)
    UpdateArrow()
end)

local function ApplyView()
    if active then
        viewFrame:Show()
    end
end

local function ApplyZoom()
    if not active then
        return
    end
    local _, _, zoom = CurrentView()
    Art:SetZoom(zoom * DetailScale())
    ApplyView()
end

-- Blizzard's own art for the map underneath (its tiles and explored areas): under ours, so hidden while ours shows.
local function BlizzardArt()
    for layer in map.detailLayerPool:EnumerateActive() do
        layer:SetShown(not active)
    end
    for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        pin:SetShown(not active)
    end
end

-- Whether the art goes on `mapID` (the map Blizzard's is about to show), and laying it out there.
local function Attach(mapID)
    active = Seamless:IsActive() and Geometry:IsStitchable(mapID) and Art:IsBuilt() and Art:Layout(mapID) or false
    Art:SetShown(active)
    BlizzardArt()
    if active then
        sc:SetMouseWheelZoomMode(MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_NONE)
        sc:SetScalingMode("SCALING_MODE_LINEAR")
        ticker:SetShown(map:IsShown())
    else
        sc:SetMouseWheelZoomMode(wheelMode)
        sc:SetScalingMode(scalingMode)
        ticker:Hide()
        anim = nil
        Arrow:Hide()
    end
end

-- Hooks into Blizzard's map --------------------------------------------------------------

-- Zoom levels from the whole world to street level, in the map's scale (after Blizzard's own).
local function OnCreateZoomLevels(self)
    if not Seamless:IsActive() then
        return
    end
    if not Art:IsBuilt() then
        local level = map:GetPinFrameLevelsManager():GetValidFrameLevel(FRAME_LEVEL)
        Art:Build(map:GetCanvas(), level, ART_RANGE)
    end
    Attach(self.mapID)
    if not active then
        return
    end
    local levels = {}
    local deepest = MAX_ZOOM * CITY_ZOOM
    local zoom = 1
    while zoom < deepest * ZOOM_STEP do
        table.insert(levels, { scale = ScaleFor(self.mapID, math.min(zoom, deepest)), layerIndex = 1 })
        zoom = zoom * ZOOM_STEP
    end
    self.zoomLevels = levels
    -- (panning allowed from the whole world's view)
    self.baseScale = levels[1].scale
end

-- Blizzard put up a map (opening, the quest log, the map's dropdown): it shows
-- whole, as Blizzard's would. (Its own reset went to the first zoom level: the world.)
local function OnResetZoom(self)
    if not active or switching then
        return
    end
    userMoved = false
    anim = nil
    SetView(ScaleFor(self.mapID, FitZoom(self.mapID)), 0.5, 0.5)
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

-- The pan's reach: the whole world (in the map underneath's normalized units), not only that map.
local function Extents(self, scale)
    local mapID = self.mapID
    local halfX = self:NormalizeHorizontalSize(self:GetWidth() * 0.5 / scale)
    local halfY = self:NormalizeVerticalSize(self:GetHeight() * 0.5 / scale)
    local x0, y0 = Geometry:FromWorld(mapID, 0, 0)
    local x1, y1 = Geometry:FromWorld(mapID, 1, 1)
    local t = Clamp((ZoomFor(mapID, scale) - 1) / (CENTRE_UNTIL - 1), 0, 1)
    local minX, maxX = Range(x0, x1, halfX, (x1 - x0) * EDGE_SLACK, t)
    local minY, maxY = Range(y0, y1, halfY, (y1 - y0) * EDGE_SLACK, t)
    return minX, maxX, minY, maxY
end

local function OnMouseWheel(_, delta)
    if active then
        ZoomAtCursor(delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP)
    end
end

-- The map grabbed: the view is the player's now, and a glide stops where it is.
local function OnMouseDown(_, button)
    if not active then
        return
    end
    userMoved = true
    if anim and anim.mode == "glide" then
        anim = nil
    end
    if button == "LeftButton" then
        press.x, press.y = sc:GetCursorPosition()
        press.moved = false
    end
end

-- A press that wandered off and came back isn't a click (Blizzard only compares where it went down and up).
local function TrackPress()
    if press.moved or not press.x or not sc.mouseButtonInfo.LeftButton.down then
        return
    end
    local x, y = sc:GetCursorPosition()
    local dx, dy = x - press.x, y - press.y
    if dx * dx + dy * dy > CLICK_SLOP then
        press.moved = true
    end
end

-- After Blizzard's own OnUpdate, so its easing never adds to ours.
local function OnUpdate(_, elapsed)
    if not active then
        anim = nil
        return
    end
    TrackPress()
    if anim then
        Animate(elapsed)
    end
end

-- A map pin (Ctrl Click, or a click with the map's pin button on) where the map
-- underneath doesn't reach: on the deepest map under the cursor that takes one, as
-- Blizzard places it on the map underneath (which would put it on that map's edge).
-- False when it's Blizzard's to place.
local function PlacePin(u, v)
    local x, y = Geometry:FromWorld(sc.mapID, u, v)
    if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        return false
    end
    local chain = Geometry:ChainAt(u, v)
    for index = #chain, 1, -1 do
        local mapID = chain[index]
        if C_Map.CanSetUserWaypointOnMap(mapID) then
            local pinPressed = map.WorldMapTrackingPinButton and map.WorldMapTrackingPinButton.isActive
            PlaySound(pinPressed and SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE or SOUNDKIT.UI_MAP_WAYPOINT_CONTROL_CLICK)
            ns:ShieldObjectiveTracker(function()
                C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, Geometry:FromWorld(mapID, u, v)))
                C_SuperTrack.SetSuperTrackedUserWaypoint(false)
            end)
            return true
        end
    end
    UIErrorsFrame:AddMessage(MAP_PIN_INVALID_MAP, RED_FONT_COLOR:GetRGBA())
    return true
end

-- A click: into the next map down under the cursor; a right click: out to the map above.
local function OnCanvasClick(_, button)
    if not active then
        return false
    end
    local pinPressed = map.WorldMapTrackingPinButton and map.WorldMapTrackingPinButton.isActive
    if button == "LeftButton" and (pinPressed or IsControlKeyDown()) then
        return PlacePin(CursorWorld())
    end
    if IsModifierKeyDown() then
        return false
    end
    if button == "LeftButton" and press.moved then
        return true
    end
    local u, v = CursorWorld()
    local _, _, zoom = CurrentView()
    local chain = Geometry:ChainAt(u, v)
    local target
    if button == "LeftButton" then
        for _, mapID in ipairs(chain) do
            if not target and mapID ~= WORLD and Geometry:IsStitchable(mapID) and FitZoom(mapID) > zoom * 1.05 then
                target = mapID
            end
        end
    elseif button == "RightButton" then
        target = WORLD
        for _, mapID in ipairs(chain) do
            if mapID ~= WORLD and Geometry:IsStitchable(mapID) and FitZoom(mapID) < zoom * 0.95 then
                target = mapID
            end
        end
    else
        return false
    end
    if target then
        local left, right, top, bottom = Geometry:Rect(target)
        GlideTo((left + right) / 2, (top + bottom) / 2, FitZoom(target))
    end
    return true
end

local provider = CreateFromMixins(MapCanvasDataProviderMixin)

function provider:OnShow()
    if active then
        ticker:Show()
        BlizzardArt()
        Art:Recull()
        ApplyZoom()
    end
end

function provider:OnHide()
    ticker:Hide()
    anim = nil
    Arrow:Hide()
end

-- (Blizzard's explored areas are put up again by their own provider on a map change,
-- after the detail layers: hidden again here)
function provider:OnMapChanged()
    BlizzardArt()
    ApplyZoom()
end

function provider:OnCanvasScaleChanged()
    ApplyZoom()
end

function provider:OnCanvasPanChanged()
    ApplyView()
end

local listener = ns:CreateEventListener({
    MAP_EXPLORATION_UPDATED = function()
        Art:RefreshExplored()
    end,
})

local function Install()
    installed = true
    map = WorldMapFrame
    sc = map.ScrollContainer
    wheelMode = sc.mouseWheelZoomMode
    scalingMode = sc:ScalingMode()
    map:GetPinFrameLevelsManager():InsertFrameLevelAbove(FRAME_LEVEL, "PIN_FRAME_LEVEL_MAP_EXPLORATION", ART_RANGE)
    hooksecurefunc(sc, "CreateZoomLevels", OnCreateZoomLevels)
    hooksecurefunc(sc, "ResetZoom", OnResetZoom)
    local blizzardExtents = sc.CalculateScrollExtentsAtScale
    sc.CalculateScrollExtentsAtScale = function(self, scale)
        if active then
            return Extents(self, scale)
        end
        return blizzardExtents(self, scale)
    end
    hooksecurefunc(map, "RefreshDetailLayers", function()
        if Seamless:IsActive() then
            BlizzardArt()
        end
    end)
    sc:HookScript("OnMouseWheel", OnMouseWheel)
    sc:HookScript("OnMouseDown", OnMouseDown)
    sc:HookScript("OnUpdate", OnUpdate)
    map:AddCanvasClickHandler(OnCanvasClick, CLICK_PRIORITY)
end

-- Lays Blizzard's map out again for the map it shows: zoom levels, view, art (through our hooks while active).
local function Relayout()
    if sc.mapID then
        sc:OnCanvasSizeChanged()
    end
end

function View:Enable()
    if not installed then
        Install()
    end
    map:AddDataProvider(provider)
    listener:Start()
    -- (areas explored while the feature was off)
    Art:RefreshExplored()
    Relayout()
end

function View:Disable()
    listener:Stop()
    map:RemoveDataProvider(provider)
    Attach(sc.mapID)
    Relayout()
end
