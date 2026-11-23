// Generates modules/inventory/cheapest/data.lua: the items `inventory.cheapest`
// can leave unmarked whatever they sell for, from the Forever client's own DB2
// tables as exported by wago.tools:
//   Tools          what profession spells need on hand (Mining Pick, Blacksmith
//                  Hammer, Runed Copper Rod, Flint and Tinder...);
//   ClassReagents  what class spells use up or need on hand (Ankh, Soul Shard,
//                  Earth Totem...), with the classes casting them.
//
// A spell needs an item on hand through SpellTotems: the item itself (Totem_n),
// or a tool category (RequiredTotemCategoryID_n) that an item's category
// (ItemSparse.TotemCategoryID) satisfies: same type, and a mask holding the
// required one's bits (the Gnomish Army Knife holds every tool's). It uses
// items up through SpellReagents. Its skill lines (SkillLineAbility) tell
// profession spells (professions.ts' SKILL_LINES) from class spells: skill
// lines of the class category that SkillRaceClassInfo gives to a single class
// (pet, mount and shared lines left out). Deprecated items and items the
// client doesn't know (no ItemSparse row) are left out. Fishing poles and ammo
// are item classes the addon reads at runtime, not listed here.
//
//   bun run cheapest                     latest Forever (wowf) build
//   bun run cheapest --build 1.60.1.71037
//   bun run cheapest --refresh           download again instead of using tools/.cache

import { writeFile } from "node:fs/promises";
import path from "node:path";
import { SKILL_LINES } from "./professions";
import { integer, latestBuild, parseCsv, type Row, table } from "./wago";

const OUTPUT = "modules/inventory/cheapest/data.lua";
const CACHE = "tools/.cache/cheapest";
const REAGENT_SLOTS = 8;
const TOTEM_SLOTS = 2;

// SkillLine.CategoryID of class skill lines.
const CATEGORY_CLASS = 7;

// ItemSparse.Flags_0.
const ITEM_FLAG_DEPRECATED = 0x10;

export type Tables = {
    itemSparse: string;
    totemCategory: string;
    spellTotems: string;
    spellReagents: string;
    skillLine: string;
    skillLineAbility: string;
    skillRaceClassInfo: string;
    chrClasses: string;
};

export type Keepers = {
    /** Item ID -> name. */
    tools: Map<number, string>;
    /** Item ID -> name and the class file names casting spells that use it. */
    classReagents: Map<number, { name: string; classes: string[] }>;
};

/** Spell ID -> the items it uses up (SpellReagents). */
function reagentsBySpell(rows: Row[]): Map<number, number[]> {
    const bySpell = new Map<number, number[]>();
    for (const row of rows) {
        const items: number[] = [];
        for (let slot = 0; slot < REAGENT_SLOTS; slot++) {
            const itemID = integer(row, `Reagent_${slot}`);
            if (itemID > 0 && integer(row, `ReagentCount_${slot}`) > 0) {
                items.push(itemID);
            }
        }
        bySpell.set(integer(row, "SpellID"), [...(bySpell.get(integer(row, "SpellID")) ?? []), ...items]);
    }
    return bySpell;
}

