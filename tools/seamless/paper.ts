// Blank map paper for the places no zone's map covers, as an undiscovered zone's map
// shows its land and sea: a patch of the zone maps' own blank parchment, and one of
// their open sea, each the cleanest found on any zone's base art (the least ink, all of
// it that zone's own land, or its own painted sea, inside its frame), made to tile.
// OpenMap's blank paper is the same idea (MapPaper, from Westfall's map).

import { blank, type Image, sample } from "./images";
import type { MaskSources } from "./ownership";
import { type Downloads, WORLD, type World } from "./world";

/** A patch's side, in its map's own pixels (a power of two, as the game wants): no zone's
 * open sea holds a clean patch as wide as its blank land does. */
const PAPER_SIZES = { land: 256, sea: 128 } as const;
const STEP = 16;
// The painted sea's blue less red is above this; the parchment's is far below (about -110).
const SEA_BLUE = -50;
// The share of a patch that must be blank land, or the painted sea (whose colour varies more).
const COVERAGE = { land: 0.999, sea: 0.97 };

/** A map's whole art, with its explored-area pieces over it when `pieces`. */
export async function composeArt(world: World, downloads: Downloads, build: string, mapID: number, pieces: boolean) {
    const art = world.art(mapID);
    if (!art) return undefined;
    const image = blank(art.width, art.height);
    const cols = Math.ceil(art.width / art.tileWidth);
    const draw = (tile: Image, x: number, y: number) => {
        for (let ty = 0; ty < tile.height; ty++) {
            const iy = y + ty;
            if (iy < 0 || iy >= art.height) continue;
            for (let tx = 0; tx < tile.width; tx++) {
                const ix = x + tx;
                if (ix < 0 || ix >= art.width) continue;
                const s = (ty * tile.width + tx) * 4;
                const d = (iy * art.width + ix) * 4;
                const a = tile.rgba[s + 3] / 255;
                for (let c = 0; c < 3; c++) image.rgba[d + c] = tile.rgba[s + c] * a + image.rgba[d + c] * (1 - a);
                image.rgba[d + 3] = Math.max(image.rgba[d + 3], tile.rgba[s + 3]);
            }
        }
    };
    for (let i = 0; i < art.tiles.length; i++) {
        draw(await downloads.texture(art.tiles[i], build), (i % cols) * art.tileWidth, Math.floor(i / cols) * art.tileHeight);
    }
    if (pieces) {
        for (const [width, , x, y, ...files] of world.piecesOf(mapID)) {
            const pieceCols = Math.ceil(width / art.tileWidth);
            for (let i = 0; i < files.length; i++) {
                const tile = await downloads.texture(files[i], build);
                draw(tile, x + (i % pieceCols) * art.tileWidth, y + Math.floor(i / pieceCols) * art.tileHeight);
            }
        }
    }
    return image;
}

// A table of sums over the image (one more row and column), for any rectangle's sum at once.
function integral(values: Float32Array, width: number, height: number): Float64Array {
    const sums = new Float64Array((width + 1) * (height + 1));
    for (let y = 0; y < height; y++) {
        let row = 0;
        for (let x = 0; x < width; x++) {
            row += values[y * width + x];
            sums[(y + 1) * (width + 1) + x + 1] = sums[y * (width + 1) + x + 1] + row;
        }
    }
    return sums;
}

function rectSum(sums: Float64Array, width: number, x: number, y: number, size: number): number {
    const w = width + 1;
    return sums[(y + size) * w + x + size] - sums[y * w + x + size] - sums[(y + size) * w + x] + sums[y * w + x];
}

// One axis made to tile: blended with itself shifted by half along it, by a weight that's 1
// in the middle (where the shifted copy's seam is) and 0 at the edges (where the shifted
// copy runs on across the wrap).
function tileAlong(patch: Image, axis: "x" | "y"): Image {
    const size = patch.width;
    const half = size / 2;
    const out = blank(size, size);
    for (let y = 0; y < size; y++) {
        for (let x = 0; x < size; x++) {
            const along = axis === "x" ? x : y;
            const edge = Math.min(along + 0.5, size - along - 0.5) / half;
            const t = Math.min(1, edge * 1.6);
            const w = t * t * (3 - 2 * t);
            const a = (y * size + x) * 4;
            const b = axis === "x" ? (y * size + ((x + half) % size)) * 4 : (((y + half) % size) * size + x) * 4;
            for (let c = 0; c < 3; c++) out.rgba[a + c] = Math.round(patch.rgba[a + c] * w + patch.rgba[b + c] * (1 - w));
            out.rgba[a + 3] = 255;
        }
    }
    return out;
}

