// Generates modules/inventory/food/data.lua: the food and drink a slot of
// `inventory.food` can hold, from the Forever client's own DB2 tables as
// exported by wago.tools.
//
// An item of the Food & Drink subclass is food when its Use spell (ItemXItemEffect
// -> ItemEffect, on use) applies health regeneration (aura MOD_REGEN) and drink
// when it applies mana regeneration (MOD_POWER_REGEN), the amount per tick
// being what it restores. The aura may sit on a spell the Use spell triggers:
// Forever's buff food ("Nutritious Food") triggers the plain Food spell of its
// tier and adds its buff. Any other effect (a buff, a stacking aura, alcohol)
// marks the item as buff food. The regenerating spell must be in the food or
// drink cooldown category (its own, else the item's), which leaves out potions restoring over time (Green
// Tea Leaf). Food restoring a share of the player's health (holiday food) has
// no amount to rank and is left out, as are deprecated items.
//
//   bun run food                     latest Forever (wowf) build
//   bun run food --build 1.60.1.71037
//   bun run food --refresh           download again instead of using tools/.cache

import { writeFile } from "node:fs/promises";
import path from "node:path";
import { float, integer, latestBuild, parseCsv, type Row, table } from "./wago";

const OUTPUT = "modules/inventory/food/data.lua";
const CACHE = "tools/.cache/food";

// Item class Consumable, subclass Food & Drink.
const CLASS_CONSUMABLE = 0;
const SUBCLASS_FOOD_AND_DRINK = 5;

// ItemSparse.Flags_0.
const ITEM_FLAG_CONJURED = 0x2;
const ITEM_FLAG_DEPRECATED = 0x10;

// ItemEffect.TriggerType: the item's Use.
const TRIGGER_ON_USE = 0;

// SpellEffect.Effect.
const EFFECT_NONE = 0;
const EFFECT_APPLY_AURA = 6;
const EFFECT_TRIGGER_SPELL = 64;

// SpellEffect.EffectAura.
const AURA_MOD_REGEN = 84;
const AURA_MOD_POWER_REGEN = 85;

// SpellCategories.Category: the food and drink cooldowns.
const CATEGORY_FOOD = 11;
const CATEGORY_DRINK = 59;

// How deep triggered spells are followed (a Use spell triggering a Food spell is 1).
const MAX_TRIGGER_DEPTH = 2;

export type Food = {
    food?: number;
    drink?: number;
    level: number;
    price: number;
    conjured: boolean;
    buff: boolean;
};

type Restoration = { food?: number; drink?: number; buff: boolean };

export type Tables = {
    item: string;
    itemSparse: string;
    itemXItemEffect: string;
    itemEffect: string;
    spellEffect: string;
    spellCategories: string;
};

