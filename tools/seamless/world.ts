// The game's map tables, as the seamless map's tools need them: where each map lies on
// Azeroth's map (947), its art, and each zone art's explored-area pieces. Read from the
// Forever client's DB2 tables, as exported by wago.tools, cached in tools/.cache.

import path from "node:path";
import { cached, float, gameFile, integer, parseCsv, type Row, table } from "../wago";
import { decodeBlp, type Image } from "./images";

const CACHE = "tools/.cache/seamless";
export const WORLD = 947;
const ZONE_TYPE = 3;
const CONTINENT_TYPE = 2;

// The OpenMap commit the masks come from. Bump it to take newer masks.
export const OPENMAP_COMMIT = "dc611408ad0cfc2355815edcd364c74679ef4101";
const OPENMAP_TEXTURES = "OpenMap/Media/Textures/Forever/";

/** A piece of a zone art: its size and offset in the art, then its tiles' files (row-major). */
export type Piece = [width: number, height: number, x: number, y: number, ...files: number[]];

/** A map's rectangle on Azeroth's map, normalized: left, right, top, bottom. */
export type Rect = [left: number, right: number, top: number, bottom: number];

export type Art = { id: number; width: number; height: number; tileWidth: number; tileHeight: number; tiles: number[] };

// Downloads ------------------------------------------------------------------------------

export class Downloads {
    constructor(
        private readonly repoRoot: string,
        private readonly refresh: boolean,
    ) {}

    private get cacheDir(): string {
        return path.join(this.repoRoot, CACHE);
    }

    private cached(file: string, url: string): Promise<Uint8Array> {
        return cached(path.join(this.cacheDir, file), url, this.refresh);
    }

    table(name: string, build: string): Promise<string> {
        return table(this.cacheDir, name, build, this.refresh);
    }

    /** A game texture by file ID (BLP), decoded. */
    async texture(fileID: number, build: string): Promise<Image> {
        return decodeBlp(await gameFile(this.cacheDir, fileID, `blp/${fileID}.blp`, build, this.refresh));
    }

    /** OpenMap's Forever textures at OPENMAP_COMMIT: their paths under OPENMAP_TEXTURES. */
    async openMapTextures(): Promise<string[]> {
        const url = `https://api.github.com/repos/openmap-world/openmap/git/trees/${OPENMAP_COMMIT}?recursive=1`;
        const tree = JSON.parse(new TextDecoder().decode(await this.cached(`${OPENMAP_COMMIT}/tree.json`, url))) as {
            tree: { path: string; type: string }[];
            truncated: boolean;
        };
        if (tree.truncated) {
            throw new Error("OpenMap's file list came back truncated");
        }
        return tree.tree
            .filter((entry) => entry.type === "blob" && entry.path.startsWith(OPENMAP_TEXTURES))
            .map((entry) => entry.path.slice(OPENMAP_TEXTURES.length));
    }

    /** One of OpenMap's Forever textures (TGA), raw. */
    async openMapFile(file: string): Promise<Uint8Array> {
        const url = `https://raw.githubusercontent.com/openmap-world/openmap/${OPENMAP_COMMIT}/${OPENMAP_TEXTURES}${file}`;
        return this.cached(`${OPENMAP_COMMIT}/${file}`, url);
    }

    /** One of OpenMap's Forever data files (Lua), as text. */
    async openMapData(file: string): Promise<string> {
        const url = `https://raw.githubusercontent.com/openmap-world/openmap/${OPENMAP_COMMIT}/OpenMap/Data/Forever/${file}`;
        return new TextDecoder().decode(await this.cached(`${OPENMAP_COMMIT}/Data/${file}`, url));
    }
}

/** A zone's colour matching: { r, g, b } multipliers. */
export type Tint = [r: number, g: number, b: number];

/**
 * OpenMap's colour matching (Data/Forever/Grade.lua), or data.lua's Seamless.Tints:
 * uiMapID -> { r, g, b } multipliers that take each zone's colours toward the palette
 * all zones share.
 */
export function parseTints(lua: string): Map<number, Tint> {
    const tints = new Map<number, Tint>();
    for (const match of lua.matchAll(/\[(\d+)\]\s*=\s*\{\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*\}/g)) {
        tints.set(Number(match[1]), [Number(match[2]), Number(match[3]), Number(match[4])]);
    }
    if (tints.size === 0) {
        throw new Error("no colour matching in OpenMap's Grade.lua");
    }
    return tints;
}

// The world ------------------------------------------------------------------------------

const TABLES = [
    "UiMap",
    "UiMapAssignment",
    "UiMapXMapArt",
    "UiMapArt",
    "UiMapArtStyleLayer",
    "UiMapArtTile",
    "WorldMapOverlay",
    "WorldMapOverlayTile",
] as const;

/** The DB2 tables the tools read, as CSV. */
export type Tables = Record<(typeof TABLES)[number], string>;

