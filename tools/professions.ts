// Generates modules/professions/reagents/data.lua: for each reagent item, the
// profession recipes that use it, from the Forever client's own DB2 tables
// (SpellReagents + SkillLineAbility) as exported by wago.tools.
//
//   bun run professions                 latest Forever (wowf) build
//   bun run professions --build 1.60.1.70888
//   bun run professions --refresh       download again instead of using tools/.cache

import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const WAGO = "https://wago.tools";
const PRODUCT = "wowf";
const OUTPUT = "modules/professions/reagents/data.lua";
const CACHE = "tools/.cache/professions";
const REAGENT_SLOTS = 8;

// Skill lines whose recipes use reagents: First Aid, Blacksmithing,
// Leatherworking, Alchemy, Cooking, Mining (smelting), Tailoring, Engineering,
// Enchanting. Each item's uses follow this order, and tooltips list the
// professions in it.
export const SKILL_LINES = [129, 185, 171, 164, 165, 197, 202, 333, 186];

type Row = Record<string, string>;

/** A recipe that uses an item: spell, skill line, quantity of the item. */
export type Use = [spellID: number, skillLineID: number, quantity: number];

function parseLine(line: string): string[] {
    const fields: string[] = [];
    let field = "";
    let quoted = false;
    for (let i = 0; i < line.length; i++) {
        const char = line[i];
        if (quoted) {
            if (char === '"' && line[i + 1] === '"') {
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
        } else {
            field += char;
        }
    }
    fields.push(field);
    return fields;
}

export function parseCsv(content: string): Row[] {
    const lines = content
        .replace(/^﻿/, "")
        .split(/\r?\n/)
        .filter((line) => line.length > 0);
    if (lines.length === 0) {
        return [];
    }
    const headers = parseLine(lines[0]);
    return lines.slice(1).map((line, index) => {
        const fields = parseLine(line);
        if (fields.length !== headers.length) {
            throw new Error(`CSV row ${index + 2} has ${fields.length} fields, expected ${headers.length}`);
        }
        return Object.fromEntries(headers.map((header, i) => [header, fields[i]]));
    });
}

function integer(row: Row, field: string): number {
    const value = Number(row[field]);
    if (!Number.isInteger(value)) {
        throw new Error(`DB2 field ${field} must be an integer, got '${row[field]}'`);
    }
    return value;
}

/** Item ID → the recipes using it, ordered by profession (SKILL_LINES) then spell. */
export function collectUses(spellReagentsCsv: string, skillLineAbilityCsv: string): Map<number, Use[]> {
    const reagentsBySpell = new Map<number, [number, number][]>();
    for (const row of parseCsv(spellReagentsCsv)) {
        const spellID = integer(row, "SpellID");
        const reagents: [number, number][] = [];
        for (let slot = 0; slot < REAGENT_SLOTS; slot++) {
            const itemID = integer(row, `Reagent_${slot}`);
            const quantity = integer(row, `ReagentCount_${slot}`);
            if (itemID > 0 && quantity > 0) {
                reagents.push([itemID, quantity]);
            }
        }
        if (spellID <= 0 || reagents.length === 0) {
            continue;
        }
        if (reagentsBySpell.has(spellID)) {
            throw new Error(`SpellReagents lists spell ${spellID} twice`);
        }
        reagentsBySpell.set(spellID, reagents);
    }

    // A few recipes belong to two professions (Synthetic Gordok Ogre Suit:
    // Tailoring and Leatherworking): one use per profession.
    const recipes = new Set<string>();
    for (const row of parseCsv(skillLineAbilityCsv)) {
        const skillLineID = integer(row, "SkillLine");
        const spellID = integer(row, "Spell");
        if (SKILL_LINES.includes(skillLineID) && reagentsBySpell.has(spellID)) {
            recipes.add(`${spellID}:${skillLineID}`);
        }
    }

    const uses = new Map<number, Use[]>();
    for (const recipe of recipes) {
        const [spellID, skillLineID] = recipe.split(":").map(Number);
        for (const [itemID, quantity] of reagentsBySpell.get(spellID)!) {
            const list = uses.get(itemID) ?? [];
            // A recipe listing the same item in two slots needs both.
            const same = list.find((use) => use[0] === spellID && use[1] === skillLineID);
            if (same) {
                same[2] += quantity;
            } else {
                list.push([spellID, skillLineID, quantity]);
            }
            uses.set(itemID, list);
        }
    }
    for (const list of uses.values()) {
        list.sort((a, b) => SKILL_LINES.indexOf(a[1]) - SKILL_LINES.indexOf(b[1]) || a[0] - b[0]);
    }
    return uses;
}

export function renderLua(uses: Map<number, Use[]>, build: string): string {
    const items = [...uses.keys()].sort((a, b) => a - b);
    const lines = [
        `-- Generated by tools/professions.ts from Forever's DB2 tables (build ${build}). Do not edit.`,
        "-- Item ID -> the recipes that use it: { spellID, skillLineID, quantity }.",
        "",
        "local _, ns = ...",
        "",
        'local Reagents = ns:GetFeature("professions", "reagents")',
        "",
        "Reagents.Data = {",
        ...items.map((itemID) => {
            const list = uses.get(itemID)!.map((use) => `{ ${use.join(", ")} }`);
            return `    [${itemID}] = { ${list.join(", ")} },`;
        }),
        "}",
        "",
    ];
    return lines.join("\n");
}

async function latestBuild(): Promise<string> {
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

async function table(repoRoot: string, name: string, build: string, refresh: boolean): Promise<string> {
    const cached = path.join(repoRoot, CACHE, build, `${name}.csv`);
    if (!refresh && existsSync(cached)) {
        return readFile(cached, "utf8");
    }
    const url = `${WAGO}/db2/${name}/csv?build=${encodeURIComponent(build)}`;
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`Failed to download ${url}: HTTP ${response.status}`);
    }
    const content = await response.text();
    await mkdir(path.dirname(cached), { recursive: true });
    await writeFile(cached, content);
    return content;
}

if (import.meta.main) {
    const args = Bun.argv.slice(2);
    const buildIndex = args.indexOf("--build");
    const build = buildIndex >= 0 ? args[buildIndex + 1] : await latestBuild();
    const refresh = args.includes("--refresh");
    const repoRoot = path.resolve(import.meta.dir, "..");

    const uses = collectUses(
        await table(repoRoot, "SpellReagents", build, refresh),
        await table(repoRoot, "SkillLineAbility", build, refresh),
    );
    const output = path.join(repoRoot, OUTPUT);
    await writeFile(output, renderLua(uses, build));
    // StyLua's layout, so `bun run lint` passes on the generated file.
    const stylua = Bun.spawnSync(["stylua", output], { stdout: "inherit", stderr: "inherit" });
    if (stylua.exitCode !== 0) {
        throw new Error("stylua failed on the generated file");
    }

    const recipes = new Set([...uses.values()].flatMap((list) => list.map((use) => use[0])));
    console.log(`${OUTPUT}: ${uses.size} reagents, ${recipes.size} recipes (build ${build})`);
}