/** The patch made to tile, across and down: no seam at its edges, nor any line through it. */
function tileable(patch: Image): Image {
    return tileAlong(tileAlong(patch, "x"), "y");
}

export type Paper = {
    image: Image;
    /** World units the patch spans, at its own map's scale. */
    worldSize: number;
    /** Where it came from, to say. */
    from: string;
};

/** The cleanest blank land and open sea of the zones' base art, made to tile. */
export async function findPapers(
    world: World,
    downloads: Downloads,
    build: string,
    sources: MaskSources,
): Promise<{ land: Paper; sea: Paper }> {
    type Best = { score: number; mapID: number; x: number; y: number; art?: Image };
    const best = { land: { score: Infinity } as Best, sea: { score: Infinity } as Best };
    for (const mapID of world.zones()) {
        const land = sources.land.get(mapID);
        const territory = sources.territory.get(mapID);
        const edge = sources.edge.get(mapID);
        if (!land || !territory || !edge) continue;
        const art = await composeArt(world, downloads, build, mapID, false);
        if (!art) continue;
        const { width, height } = art;
        // ink: how much each pixel differs from its neighbours (drawn lines, names, hatching)
        const ink = new Float32Array(width * height);
        const isLand = new Float32Array(width * height);
        const isSea = new Float32Array(width * height);
        const lum = (x: number, y: number) => {
            const p = (y * width + x) * 4;
            return 0.3 * art.rgba[p] + 0.59 * art.rgba[p + 1] + 0.11 * art.rgba[p + 2];
        };
        for (let y = 1; y < height - 1; y++) {
            for (let x = 1; x < width - 1; x++) {
                const i = y * width + x;
                ink[i] = Math.abs(lum(x + 1, y) - lum(x - 1, y)) + Math.abs(lum(x, y + 1) - lum(x, y - 1));
                const mx = (x + 0.5) / width;
                const my = (y + 0.5) / height;
                const inFrame = sample(edge, mx * edge.width, my * edge.height, 3) > 240;
                const l = sample(land, mx * land.width, my * land.height, 3);
                isLand[i] = inFrame && l > 240 ? 1 : 0;
                // (its own sea: not its land, and the painted sea's grey, not the parchment's orange)
                const p = i * 4;
                isSea[i] = inFrame && l < 10 && art.rgba[p + 2] - art.rgba[p] > SEA_BLUE ? 1 : 0;
            }
        }
        const inkSums = integral(ink, width, height);
        const kinds = { land: integral(isLand, width, height), sea: integral(isSea, width, height) };
        for (const kind of ["land", "sea"] as const) {
            const size = PAPER_SIZES[kind];
            const area = size * size;
            for (let y = 0; y + size <= height; y += STEP) {
                for (let x = 0; x + size <= width; x += STEP) {
                    if (rectSum(kinds[kind], width, x, y, size) < area * COVERAGE[kind]) continue;
                    const score = rectSum(inkSums, width, x, y, size) / area;
                    if (score < best[kind].score) best[kind] = { score, mapID, x, y, art };
                }
            }
        }
    }
    const paper = (found: Best, kind: keyof typeof PAPER_SIZES): Paper => {
        const size = PAPER_SIZES[kind];
        if (!found.art) throw new Error(`no zone map has a clean patch of blank ${kind} ${size} pixels wide`);
        const patch = blank(size, size);
        for (let y = 0; y < size; y++) {
            const from = ((found.y + y) * found.art.width + found.x) * 4;
            patch.rgba.set(found.art.rgba.subarray(from, from + size * 4), y * size * 4);
        }
        const rect = world.rect(found.mapID)!;
        const art = world.art(found.mapID)!;
        const unitsPerPixel = ((rect[1] - rect[0]) * world.art(WORLD)!.width) / art.width;
        return {
            image: tileable(patch),
            worldSize: size * unitsPerPixel,
            from: `${world.name(found.mapID)}'s map at (${found.x}, ${found.y})`,
        };
    };
    return { land: paper(best.land, "land"), sea: paper(best.sea, "sea") };
}
