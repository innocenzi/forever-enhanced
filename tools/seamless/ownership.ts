// Which zone's map shows where: the world shared out between the zones, one mask per
// zone over its map, so the map draws each zone once through its own mask and every
// place inside some zone's map shows exactly one of them, never a hole.
//
// A place inside a zone's frame (OpenMap's MapEdge: its map, less its torn border)
// belongs to the zone whose own land it is (OpenMap's MapTerritory: the land and sea
// it paints, not its neighbours'); where several claim it, the strongest claim, then
// the smaller zone; where none does (border mountains and gaps OpenMap paints with
// layers of its own), the zone whose land is nearest. A zone's mask is its share,
// fading out over FADE world units past it, so neighbours blend; zones are drawn
// biggest first, each fading over the ones under it.

import { blank, type Image, sample } from "./images";
import { type Rect, WORLD, type World } from "./world";

/** OpenMap's masks of each zone: MapTerritory, MapEdge, MapZoneLand (its land, without its painted sea). */
export type MaskSources = { territory: Map<number, Image>; edge: Map<number, Image>; land: Map<number, Image> };

// Raster pixels per world unit; world units a share fades out over; a mask's side, in pixels.
const SCALE = 4;
const FADE = 3;
const MASK_SIZE = 256;

const EDGE_PENALTY = 4;
// A zone fades out over EDGE_FADE world units to the edge of its map (into the blank
// paper, where no neighbour's map takes over), never ending on its map's straight edge.
const EDGE_FADE = 4;
const SEA_KEEP = 3;
const SEA_FADE = 8;

// A zone's map without its own frame mask: everything but a thin border.
const GENERIC_INSET = 0.03;
const GENERIC_FADE = 0.02;

/** Squared Euclidean distance transform (Felzenszwalb), in pixels: to the nearest set pixel. */
export function distanceTransform(set: Uint8Array, width: number, height: number): Float32Array {
    const INF = 1e20;
    const out = new Float32Array(width * height);
    const size = Math.max(width, height);
    const f = new Float64Array(size);
    const d = new Float64Array(size);
    const v = new Int32Array(size);
    const z = new Float64Array(size + 1);
    const pass = (n: number) => {
        let k = 0;
        v[0] = 0;
        z[0] = -INF;
        z[1] = INF;
        for (let q = 1; q < n; q++) {
            let s = (f[q] + q * q - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
            while (s <= z[k]) {
                k--;
                s = (f[q] + q * q - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
            }
            k++;
            v[k] = q;
            z[k] = s;
            z[k + 1] = INF;
        }
        k = 0;
        for (let q = 0; q < n; q++) {
            while (z[k + 1] < q) k++;
            d[q] = (q - v[k]) * (q - v[k]) + f[v[k]];
        }
    };
    for (let x = 0; x < width; x++) {
        for (let y = 0; y < height; y++) f[y] = set[y * width + x] ? 0 : INF;
        pass(height);
        for (let y = 0; y < height; y++) out[y * width + x] = d[y];
    }
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) f[x] = out[y * width + x];
        pass(width);
        for (let x = 0; x < width; x++) out[y * width + x] = Math.sqrt(d[x]);
    }
    return out;
}

function smooth(t: number): number {
    const c = Math.min(1, Math.max(0, t));
    return c * c * (3 - 2 * c);
}

type Zone = {
    mapID: number;
    rect: Rect;
    area: number;
    // its window on the raster: [x0, y0) to [x1, y1)
    x0: number;
    y0: number;
    width: number;
    height: number;
    frame: Float32Array;
    territory: Float32Array;
    land: Float32Array;
};