export function collectKeepers(tables: Tables): Keepers {
    // Items the client knows and still uses: item ID -> its ItemSparse row.
    const items = new Map<number, Row>();
    for (const row of parseCsv(tables.itemSparse)) {
        if ((integer(row, "Flags_0") & ITEM_FLAG_DEPRECATED) === 0) {
            items.set(integer(row, "ID"), row);
        }
    }

    // Tool categories: ID -> type and mask (unsigned).
    const categories = new Map<number, { type: number; mask: number }>();
    for (const row of parseCsv(tables.totemCategory)) {
        categories.set(integer(row, "ID"), {
            type: integer(row, "TotemCategoryType"),
            mask: integer(row, "TotemCategoryMask") >>> 0,
        });
    }
    // The items satisfying each required category.
    const itemsByCategory = new Map<number, number[]>();
    for (const [itemID, row] of items) {
        const own = categories.get(integer(row, "TotemCategoryID"));
        if (!own) {
            continue;
        }
        for (const [categoryID, required] of categories) {
            if (own.type === required.type && (own.mask & required.mask) >>> 0 === required.mask) {
                itemsByCategory.set(categoryID, [...(itemsByCategory.get(categoryID) ?? []), itemID]);
            }
        }
    }
    // Spell ID -> the items it needs on hand.
    const toolsBySpell = new Map<number, number[]>();
    for (const row of parseCsv(tables.spellTotems)) {
        const needed: number[] = [];
        for (let slot = 0; slot < TOTEM_SLOTS; slot++) {
            const itemID = integer(row, `Totem_${slot}`);
            if (itemID > 0) {
                needed.push(itemID);
            }
            needed.push(...(itemsByCategory.get(integer(row, `RequiredTotemCategoryID_${slot}`)) ?? []));
        }
        const spellID = integer(row, "SpellID");
        toolsBySpell.set(spellID, [...(toolsBySpell.get(spellID) ?? []), ...needed]);
    }
    const reagents = reagentsBySpell(parseCsv(tables.spellReagents));

    // Class skill lines -> the class file name of the one class they belong to.
    const classFiles = new Map(parseCsv(tables.chrClasses).map((row) => [integer(row, "ID"), row.Filename]));
    const classMasks = new Map<number, Set<number>>();
    for (const row of parseCsv(tables.skillRaceClassInfo)) {
        const skillID = integer(row, "SkillID");
        classMasks.set(skillID, (classMasks.get(skillID) ?? new Set()).add(integer(row, "ClassMask")));
    }
    const classOfLine = new Map<number, string>();
    for (const row of parseCsv(tables.skillLine)) {
        const masks = [...(classMasks.get(integer(row, "ID")) ?? [])];
        if (integer(row, "CategoryID") !== CATEGORY_CLASS || masks.length !== 1) {
            continue;
        }
        const classID = Math.log2(masks[0]) + 1;
        const file = classFiles.get(classID);
        if (Number.isInteger(classID) && file) {
            classOfLine.set(integer(row, "ID"), file);
        }
    }

    const professions = new Set(SKILL_LINES);
    const tools = new Map<number, string>();
    const classReagents = new Map<number, { name: string; classes: string[] }>();
    for (const row of parseCsv(tables.skillLineAbility)) {
        const skillLine = integer(row, "SkillLine");
        const spellID = integer(row, "Spell");
        const className = classOfLine.get(skillLine);
        if (professions.has(skillLine)) {
            for (const itemID of toolsBySpell.get(spellID) ?? []) {
                const item = items.get(itemID);
                if (item) {
                    tools.set(itemID, item.Display_lang);
                }
            }
        } else if (className) {
            for (const itemID of [...(toolsBySpell.get(spellID) ?? []), ...(reagents.get(spellID) ?? [])]) {
                const item = items.get(itemID);
                if (!item) {
                    continue;
                }
                const entry = classReagents.get(itemID) ?? { name: item.Display_lang, classes: [] };
                if (!entry.classes.includes(className)) {
                    entry.classes.push(className);
                    entry.classes.sort();
                }
                classReagents.set(itemID, entry);
            }
        }
    }
    return { tools, classReagents };
}

export function renderLua(keepers: Keepers, build: string): string {
    const sorted = <T>(map: Map<number, T>) => [...map.entries()].sort(([a], [b]) => a - b);
    const lines = [
        `-- Generated by tools/cheapest.ts from Forever's DB2 tables (build ${build}). Do not edit.`,
        "-- Item ID -> true for the tools profession spells need on hand, and item ID ->",
        "-- the classes (file names) whose spells use up or need the item on hand.",
        "",
        "local _, ns = ...",
        "",
        'local Cheapest = ns:GetFeature("inventory", "cheapest")',
        "",
        "Cheapest.Tools = {",
        ...sorted(keepers.tools).map(([itemID, name]) => `    [${itemID}] = true, -- ${name}`),
        "}",
        "",
        "Cheapest.ClassReagents = {",
        ...sorted(keepers.classReagents).map(
            ([itemID, { name, classes }]) =>
                `    [${itemID}] = { ${classes.map((file) => `"${file}"`).join(", ")} }, -- ${name}`,
        ),
        "}",
        "",
    ];
    return lines.join("\n");
}

if (import.meta.main) {
    const args = Bun.argv.slice(2);
    const buildIndex = args.indexOf("--build");
    const build = buildIndex >= 0 ? args[buildIndex + 1] : await latestBuild();
    const refresh = args.includes("--refresh");
    const repoRoot = path.resolve(import.meta.dir, "..");
    const load = (name: string) => table(path.join(repoRoot, CACHE), name, build, refresh);

    const keepers = collectKeepers({
        itemSparse: await load("ItemSparse"),
        totemCategory: await load("TotemCategory"),
        spellTotems: await load("SpellTotems"),
        spellReagents: await load("SpellReagents"),
        skillLine: await load("SkillLine"),
        skillLineAbility: await load("SkillLineAbility"),
        skillRaceClassInfo: await load("SkillRaceClassInfo"),
        chrClasses: await load("ChrClasses"),
    });
    const output = path.join(repoRoot, OUTPUT);
    await writeFile(output, renderLua(keepers, build));
    // StyLua's layout, so `bun run lint` passes on the generated file.
    const stylua = Bun.spawnSync(["stylua", output], { stdout: "inherit", stderr: "inherit" });
    if (stylua.exitCode !== 0) {
        throw new Error("stylua failed on the generated file");
    }
    console.log(`${OUTPUT}: ${keepers.tools.size} tools, ${keepers.classReagents.size} class reagents (build ${build})`);
}
