// wago.tools, where the generators get the Forever client's data: its latest build, its
// DB2 tables as CSV and its files (CASC), downloaded once into tools/.cache.

import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

export const WAGO = "https://wago.tools";
const PRODUCT = "wowf";

export type Row = Record<string, string>;

// The records of a CSV file: quoted fields may hold commas, doubled quotes and
// line breaks (text columns like Map's descriptions). Blank lines are skipped.
function parseRecords(content: string): string[][] {
    const records: string[][] = [];
    let fields: string[] = [];
    let field = "";
    let quoted = false;
    const endRecord = () => {
        fields.push(field);
        if (fields.length > 1 || fields[0] !== "") {
            records.push(fields);
        }
        fields = [];
        field = "";
    };
    for (let i = 0; i < content.length; i++) {
        const char = content[i];
        if (quoted) {
            if (char === '"' && content[i + 1] === '"') {
                field += '"';
                i++;
            } else if (char === '"') {
                quoted = false;
            } else {
                field += char;
            }
        } else if (char === '"') {
            quoted = true;
        } else if (char === ",") {
            fields.push(field);
            field = "";
        } else if (char === "\n") {
            endRecord();
        } else if (char !== "\r") {
            field += char;
        }
    }
    endRecord();
    return records;
}

export function parseCsv(content: string): Row[] {
    const records = parseRecords(content.replace(/^﻿/, ""));
    if (records.length === 0) {
        return [];
    }
    const headers = records[0];
    return records.slice(1).map((fields, index) => {
        if (fields.length !== headers.length) {
            throw new Error(`CSV record ${index + 2} has ${fields.length} fields, expected ${headers.length}`);
        }
        return Object.fromEntries(headers.map((header, i) => [header, fields[i]]));
    });
}

export function integer(row: Row, field: string): number {
    const value = Number(row[field]);
    if (!Number.isInteger(value)) {
        throw new Error(`DB2 field ${field} must be an integer, got '${row[field]}'`);
    }
    return value;
}

export function float(row: Row, field: string): number {
    const value = Number(row[field]);
    if (row[field] === undefined || row[field] === "" || !Number.isFinite(value)) {
        throw new Error(`DB2 field ${field} must be a number, got '${row[field]}'`);
    }
    return value;
}

export async function latestBuild(): Promise<string> {
    const response = await fetch(`${WAGO}/api/builds`);
    if (!response.ok) {
        throw new Error(`Failed to list builds: HTTP ${response.status}`);
    }
    const builds = (await response.json()) as Record<string, { version: string }[]>;
    const build = builds[PRODUCT]?.[0]?.version;
    if (!build) {
        throw new Error(`No ${PRODUCT} build on wago.tools`);
    }
    return build;
}

/** `url`'s content, kept at `at` (downloaded again when `refresh`, or when it isn't there). */
export async function cached(at: string, url: string, refresh: boolean): Promise<Uint8Array> {
    if (!refresh && existsSync(at)) {
        return new Uint8Array(await readFile(at));
    }
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`Failed to download ${url}: HTTP ${response.status}`);
    }
    const content = new Uint8Array(await response.arrayBuffer());
    await mkdir(path.dirname(at), { recursive: true });
    await writeFile(at, content);
    return content;
}

/** A DB2 table of `build` as CSV, kept in `cacheDir/<build>/<name>.csv`. */
export async function table(cacheDir: string, name: string, build: string, refresh: boolean): Promise<string> {
    const url = `${WAGO}/db2/${name}/csv?build=${encodeURIComponent(build)}`;
    return new TextDecoder().decode(await cached(path.join(cacheDir, build, `${name}.csv`), url, refresh));
}

/** A game file of `build` by file ID, kept in `cacheDir/<name>`. */
export async function gameFile(cacheDir: string, fileID: number, name: string, build: string, refresh: boolean) {
    const url = `${WAGO}/api/casc/${fileID}?download&version=${encodeURIComponent(build)}`;
    return cached(path.join(cacheDir, name), url, refresh);
}
