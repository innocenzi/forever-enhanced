-- The stitched art: every zone's map on one canvas. Each region is placed once,
-- in world units, on `root`; Layout only scales and moves root into the canvas
-- units of whichever map Blizzard's map shows (the host), so nothing else moves
-- when the map underneath changes.
--
-- Layers, bottom to top, and the zoom where each fades in. The zoom is by how much
-- of the world is in view (View's DetailScale): 1, the whole world's area.
--   world        blank sea (media/sea.png: a zone map's open sea), then Azeroth's art, always
--   continents   their art, edges faded (CONTINENTS_IN), and blank land paper
--                (media/land.png: a zone map's undiscovered parchment) on their land
--                (media/land/: inland, off the zones' seas)
--                As the zones come in (MUTE), the world's and continents' art fades out
--                (at that zoom it's blurry, its names huge) and the land paper in: past
--                every zone's map there's blank paper, sea and land, as on a map
--                that doesn't draw a place.
--   zones        each zone once, one frame per zone, biggest first: its base art and
--                its explored-area pieces (explored ones from the client, the rest
--                from Seamless.Pieces, shown with "unexplored" on), all through its
--                share of the world (media/zone, tools/seamless/ownership.ts: every
--                place inside some zone's map is one zone's, fading into the next),
--                tinted toward the palette every zone shares (Seamless.Tints) (DETAIL)
--   cities       their base art, round-faded, as they come to fill the view (CITY_IN)
-- A zone without its share takes its whole map less a thin border (media/feather-thin).
--
-- Only what's near the view is drawn (Cull): a zone's textures get their file
-- the first time they come near it, a few each frame (the loader), fading in.
-- A hidden texture lets go of its anchor: the game lays out again everything
-- anchored to a frame that moves, hidden or not, on each frame of a pan or zoom.

local _, ns = ...

local Seamless = ns:GetFeature("map", "seamless")
local Geometry = Seamless.Geometry

local Art = {}
Seamless.Art = Art

local WORLD = Geometry.WORLD
local MEDIA = Seamless.MEDIA
local FEATHER_THIN = MEDIA .. "feather-thin.png"
local FEATHER_WIDE = MEDIA .. "feather-wide.png"
local FEATHER_ROUND = MEDIA .. "feather-round.png"

-- Zooms each layer fades in across: { from, to }.
local CONTINENTS_IN = { 1.3, 1.7 }
-- The zones' detail: a hint of it from DETAIL_HINT (at HINT strength), all of it by DETAIL.
local DETAIL_HINT = { 1.8, 3 }
local HINT = 0.3
local DETAIL = { 3, 4.5 }
-- A city: shares of the zoom where it fills the view.
local CITY_IN = { 0.2, 0.4 }
-- The world and continent art giving way to blank paper. The sea paper reaches
-- SEA_REACH world sizes past the world on every side; a paper tile spans as much of the
-- world as on the map it comes from (Seamless.Papers), drawn twice: at its size, and at
-- PAPER_OVER times it at PAPER_OVER_ALPHA, offset, so its tiling never shows.
local MUTE = { 4, 7 }
local SEA_REACH = 1
local PAPER_OVER, PAPER_OVER_ALPHA, PAPER_OVER_SHIFT = 2.618, 0.5, 0.37

-- Files set per frame: at least LOAD_LEAST, a queue's share over LOAD_FRAMES, at most LOAD_MOST.
local LOAD_LEAST, LOAD_FRAMES, LOAD_MOST = 40, 6, 60
local LOAD_FADE = 0.3

-- The box round the view whose art is drawn: MARGIN of the view's size past
-- it on every side; redone once the view comes KEEP of its size near the box's
-- edge, or zoomed in ZOOM_IN times since (the box would be much too big).
local MARGIN, KEEP, ZOOM_IN = 0.35, 0.1, 1.6

local root
local layers = {}
local worldWidth, worldHeight
local hostMapID, hostScale
local zoomNow = 1
local muted
local detailShown = false
local unexploredShown = false
local cullBox

-- region -> { x, y, width, height } in world units
local places = {}
-- texture -> its file, until the loader sets it
local files = {}
-- texture -> whether ShowZone shows it
local shown = {}
-- mapID -> { kind = "zone" | "city", entries = { { texture, u0, v0, u1, v1, piece } }, near, visible }
local zones = {}
-- { frame, mapID, fill = the zoom where it fills the view, alpha }
local cities = {}
-- mapID -> piece key -> { unexplored }: one per piece, shared by its copies
local pieces = {}
-- the world's and continents' art textures, muted as the zones come in
local backdrop = {}
-- the continents' blank land paper, faded in as their art fades out
local papers = {}

local function Anchor(region)
    local place = places[region]
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", root, "TOPLEFT", place[1], -place[2])
    region:SetSize(place[3], place[4])
end

local function Put(region, x, y, width, height)
    places[region] = { x, y, width, height }
    Anchor(region)
end

-- 0 to 1 as the zoom now goes from `from` to `to`, eased.
local function Smooth(from, to)
    local t = math.max(0, math.min(1, (zoomNow - from) / (to - from)))
    return t * t * (3 - 2 * t)
end

-- Below this alpha, a layer is gone: hidden (drawn at alpha 0 it still costs its size in fill).
local GONE = 0.003

local function Fade(region, alpha)
    region:SetAlpha(alpha)
    region:SetShown(alpha > GONE)
end

-- The file loader ------------------------------------------------------------------------

-- The textures waiting for their file: queue[queueStart] to queue[queueEnd]. (Its ends are
-- counted: once its front is taken, the table has holes, and # can't measure it.)
local queue, queueStart, queueEnd = {}, 1, 0
local queued = {}
local fading = {}
local loader = CreateFrame("Frame")
loader:Hide()

local function Load(texture)
    if files[texture] and not queued[texture] then
        queued[texture] = true
        queueEnd = queueEnd + 1
        queue[queueEnd] = texture
        loader:Show()
    end
end

loader:SetScript("OnUpdate", function(self)
    local now = GetTime()
    local waiting = queueEnd - queueStart + 1
    local most = math.min(LOAD_MOST, math.max(LOAD_LEAST, math.ceil(waiting / LOAD_FRAMES)))
    for _ = 1, math.min(most, waiting) do
        local texture = queue[queueStart]
        queue[queueStart] = nil
        queueStart = queueStart + 1
        queued[texture] = nil
        texture:SetTexture(files[texture], nil, nil, "TRILINEAR")
        files[texture] = nil
        texture:SetAlpha(0)
        fading[texture] = now
    end
    if queueStart > queueEnd then
        queue, queueStart, queueEnd = {}, 1, 0
    end
    for texture, start in pairs(fading) do
        local t = (now - start) / LOAD_FADE
        if t >= 1 then
            texture:SetAlpha(1)
            fading[texture] = nil
        else
            texture:SetAlpha(t * t * (3 - 2 * t))
        end
    end
    if queueStart > queueEnd and next(fading) == nil then
        self:Hide()
    end
end)

-- Placing art ----------------------------------------------------------------------------

local function Pow2(n)
    local p = 16
    while p < n do
        p = p * 2
    end
    return p
end

-- A map's art rectangle in world units: left, top, world units per art pixel (sx, sy), its art layer.
local function Placement(mapID)
    local artWidth, artHeight, layer = Geometry:ArtSize(mapID)
    local left, right, top, bottom = Geometry:Rect(mapID)
    if not artWidth or not left then
        return nil
    end
    return {
        left = left * worldWidth,
        top = top * worldHeight,
        sx = (right - left) * worldWidth / artWidth,
        sy = (bottom - top) * worldHeight / artHeight,
        layer = layer,
    }
end

-- A mask over a map's whole art, on `parent` (it masks textures of that frame).
local function Mask(parent, placement, file)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    local layer = placement.layer
    Put(mask, placement.left, placement.top, layer.layerWidth * placement.sx, layer.layerHeight * placement.sy)
    return mask
end

-- An image `width` x `height` at (x, y) in a map's art, cut in the art's tiles (file IDs,
-- row-major). A base art's tiles are whole files cropped at the art's edge; an overlay's
-- last row and column are files of the next power of two. With `options.entries`, the
-- tiles are a zone's: their files wait for ShowZone, and they're listed there.
local function Tiles(parent, placement, list, x, y, width, height, options)
    local layer = placement.layer
    local tileWidth, tileHeight = layer.tileWidth, layer.tileHeight
    local cols, rows = math.ceil(width / tileWidth), math.ceil(height / tileHeight)
    for row = 1, rows do
        local pixelHeight = row < rows and tileHeight or height - (rows - 1) * tileHeight
        local fileHeight = (row < rows or not options.overlay) and tileHeight or Pow2(pixelHeight)
        for col = 1, cols do
            local file = list[(row - 1) * cols + col]
            local pixelWidth = col < cols and tileWidth or width - (cols - 1) * tileWidth
            local fileWidth = (col < cols or not options.overlay) and tileWidth or Pow2(pixelWidth)
            if file and pixelWidth > 0 and pixelHeight > 0 then
                local tx = placement.left + (x + (col - 1) * tileWidth) * placement.sx
                local ty = placement.top + (y + (row - 1) * tileHeight) * placement.sy
                local tw, th = pixelWidth * placement.sx, pixelHeight * placement.sy
                local texture = parent:CreateTexture(nil, "ARTWORK", nil, options.sublevel or 0)
                texture:SetTexCoord(0, pixelWidth / fileWidth, 0, pixelHeight / fileHeight)
                for _, mask in ipairs(options.masks) do
                    texture:AddMaskTexture(mask)
                end
                if options.tint then
                    texture:SetVertexColor(options.tint[1], options.tint[2], options.tint[3])
                end
                places[texture] = { tx, ty, tw, th }
                if options.entries then
                    files[texture] = tonumber(file) or file
                    texture:Hide()
                    table.insert(options.entries, {
                        texture,
                        tx / worldWidth,
                        ty / worldHeight,
                        (tx + tw) / worldWidth,
                        (ty + th) / worldHeight,
                        options.piece,
                    })
                else
                    texture:SetTexture(tonumber(file) or file, nil, nil, "TRILINEAR")
                    Anchor(texture)
                    table.insert(backdrop, texture)
                end
            end
        end
    end
end

-- A map's whole base art.
local function BaseArt(parent, mapID, masks, entries, tint)
    local placement = Placement(mapID)
    local list = placement and C_Map.GetMapArtLayerTextures(mapID, 1)
    if not list or #list == 0 then
        return
    end
    local layer = placement.layer
    local options = { masks = masks(placement), entries = entries, tint = tint }
    Tiles(parent, placement, list, 0, 0, layer.layerWidth, layer.layerHeight, options)
end

local function PieceKey(width, height, x, y)
    return width .. ":" .. height .. ":" .. x .. ":" .. y
end

-- Every explored-area piece of a zone: fn(files, x, y, width, height, piece). The client
-- lists the explored ones; the rest come from the game's tables (Seamless.Pieces).
local function EachPiece(mapID, fn)
    pieces[mapID] = pieces[mapID] or {}
    local seen = {}
    local function Piece(key, unexplored)
        local piece = pieces[mapID][key] or {}
        piece.unexplored = unexplored
        pieces[mapID][key] = piece
        return piece
    end
    for _, info in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
        local key = PieceKey(info.textureWidth, info.textureHeight, info.offsetX, info.offsetY)
        seen[key] = true
        if not info.isShownByMouseOver then
            local piece = Piece(key, false)
            fn(info.fileDataIDs, info.offsetX, info.offsetY, info.textureWidth, info.textureHeight, piece)
        end
    end
    for _, data in ipairs(Seamless.Pieces[C_Map.GetMapArtID(mapID)] or {}) do
        local key = PieceKey(data[1], data[2], data[3], data[4])
        if not seen[key] then
            fn({ select(5, unpack(data)) }, data[3], data[4], data[1], data[2], Piece(key, true))
        end
    end
end

-- Whether the zone has explored-area pieces (else it's a city).
local function HasPieces(mapID)
    return #(Seamless.Pieces[C_Map.GetMapArtID(mapID)] or {}) > 0
        or #(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) > 0
end

-- A zone, on its own frame: its base art, then its pieces, all through its share of the world.
local function ZoneArt(frame, mapID, entries)
    local placement = Placement(mapID)
    if not placement then
        return
    end
    local share = Seamless.Zones[mapID] and MEDIA .. "zone\\" .. mapID .. ".png" or FEATHER_THIN
    local masks = { Mask(frame, placement, share) }
    local tint = Seamless.Tints[mapID]
    BaseArt(frame, mapID, function()
        return masks
    end, entries, tint)
    EachPiece(mapID, function(list, x, y, width, height, piece)
        -- (explored pieces over the rest, where they overlap)
        local options = {
            overlay = true,
            sublevel = piece.unexplored and 1 or 2,
            masks = masks,
            entries = entries,
            piece = piece,
            tint = tint,
        }
        Tiles(frame, placement, list, x, y, width, height, options)
    end)
end

-- Showing what's near the view ------------------------------------------------------------

local function IsNear(entry)
    local box = cullBox
    return entry[4] > box[1] and entry[2] < box[3] and entry[5] > box[2] and entry[3] < box[4]
end

-- Shows the zone's textures near the view, as far as its layer shows, and loads their files.
local function ShowZone(mapID)
    local zone = zones[mapID]
    local drawn = zone.near and (zone.kind == "zone" and detailShown or zone.kind == "city" and zone.visible)
    for _, entry in ipairs(zone.entries) do
        local texture, piece = entry[1], entry[6]
        local show = drawn and IsNear(entry) and not (piece and piece.unexplored and not unexploredShown) or false
        if shown[texture] ~= show then
            shown[texture] = show
            if show then
                Anchor(texture)
                texture:Show()
                Load(texture)
            else
                texture:Hide()
                texture:ClearAllPoints()
            end
        end
    end
end

local function ShowZones()
    if not cullBox then
        return
    end
    for mapID in pairs(zones) do
        ShowZone(mapID)
    end
end

-- Building -------------------------------------------------------------------------------

-- Blank paper ("land" or "sea", media/<kind>.png) tiled over a rectangle in world units,
-- twice (PAPER_OVER): the two textures, the second over the first (its strength in its
-- vertex colour).
local function Paper(parent, drawLayer, sublevel, kind, x, y, width, height)
    local list = {}
    for copy = 1, 2 do
        local tile = Seamless.Papers[kind] * (copy == 1 and 1 or PAPER_OVER)
        local shift = copy == 1 and 0 or PAPER_OVER_SHIFT
        local texture = parent:CreateTexture(nil, drawLayer, nil, sublevel + copy - 1)
        texture:SetTexture(MEDIA .. kind .. ".png", "REPEAT", "REPEAT")
        texture:SetTexCoord(shift, shift + width / tile, shift * 1.7, shift * 1.7 + height / tile)
        texture:SetVertexColor(1, 1, 1, copy == 1 and 1 or PAPER_OVER_ALPHA)
        Put(texture, x, y, width, height)
        table.insert(list, texture)
    end
    return list
end

-- A frame for art at frame level `level`, under `parent` (root by default) for its alpha.
local function Layer(level, parent)
    local frame = CreateFrame("Frame", nil, parent or root)
    frame:SetAllPoints(root)
    frame:SetFrameLevel(level)
    return frame
end

-- Builds the art on `canvas` (Blizzard's map canvas), between frame levels
-- `level` and `level + range`.
function Art:Build(canvas, level, range)
    worldWidth, worldHeight = Geometry:Size()
    root = CreateFrame("Frame", nil, canvas)
    root:SetSize(1, 1)
    root:SetFrameLevel(level)
    root:Hide()
    layers.world = Layer(level)
    layers.continents = Layer(level + 1)
    layers.zones = Layer(level + 2)
    layers.cities = Layer(level + range - 1)

    local reachX, reachY = SEA_REACH * worldWidth, SEA_REACH * worldHeight
    Paper(layers.world, "BACKGROUND", -8, "sea", -reachX, -reachY, worldWidth + 2 * reachX, worldHeight + 2 * reachY)
    BaseArt(layers.world, WORLD, function()
        return {}
    end)
    for _, info in ipairs(C_Map.GetMapChildrenInfo(WORLD, Enum.UIMapType.Continent, true) or {}) do
        if Geometry:IsStitchable(info.mapID) then
            BaseArt(layers.continents, info.mapID, function(placement)
                return { Mask(layers.continents, placement, FEATHER_WIDE) }
            end)
            local placement = Placement(info.mapID)
            if Seamless.Lands[info.mapID] and placement then
                local layer = placement.layer
                local width, height = layer.layerWidth * placement.sx, layer.layerHeight * placement.sy
                local land = Mask(layers.continents, placement, MEDIA .. "land\\" .. info.mapID .. ".png")
                local list =
                    Paper(layers.continents, "ARTWORK", 1, "land", placement.left, placement.top, width, height)
                for _, paper in ipairs(list) do
                    paper:AddMaskTexture(land)
                    table.insert(papers, paper)
                end
            end
        end
    end

    -- Zones biggest first, so small zones land on top. A zone without explored-area
    -- pieces is a city.
    local list = {}
    local area = {}
    for _, info in ipairs(C_Map.GetMapChildrenInfo(WORLD, Enum.UIMapType.Zone, true) or {}) do
        local left, right, top, bottom = Geometry:Rect(info.mapID)
        if left and Geometry:ArtSize(info.mapID) then
            area[info.mapID] = (right - left) * (bottom - top)
            table.insert(list, info.mapID)
        end
    end
    table.sort(list, function(a, b)
        return area[a] > area[b] or area[a] == area[b] and a < b
    end)
    local zoneLevel = level + 2
    for _, mapID in ipairs(list) do
        local entries = {}
        if HasPieces(mapID) then
            zoneLevel = math.min(zoneLevel + 1, level + range - 2)
            ZoneArt(Layer(zoneLevel, layers.zones), mapID, entries)
            zones[mapID] = { kind = "zone", entries = entries }
        else
            local frame = Layer(level + range - 1, layers.cities)
            BaseArt(frame, mapID, function(placement)
                return { Mask(frame, placement, FEATHER_ROUND) }
            end, entries)
            local left, right = Geometry:Rect(mapID)
            zones[mapID] = { kind = "city", entries = entries }
            table.insert(cities, { frame = frame, mapID = mapID, fill = 1 / (right - left) })
        end
    end
end

function Art:IsBuilt()
    return root ~= nil
end

function Art:SetShown(shownNow)
    if root then
        root:SetShown(shownNow)
    end
end

-- Lays the art out in `mapID`'s canvas units: root's scale and corner. False when the map isn't on the world.
function Art:Layout(mapID)
    local artWidth = Geometry:ArtSize(mapID)
    local left, right, top = Geometry:Rect(mapID)
    if not root or not artWidth or not left then
        return false
    end
    local scale = artWidth / ((right - left) * worldWidth)
    -- (the same map again, each time the map opens: moving root would lay out everything under it again)
    if hostMapID == mapID and hostScale == scale then
        return true
    end
    hostMapID, hostScale = mapID, scale
    root:SetScale(scale)
    root:ClearAllPoints()
    -- (offsets in root's own, scaled, units)
    root:SetPoint("TOPLEFT", root:GetParent(), "TOPLEFT", -left * worldWidth, top * worldHeight)
    return true
end

-- The layers' fades for `zoom` (by how much of the world is in view: see the top of the file).
function Art:SetZoom(zoom)
    if not root then
        return
    end
    zoomNow = zoom
    Fade(layers.continents, Smooth(CONTINENTS_IN[1], CONTINENTS_IN[2]))
    -- (in steps: every world and continent texture is redrawn on a change)
    local mute = math.floor(Smooth(MUTE[1], MUTE[2]) * 20 + 0.5) / 20
    if mute ~= muted then
        muted = mute
        for _, texture in ipairs(backdrop) do
            Fade(texture, 1 - mute)
        end
        for _, paper in ipairs(papers) do
            Fade(paper, mute)
        end
    end
    local detail = HINT * Smooth(DETAIL_HINT[1], DETAIL_HINT[2]) + (1 - HINT) * Smooth(DETAIL[1], DETAIL[2])
    Fade(layers.zones, detail)
    local detailNow = detail > 0.001
    local changed = detailNow ~= detailShown
    detailShown = detailNow
    for _, city in ipairs(cities) do
        local alpha = Smooth(CITY_IN[1] * city.fill, CITY_IN[2] * city.fill)
        if city.alpha ~= alpha then
            city.alpha = alpha
            Fade(city.frame, alpha)
            local zone = zones[city.mapID]
            if zone.visible ~= (alpha > GONE) then
                zone.visible = alpha > GONE
                if cullBox and not changed then
                    ShowZone(city.mapID)
                end
            end
        end
    end
    if changed then
        ShowZones()
    end
end

-- Draws only the art near the view: (u0, v0) to (u1, v1) on the world.
function Art:Cull(u0, v0, u1, v1)
    if not root then
        return
    end
    local width, height = u1 - u0, v1 - v0
    local box = cullBox
    if
        box
        and width * ZOOM_IN > box.width
        and u0 - width * KEEP > box[1]
        and u1 + width * KEEP < box[3]
        and v0 - height * KEEP > box[2]
        and v1 + height * KEEP < box[4]
    then
        return
    end
    local mu, mv = width * MARGIN, height * MARGIN
    cullBox = { u0 - mu, v0 - mv, u1 + mu, v1 + mv, width = width }
    for mapID, zone in pairs(zones) do
        local left, right, top, bottom = Geometry:Rect(mapID)
        local near = right > cullBox[1] and left < cullBox[3] and bottom > cullBox[2] and top < cullBox[4]
        -- (a zone in view: its tiles near the new box)
        if near or zone.near ~= near then
            zone.near = near
            ShowZone(mapID)
        end
    end
end

-- The map shown again: the next Cull runs in full.
function Art:Recull()
    cullBox = nil
end

-- Pieces the player has just explored: no longer hidden with the unexplored ones.
function Art:RefreshExplored()
    for mapID, list in pairs(pieces) do
        local changed = false
        for _, info in ipairs(C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}) do
            local piece = list[PieceKey(info.textureWidth, info.textureHeight, info.offsetX, info.offsetY)]
            if piece and piece.unexplored then
                piece.unexplored = false
                changed = true
            end
        end
        if changed and zones[mapID] and cullBox then
            ShowZone(mapID)
        end
    end
end

function Art:SetUnexploredShown(shownNow)
    unexploredShown = shownNow
    ShowZones()
end
