// Renders part of the stitched map out of the game, as the map draws it zoomed in on
// zones (blank sea and land paper past the zones, each zone's base art and every
// explored-area piece through its share, tinted, cities round-faded on top), from what
// the addon ships (modules/map/seamless: data.lua's build, tints and papers, media/), to
// check the masks without the game. Dev only.
//
//   bun tools/seamless/preview.ts <left> <top> <right> <bottom> [px per world unit] [out.png]
//     the box on Azeroth's map, normalized (e.g. 0.70 0.60 0.84 0.74: Duskwood and around);
//     4 px a world unit, and tools/.cache/seamless/preview.png, unless given
//
// Run `bun run seamless` first.

import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { blank, decodePng, encodePng, type Image, sample } from "./images";
import { composeArt } from "./paper";
import { Downloads, loadTables, parseTints, type Tint, WORLD, World } from "./world";

const SLICE = "modules/map/seamless";
// (art.lua's PAPER_OVER*)
const PAPER_OVER = 2.618;
const PAPER_OVER_ALPHA = 0.5;
const PAPER_OVER_SHIFT = 0.37;

type Box = [left: number, top: number, right: number, bottom: number];

export type PreviewLayers = {
    /** The zones' shares, over each one's whole map. */
    zoneMasks: Map<number, Image>;
    /** Each continent's land. */
    lands: Map<number, Image>;
    cityMask: Image;
    /** The blank papers, and the world units a tile of each spans. */
    papers: { land: Image; sea: Image; landSize: number; seaSize: number };
    tints: Map<number, Tint>;
};

export async function renderPreview(
    world: World,
    downloads: Downloads,
    build: string,
    box: Box,
    pxPerUnit: number,
    layers: PreviewLayers,
): Promise<Image> {
    const worldArt = world.art(WORLD)!;
    const [u0, v0, u1, v1] = box;
    const width = Math.round((u1 - u0) * worldArt.width * pxPerUnit);
    const height = Math.round((v1 - v0) * worldArt.height * pxPerUnit);
    const color = new Float32Array(width * height * 3);
    const worldX = (x: number) => (u0 + ((x + 0.5) / width) * (u1 - u0)) * worldArt.width;
    const worldY = (y: number) => (v0 + ((y + 0.5) / height) * (v1 - v0)) * worldArt.height;

    // a paper's colour at world units (x, y), tiled twice as art.lua's Paper draws it
    const tiled = (paper: Image, x: number, y: number, c: number, tile: number, shift: number) => {
        const n = paper.width;
        const px = ((Math.floor((x / tile + shift) * n) % n) + n) % n;
        const py = ((Math.floor((y / tile + shift * 1.7) * n) % n) + n) % n;
        return paper.rgba[(py * n + px) * 4 + c] / 255;
    };
    const paperAt = (paper: Image, size: number, x: number, y: number, c: number) => {
        const under = tiled(paper, x, y, c, size, 0);
        const over = tiled(paper, x, y, c, size * PAPER_OVER, PAPER_OVER_SHIFT);
        return under + (over - under) * PAPER_OVER_ALPHA;
    };
    const { sea, land, seaSize, landSize } = layers.papers;
    for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
            for (let c = 0; c < 3; c++) color[(y * width + x) * 3 + c] = paperAt(sea, seaSize, worldX(x), worldY(y), c);
        }
    }

    const overlaps = (mapID: number) => {
        const rect = world.rect(mapID)!;
        return rect[1] > u0 && rect[0] < u1 && rect[3] > v0 && rect[2] < v1;
    };
    // Draws `colorAt` over a map's rect, through `alphaAt` (both at 0..1 on its map).
    const paint = (
        mapID: number,
        colorAt: (mx: number, my: number, x: number, y: number, c: number) => number,
        alphaAt: (mx: number, my: number) => number,
    ) => {
        const [left, right, top, bottom] = world.rect(mapID)!;
        for (let y = 0; y < height; y++) {
            const my = (v0 + ((y + 0.5) / height) * (v1 - v0) - top) / (bottom - top);
            if (my < 0 || my >= 1) continue;
            for (let x = 0; x < width; x++) {
                const mx = (u0 + ((x + 0.5) / width) * (u1 - u0) - left) / (right - left);
                if (mx < 0 || mx >= 1) continue;
                const a = alphaAt(mx, my);
                if (a <= 0) continue;
                const i = (y * width + x) * 3;
                for (let c = 0; c < 3; c++) color[i + c] = colorAt(mx, my, x, y, c) * a + color[i + c] * (1 - a);
            }
        }
    };
    const maskAlpha = (mask: Image) => (mx: number, my: number) => sample(mask, mx * mask.width, my * mask.height, 3) / 255;
    const artColor = (art: Image, tint: Tint = [1, 1, 1]) => (mx: number, my: number, _x: number, _y: number, c: number) =>
        (sample(art, mx * art.width, my * art.height, c) / 255) * tint[c];
    const artAlpha = (art: Image, mask: Image) => (mx: number, my: number) =>
        maskAlpha(mask)(mx, my) * (sample(art, mx * art.width, my * art.height, 3) / 255);

    for (const mapID of world.mapsOfType("continent")) {
        const mask = layers.lands.get(mapID);
        if (overlaps(mapID) && mask) {
            paint(mapID, (_mx, _my, x, y, c) => paperAt(land, landSize, worldX(x), worldY(y), c), maskAlpha(mask));
        }
    }
    const area = (mapID: number) => {
        const [l, r, t, b] = world.rect(mapID)!;
        return (r - l) * (b - t);
    };
    const zones = world
        .zones()
        .filter(overlaps)
        .sort((a, b) => area(b) - area(a) || a - b);
    for (const mapID of zones) {
        const mask = layers.zoneMasks.get(mapID);
        const art = mask && (await composeArt(world, downloads, build, mapID, true));
        if (mask && art) paint(mapID, artColor(art, layers.tints.get(mapID)), artAlpha(art, mask));
    }
    for (const mapID of world.mapsOfType("zone")) {
        if (zones.includes(mapID) || !overlaps(mapID)) continue;
        const art = await composeArt(world, downloads, build, mapID, false);
        if (art) paint(mapID, artColor(art), artAlpha(art, layers.cityMask));
    }

    const out = blank(width, height);
    for (let i = 0; i < width * height; i++) {
        for (let c = 0; c < 3; c++) out.rgba[i * 4 + c] = Math.round(Math.min(1, color[i * 3 + c]) * 255);
        out.rgba[i * 4 + 3] = 255;
    }
    return out;
}