export async function loadTables(downloads: Downloads, build: string): Promise<Tables> {
    const tables = {} as Tables;
    for (const name of TABLES) {
        tables[name] = await downloads.table(name, build);
    }
    return tables;
}

export class World {
    private readonly maps = new Map<number, { parent: number; type: number; name: string }>();
    private readonly assignments = new Map<number, Row[]>();
    private readonly artOf = new Map<number, number>();
    private readonly arts = new Map<number, Art>();
    private readonly rects = new Map<number, Rect | null>();
    readonly pieces = new Map<number, Piece[]>();

    constructor(tables: Tables) {
        for (const row of parseCsv(tables.UiMap)) {
            this.maps.set(integer(row, "ID"), {
                parent: integer(row, "ParentUiMapID"),
                type: integer(row, "Type"),
                name: row.Name_lang,
            });
        }
        for (const row of parseCsv(tables.UiMapAssignment)) {
            const list = this.assignments.get(integer(row, "UiMapID")) ?? [];
            list.push(row);
            this.assignments.set(integer(row, "UiMapID"), list);
        }
        // (the biggest part of each map's art first: the one GetMapRectOnMap goes by)
        const area = (row: Row) =>
            (float(row, "UiMax_0") - float(row, "UiMin_0")) * (float(row, "UiMax_1") - float(row, "UiMin_1"));
        for (const list of this.assignments.values()) {
            list.sort((a, b) => integer(a, "OrderIndex") - integer(b, "OrderIndex") || area(b) - area(a));
        }
        for (const row of parseCsv(tables.UiMapXMapArt)) {
            if (integer(row, "PhaseID") === 0 && !this.artOf.has(integer(row, "UiMapID"))) {
                this.artOf.set(integer(row, "UiMapID"), integer(row, "UiMapArtID"));
            }
        }
        const styleOf = new Map<number, number>();
        for (const row of parseCsv(tables.UiMapArt)) {
            styleOf.set(integer(row, "ID"), integer(row, "UiMapArtStyleID"));
        }
        const layers = new Map<number, Row>();
        for (const row of parseCsv(tables.UiMapArtStyleLayer)) {
            if (integer(row, "LayerIndex") === 0) {
                layers.set(integer(row, "UiMapArtStyleID"), row);
            }
        }
        const tiles = new Map<number, [number, number, number][]>();
        for (const row of parseCsv(tables.UiMapArtTile)) {
            if (integer(row, "LayerIndex") !== 0) continue;
            const list = tiles.get(integer(row, "UiMapArtID")) ?? [];
            list.push([integer(row, "RowIndex"), integer(row, "ColIndex"), integer(row, "FileDataID")]);
            tiles.set(integer(row, "UiMapArtID"), list);
        }
        for (const [artID, styleID] of styleOf) {
            const layer = layers.get(styleID);
            const list = tiles.get(artID);
            if (!layer || !list) continue;
            list.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
            this.arts.set(artID, {
                id: artID,
                width: integer(layer, "LayerWidth"),
                height: integer(layer, "LayerHeight"),
                tileWidth: integer(layer, "TileWidth"),
                tileHeight: integer(layer, "TileHeight"),
                tiles: list.map((tile) => tile[2]),
            });
        }
        this.collectPieces(tables);
    }

    private collectPieces(tables: Tables): void {
        const worldArts = new Set<number>();
        for (const [mapID, artID] of this.artOf) {
            if (this.isOnWorld(mapID)) worldArts.add(artID);
        }
        const tiles = new Map<number, [number, number, number][]>();
        for (const row of parseCsv(tables.WorldMapOverlayTile)) {
            if (integer(row, "LayerIndex") !== 0) continue;
            const list = tiles.get(integer(row, "WorldMapOverlayID")) ?? [];
            list.push([integer(row, "RowIndex"), integer(row, "ColIndex"), integer(row, "FileDataID")]);
            tiles.set(integer(row, "WorldMapOverlayID"), list);
        }
        for (const row of parseCsv(tables.WorldMapOverlay)) {
            const art = integer(row, "UiMapArtID");
            const list = tiles.get(integer(row, "ID"));
            if (!worldArts.has(art) || !list) continue;
            list.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
            const piece: Piece = [
                integer(row, "TextureWidth"),
                integer(row, "TextureHeight"),
                integer(row, "OffsetX"),
                integer(row, "OffsetY"),
                ...list.map((tile) => tile[2]),
            ];
            const pieces = this.pieces.get(art) ?? [];
            pieces.push(piece);
            this.pieces.set(art, pieces);
        }
        for (const list of this.pieces.values()) {
            list.sort((a, b) => a[2] - b[2] || a[3] - b[3] || a[0] - b[0] || a[1] - b[1]);
        }
    }

    isOnWorld(mapID: number): boolean {
        for (let id = mapID, steps = 0; id > 0 && steps < 16; id = this.maps.get(id)?.parent ?? 0, steps++) {
            if (id === WORLD) return true;
        }
        return false;
    }

    name(mapID: number): string {
        return this.maps.get(mapID)?.name ?? String(mapID);
    }