/** Each zone's mask (alpha; white), over its whole map, MASK_SIZE pixels a side. */
export function ownershipMasks(
    world: World,
    zoneIDs: number[],
    sources: MaskSources,
): { masks: Map<number, Image>; field: LandField } {
    const worldArt = world.art(WORLD);
    if (!worldArt) throw new Error("no art for Azeroth's map");
    const scale = SCALE;
    const fade = FADE;
    const size = MASK_SIZE;
    const unitsWide = worldArt.width;
    const unitsHigh = worldArt.height;
    const rasterWidth = Math.ceil(unitsWide * scale);
    const rasterHeight = Math.ceil(unitsHigh * scale);

    // Each zone's frame and territory, sampled on its window of the raster.
    const zones: Zone[] = [];
    for (const mapID of zoneIDs) {
        const rect = world.rect(mapID);
        if (!rect) continue;
        const [left, right, top, bottom] = rect;
        const x0 = Math.max(0, Math.floor(left * unitsWide * scale));
        const y0 = Math.max(0, Math.floor(top * unitsHigh * scale));
        const x1 = Math.min(rasterWidth, Math.ceil(right * unitsWide * scale));
        const y1 = Math.min(rasterHeight, Math.ceil(bottom * unitsHigh * scale));
        const width = x1 - x0;
        const height = y1 - y0;
        const frame = new Float32Array(width * height);
        const territory = new Float32Array(width * height);
        const land = new Float32Array(width * height);
        const edgeSource = sources.edge.get(mapID);
        const territorySource = sources.territory.get(mapID);
        const landSource = sources.land.get(mapID);
        for (let y = 0; y < height; y++) {
            for (let x = 0; x < width; x++) {
                // the pixel's middle on the zone's map, 0..1
                const mx = ((x0 + x + 0.5) / scale / unitsWide - left) / (right - left);
                const my = ((y0 + y + 0.5) / scale / unitsHigh - top) / (bottom - top);
                let f: number;
                if (edgeSource) {
                    f = sample(edgeSource, mx * edgeSource.width, my * edgeSource.height, 3) / 255;
                } else {
                    const inside = Math.min(mx, 1 - mx, my, 1 - my);
                    f = smooth((inside - GENERIC_INSET) / GENERIC_FADE);
                }
                frame[y * width + x] = f;
                territory[y * width + x] = territorySource
                    ? sample(territorySource, mx * territorySource.width, my * territorySource.height, 3) / 255
                    : f;
                land[y * width + x] = landSource
                    ? sample(landSource, mx * landSource.width, my * landSource.height, 3) / 255
                    : territory[y * width + x];
            }
        }
        zones.push({
            mapID,
            rect,
            area: (right - left) * (bottom - top),
            x0,
            y0,
            width,
            height,
            frame,
            territory,
            land,
        });
    }
    // biggest first: a smaller zone's claim wins a tie, as it's drawn over
    zones.sort((a, b) => b.area - a.area || a.mapID - b.mapID);

    // Owners: by the strongest claim of own land, else by the nearest own land.
    const owner = new Int16Array(rasterWidth * rasterHeight).fill(-1);
    const claim = new Float32Array(rasterWidth * rasterHeight);
    const nearest = new Float32Array(rasterWidth * rasterHeight).fill(Infinity);
    const nearestOwner = new Int16Array(rasterWidth * rasterHeight).fill(-1);
    // (a place near the edge of a zone's map counts as farther from its land, by up to
    // EDGE_PENALTY per world unit inside the zone's edge fade and its share's fade: a
    // neighbour whose map reaches there takes over before the zone fades, so the handover
    // is inside both maps, and never a straight line along one map's edge; and the zone
    // claims no land there as its own)
    const edgeFade = EDGE_FADE * scale;
    const edgeReach = edgeFade + fade * scale;
    const toEdges: Float32Array[] = [];
    zones.forEach((zone, index) => {
        const own = new Uint8Array(zone.width * zone.height);
        const outsideFrame = new Uint8Array(zone.width * zone.height);
        for (let i = 0; i < own.length; i++) {
            own[i] = zone.territory[i] >= 0.5 ? 1 : 0;
            outsideFrame[i] = zone.frame[i] < 0.5 ? 1 : 0;
        }
        const distance = distanceTransform(own, zone.width, zone.height);
        const toEdge = distanceTransform(outsideFrame, zone.width, zone.height);
        // (the window's own edge is the map's edge too)
        for (let y = 0; y < zone.height; y++) {
            for (let x = 0; x < zone.width; x++) {
                const i = y * zone.width + x;
                toEdge[i] = Math.min(toEdge[i], x + 0.5, y + 0.5, zone.width - x - 0.5, zone.height - y - 0.5);
            }
        }
        toEdges[index] = toEdge;
        for (let y = 0; y < zone.height; y++) {
            for (let x = 0; x < zone.width; x++) {
                const i = y * zone.width + x;
                if (zone.frame[i] < 0.5) continue;
                const at = (zone.y0 + y) * rasterWidth + zone.x0 + x;
                const edge = toEdge[i];
                const t = zone.territory[i];
                if (t >= 0.5 && t >= claim[at] && edge >= edgeReach) {
                    claim[at] = t;
                    owner[at] = index;
                }
                const score = distance[i] + EDGE_PENALTY * Math.max(0, edgeReach - edge);
                if (score <= nearest[at]) {
                    nearest[at] = score;
                    nearestOwner[at] = index;
                }
            }
        }
    });
    for (let at = 0; at < owner.length; at++) {
        if (owner[at] < 0) owner[at] = nearestOwner[at];
    }

    // How far each place is from any zone's own land: out at sea, a zone's painted sea
    // fades out (SEA_KEEP, then over SEA_FADE world units) into the continent's, so a
    // coast never sits in its map's rectangle.
    // (and from the sea a zone paints, for the continents' land: continentLand)
    const land = new Uint8Array(rasterWidth * rasterHeight);
    const paintedSea = new Uint8Array(rasterWidth * rasterHeight);
    for (const zone of zones) {
        for (let y = 0; y < zone.height; y++) {
            for (let x = 0; x < zone.width; x++) {
                const i = y * zone.width + x;
                if (zone.frame[i] < 0.5) continue;
                const at = (zone.y0 + y) * rasterWidth + zone.x0 + x;
                if (zone.land[i] >= 0.25) {
                    land[at] = 1;
                } else if (zone.territory[i] >= 0.5) {
                    paintedSea[at] = 1;
                }
            }
        }
    }
    const fromLand = distanceTransform(land, rasterWidth, rasterHeight);
    const fromSea = distanceTransform(paintedSea, rasterWidth, rasterHeight);

    // Each zone's share, fading out past it, inside its frame; resampled over its map.
    const masks = new Map<number, Image>();
    zones.forEach((zone, index) => {
        const share = new Uint8Array(zone.width * zone.height);
        for (let y = 0; y < zone.height; y++) {
            for (let x = 0; x < zone.width; x++) {
                share[y * zone.width + x] = owner[(zone.y0 + y) * rasterWidth + zone.x0 + x] === index ? 1 : 0;
            }
        }
        const outside = distanceTransform(share, zone.width, zone.height);
        const alpha = new Float32Array(zone.width * zone.height);
        for (let y = 0; y < zone.height; y++) {
            for (let x = 0; x < zone.width; x++) {
                const i = y * zone.width + x;
                const sea = fromLand[(zone.y0 + y) * rasterWidth + zone.x0 + x] / scale;
                const offshore = smooth(1 - (sea - SEA_KEEP) / SEA_FADE);
                const edge = smooth(toEdges[index][i] / edgeFade);
                alpha[i] = smooth(1 - outside[i] / (fade * scale)) * zone.frame[i] * offshore * edge;
            }
        }
        const mask = blank(size, size);
        const [left, right, top, bottom] = zone.rect;
        for (let y = 0; y < size; y++) {
            for (let x = 0; x < size; x++) {
                const rx = (left + ((x + 0.5) / size) * (right - left)) * unitsWide * scale - zone.x0;
                const ry = (top + ((y + 0.5) / size) * (bottom - top)) * unitsHigh * scale - zone.y0;
                const p = (y * size + x) * 4;
                mask.rgba[p] = mask.rgba[p + 1] = mask.rgba[p + 2] = 255;
                mask.rgba[p + 3] = Math.round(255 * bilinear(alpha, zone.width, zone.height, rx, ry));
            }
        }
        masks.set(zone.mapID, mask);
    });
    return { masks, field: { width: rasterWidth, height: rasterHeight, scale, fromLand, fromSea } };
}