/** Item ID -> what it restores, for every food and drink item. */
export function collectFood(tables: Tables): Map<number, Food> {
    const sparse = new Map(parseCsv(tables.itemSparse).map((row) => [integer(row, "ID"), row]));
    const effectsBySpell = new Map<number, Row[]>();
    for (const row of parseCsv(tables.spellEffect)) {
        // Effects of other difficulties don't apply in the open world.
        if (integer(row, "DifficultyID") !== 0) {
            continue;
        }
        const spellID = integer(row, "SpellID");
        const effects = effectsBySpell.get(spellID) ?? [];
        effects.push(row);
        effectsBySpell.set(spellID, effects);
    }
    const categories = new Map<number, number>();
    for (const row of parseCsv(tables.spellCategories)) {
        if (integer(row, "DifficultyID") === 0) {
            categories.set(integer(row, "SpellID"), integer(row, "Category"));
        }
    }
    const itemEffects = new Map(parseCsv(tables.itemEffect).map((row) => [integer(row, "ID"), row]));
    // Item ID -> its Use spells, with the cooldown category the item gives them.
    const useSpells = new Map<number, { spellID: number; category: number }[]>();
    for (const row of parseCsv(tables.itemXItemEffect)) {
        const effect = itemEffects.get(integer(row, "ItemEffectID"));
        if (effect && integer(effect, "TriggerType") === TRIGGER_ON_USE) {
            const itemID = integer(row, "ItemID");
            const spells = useSpells.get(itemID) ?? [];
            spells.push({ spellID: integer(effect, "SpellID"), category: integer(effect, "SpellCategoryID") });
            useSpells.set(itemID, spells);
        }
    }

    // What the spell and those it triggers restore, and whether they do anything
    // else. A spell without a category of its own takes the one of the item or
    // spell triggering it (the manna biscuits' food and drink spells).
    const restoration = (spellID: number, inherited: number, depth: number, into: Restoration) => {
        const category = categories.get(spellID) || inherited;
        for (const effect of effectsBySpell.get(spellID) ?? []) {
            const kind = integer(effect, "Effect");
            const aura = integer(effect, "EffectAura");
            // Food restoring mana too (Senggin Root) is in the food category.
            const regenerates = category === CATEGORY_FOOD || category === CATEGORY_DRINK;
            if (kind === EFFECT_NONE) {
                continue;
            } else if (kind === EFFECT_APPLY_AURA && aura === AURA_MOD_REGEN && regenerates) {
                into.food = Math.max(into.food ?? 0, float(effect, "EffectBasePointsF"));
            } else if (kind === EFFECT_APPLY_AURA && aura === AURA_MOD_POWER_REGEN && regenerates) {
                into.drink = Math.max(into.drink ?? 0, float(effect, "EffectBasePointsF"));
            } else if (kind === EFFECT_TRIGGER_SPELL && depth < MAX_TRIGGER_DEPTH) {
                restoration(integer(effect, "EffectTriggerSpell"), category, depth + 1, into);
            } else {
                into.buff = true;
            }
        }
    };

    const food = new Map<number, Food>();
    for (const row of parseCsv(tables.item)) {
        if (integer(row, "ClassID") !== CLASS_CONSUMABLE || integer(row, "SubclassID") !== SUBCLASS_FOOD_AND_DRINK) {
            continue;
        }
        const itemID = integer(row, "ID");
        const item = sparse.get(itemID);
        if (!item || (integer(item, "Flags_0") & ITEM_FLAG_DEPRECATED) !== 0) {
            continue;
        }
        const restores: Restoration = { buff: false };
        for (const { spellID, category } of useSpells.get(itemID) ?? []) {
            restoration(spellID, category, 0, restores);
        }
        if (restores.food === undefined && restores.drink === undefined) {
            continue;
        }
        food.set(itemID, {
            ...restores,
            level: integer(item, "RequiredLevel"),
            price: integer(item, "SellPrice"),
            conjured: (integer(item, "Flags_0") & ITEM_FLAG_CONJURED) !== 0,
        });
    }
    return food;
}

function renderEntry(itemID: number, item: Food): string {
    const fields: string[] = [];
    if (item.food !== undefined) {
        fields.push(`food = ${item.food}`);
    }
    if (item.drink !== undefined) {
        fields.push(`drink = ${item.drink}`);
    }
    fields.push(`level = ${item.level}`, `price = ${item.price}`);
    if (item.conjured) {
        fields.push("conjured = true");
    }
    if (item.buff) {
        fields.push("buff = true");
    }
    return `    [${itemID}] = { ${fields.join(", ")} },`;
}

export function renderLua(food: Map<number, Food>, build: string): string {
    const itemIDs = [...food.keys()].sort((a, b) => a - b);
    const lines = [
        `-- Generated by tools/food.ts from Forever's DB2 tables (build ${build}). Do not edit.`,
        "-- Item ID -> what it restores per tick: food (health) and drink (mana), the",
        "-- required level, the sell price in copper, and whether it's conjured or buff food.",
        "",
        "local _, ns = ...",
        "",
        'local Food = ns:GetFeature("inventory", "food")',
        "",
        "Food.Data = {",
        ...itemIDs.map((itemID) => renderEntry(itemID, food.get(itemID)!)),
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

    const food = collectFood({
        item: await load("Item"),
        itemSparse: await load("ItemSparse"),
        itemXItemEffect: await load("ItemXItemEffect"),
        itemEffect: await load("ItemEffect"),
        spellEffect: await load("SpellEffect"),
        spellCategories: await load("SpellCategories"),
    });
    const output = path.join(repoRoot, OUTPUT);
    await writeFile(output, renderLua(food, build));
    // StyLua's layout, so `bun run lint` passes on the generated file.
    const stylua = Bun.spawnSync(["stylua", output], { stdout: "inherit", stderr: "inherit" });
    if (stylua.exitCode !== 0) {
        throw new Error("stylua failed on the generated file");
    }
    console.log(`${OUTPUT}: ${food.size} items (build ${build})`);
}