    art(mapID: number): Art | undefined {
        const artID = this.artOf.get(mapID);
        return artID === undefined ? undefined : this.arts.get(artID);
    }

    piecesOf(mapID: number): Piece[] {
        const art = this.art(mapID);
        return (art && this.pieces.get(art.id)) ?? [];
    }

    /** Azeroth's continents and zones, as C_Map.GetMapChildrenInfo(947, type, true). */
    mapsOfType(type: "continent" | "zone"): number[] {
        const wanted = type === "zone" ? ZONE_TYPE : CONTINENT_TYPE;
        return [...this.maps.entries()]
            .filter(([id, map]) => map.type === wanted && this.isOnWorld(id) && this.rect(id) && this.art(id))
            .map(([id]) => id)
            .sort((a, b) => a - b);
    }

    /** The zones drawn as zones: with explored-area pieces (the rest are cities). */
    zones(): number[] {
        return this.mapsOfType("zone").filter((id) => this.piecesOf(id).length > 0);
    }

    // A world point (yards on `row`'s game map) on that row's map, normalized.
    private static normalized(row: Row, x: number, y: number): [number, number] {
        const u =
            float(row, "UiMin_0") +
            ((float(row, "Region_4") - y) / (float(row, "Region_4") - float(row, "Region_1"))) *
                (float(row, "UiMax_0") - float(row, "UiMin_0"));
        const v =
            float(row, "UiMin_1") +
            ((float(row, "Region_3") - x) / (float(row, "Region_3") - float(row, "Region_0"))) *
                (float(row, "UiMax_1") - float(row, "UiMin_1"));
        return [u, v];
    }

    private static contains(row: Row, x: number, y: number): boolean {
        return (
            float(row, "Region_0") <= x &&
            x <= float(row, "Region_3") &&
            float(row, "Region_1") <= y &&
            y <= float(row, "Region_4")
        );
    }

    // The host's assignment on that game map holding the point (else the nearest).
    private hostRow(host: number, gameMap: number, x: number, y: number): Row | undefined {
        const rows = (this.assignments.get(host) ?? []).filter((row) => integer(row, "MapID") === gameMap);
        const holding = rows.find((row) => World.contains(row, x, y));
        if (holding || rows.length === 0) return holding;
        const distance = (row: Row) =>
            ((float(row, "Region_0") + float(row, "Region_3")) / 2 - x) ** 2 +
            ((float(row, "Region_1") + float(row, "Region_4")) / 2 - y) ** 2;
        return rows.reduce((best, row) => (distance(row) < distance(best) ? row : best));
    }

    /**
     * The map's rectangle on Azeroth's map, as C_Map.GetMapRectOnMap(mapID, 947): through
     * the first of its assignments that Azeroth's map (or the nearest map above it with
     * that game map) places. From OpenMap's tools/uimap.py.
     */
    rect(mapID: number): Rect | null {
        if (mapID === WORLD) return [0, 1, 0, 1];
        const known = this.rects.get(mapID);
        if (known !== undefined) return known;
        let out: Rect | null = null;
        for (const row of this.assignments.get(mapID) ?? []) {
            const gameMap = integer(row, "MapID");
            const cx = (float(row, "Region_0") + float(row, "Region_3")) / 2;
            const cy = (float(row, "Region_1") + float(row, "Region_4")) / 2;
            let hostRect: Rect | null = [0, 1, 0, 1];
            let host = this.hostRow(WORLD, gameMap, cx, cy);
            if (!host) {
                for (let parent = this.maps.get(mapID)?.parent ?? 0, steps = 0; parent && parent !== WORLD && steps < 10; steps++) {
                    host = this.hostRow(parent, gameMap, cx, cy);
                    if (host) {
                        hostRect = this.rect(parent);
                        break;
                    }
                    parent = this.maps.get(parent)?.parent ?? 0;
                }
                if (!host || !hostRect) continue;
            }
            const [u0, v0] = World.normalized(host, float(row, "Region_3"), float(row, "Region_4"));
            const [u1, v1] = World.normalized(host, float(row, "Region_0"), float(row, "Region_1"));
            let left = Math.min(u0, u1);
            const right = Math.max(u0, u1);
            let top = Math.min(v0, v1);
            const bottom = Math.max(v0, v1);
            const minU = float(row, "UiMin_0");
            const minV = float(row, "UiMin_1");
            const maxU = float(row, "UiMax_0");
            const maxV = float(row, "UiMax_1");
            if (maxU <= minU || maxV <= minV) continue;
            const width = (right - left) / (maxU - minU);
            const height = (bottom - top) / (maxV - minV);
            left -= minU * width;
            top -= minV * height;
            const [hl, hr, ht, hb] = hostRect;
            out = [hl + left * (hr - hl), hl + (left + width) * (hr - hl), ht + top * (hb - ht), ht + (top + height) * (hb - ht)];
            break;
        }
        this.rects.set(mapID, out);
        return out;
    }
}