/** How far each place of the world is from the zones' land and from the sea they paint (raster pixels). */
export type LandField = {
    width: number;
    height: number;
    /** Raster pixels per world unit. */
    scale: number;
    fromLand: Float32Array;
    fromSea: Float32Array;
};

// The continents' land is OpenMap's MapBackLand, but only inland (LAND_INSET world units
// from its coast, faded over LAND_FADE): MapBackLand takes in the continent map's coastal
// band (its shoreline ink and hatching), and the continent's outline is coarse, so near
// its coast its land reads as a second coastline beside the zones' own; the zones paint
// their coasts themselves. And never where the sea a zone paints is nearer than its land
// (handed over across LAND_SIDE world units either side of halfway): off a zone's coast
// the continent may still count land.
const LAND_INSET = 12;
const LAND_FADE = 4;
const LAND_SIDE = 4;

/** A continent's land, inland and off the zones' seas (alpha; white), over its whole map, MASK_SIZE pixels a side. */
export function continentLand(world: World, mapID: number, backLand: Image, field: LandField): Image {
    const size = MASK_SIZE;
    const worldArt = world.art(WORLD);
    const rect = world.rect(mapID);
    if (!worldArt || !rect) throw new Error(`no place for continent ${mapID}`);
    const [left, right, top, bottom] = rect;
    // one pixel a world unit, over the continent's map
    const width = Math.ceil((right - left) * worldArt.width);
    const height = Math.ceil((bottom - top) * worldArt.height);
    const back = new Float32Array(width * height);
    const sea = new Uint8Array(width * height);
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            const i = y * width + x;
            back[i] = sample(backLand, ((x + 0.5) / width) * backLand.width, ((y + 0.5) / height) * backLand.height, 3) / 255;
            sea[i] = back[i] < 0.5 ? 1 : 0;
        }
    }
    const inland = distanceTransform(sea, width, height);
    const alpha = new Float32Array(width * height);
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            const i = y * width + x;
            const fx = Math.floor((left * worldArt.width + x + 0.5) * field.scale);
            const fy = Math.floor((top * worldArt.height + y + 0.5) * field.scale);
            let side = 1;
            if (fx >= 0 && fy >= 0 && fx < field.width && fy < field.height) {
                const toLand = field.fromLand[fy * field.width + fx] / field.scale;
                const toSea = field.fromSea[fy * field.width + fx] / field.scale;
                if (Number.isFinite(toSea)) side = smooth(0.5 + (toSea - toLand) / (2 * LAND_SIDE));
            }
            alpha[i] = back[i] * smooth((inland[i] - LAND_INSET) / LAND_FADE) * side;
        }
    }
    const mask = blank(size, size);
    for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
            const p = (y * size + x) * 4;
            mask.rgba[p] = mask.rgba[p + 1] = mask.rgba[p + 2] = 255;
            const value = bilinear(alpha, width, height, ((x + 0.5) / size) * width, ((y + 0.5) / size) * height);
            mask.rgba[p + 3] = Math.round(255 * value);
        }
    }
    return mask;
}

function bilinear(values: Float32Array, width: number, height: number, x: number, y: number): number {
    const fx = Math.min(Math.max(x - 0.5, 0), width - 1);
    const fy = Math.min(Math.max(y - 0.5, 0), height - 1);
    const x0 = Math.floor(fx);
    const y0 = Math.floor(fy);
    const x1 = Math.min(x0 + 1, width - 1);
    const y1 = Math.min(y0 + 1, height - 1);
    const tx = fx - x0;
    const ty = fy - y0;
    const at = (px: number, py: number) => values[py * width + px];
    return (at(x0, y0) * (1 - tx) + at(x1, y0) * tx) * (1 - ty) + (at(x0, y1) * (1 - tx) + at(x1, y1) * tx) * ty;
}