function usage(): never {
    throw new Error("usage: bun tools/seamless/preview.ts <left> <top> <right> <bottom> [px per world unit] [out.png]");
}

if (import.meta.main) {
    const args = Bun.argv.slice(2);
    const box = args.slice(0, 4).map(Number) as Box;
    if (box.length < 4 || box.some((value) => !Number.isFinite(value)) || box[2] <= box[0] || box[3] <= box[1]) usage();
    const pxPerUnit = Number(args[4] ?? 4);
    if (!(pxPerUnit > 0)) usage();
    const repoRoot = path.resolve(import.meta.dir, "../..");
    const output = args[5] ?? path.join(repoRoot, "tools/.cache/seamless/preview.png");

    // what the addon ships: data.lua's build, tints and papers' sizes, and media/
    const data = await readFile(path.join(repoRoot, SLICE, "data.lua"), "utf8");
    const build = data.match(/\(build ([\d.]+),/)?.[1];
    const sizes = data.match(/Seamless\.Papers = \{ land = ([\d.]+), sea = ([\d.]+) \}/);
    const tintsAt = data.indexOf("Seamless.Tints");
    if (!build || !sizes || tintsAt < 0) throw new Error(`${SLICE}/data.lua isn't the generator's: run \`bun run seamless\``);
    const media = path.join(repoRoot, SLICE, "media");
    const read = async (file: string) => decodePng(new Uint8Array(await readFile(path.join(media, file))));

    const downloads = new Downloads(repoRoot, false);
    const world = new World(await loadTables(downloads, build));
    const zoneMasks = new Map<number, Image>();
    for (const mapID of world.zones()) {
        if (existsSync(path.join(media, "zone", `${mapID}.png`))) zoneMasks.set(mapID, await read(`zone/${mapID}.png`));
    }
    const lands = new Map<number, Image>();
    for (const mapID of world.mapsOfType("continent")) {
        if (existsSync(path.join(media, "land", `${mapID}.png`))) lands.set(mapID, await read(`land/${mapID}.png`));
    }
    const image = await renderPreview(world, downloads, build, box, pxPerUnit, {
        zoneMasks,
        lands,
        cityMask: await read("feather-round.png"),
        papers: { land: await read("land.png"), sea: await read("sea.png"), landSize: Number(sizes[1]), seaSize: Number(sizes[2]) },
        tints: parseTints(data.slice(tintsAt)),
    });
    await mkdir(path.dirname(output), { recursive: true });
    await writeFile(output, encodePng(image));
    console.log(`${output}: ${image.width}x${image.height}`);
}
