// Generates, from the Forever client's own DB2 tables as exported by wago.tools,
// modules/combat/dots/data.lua: the damage over time spells the overlay follows
// and what changes their damage, as the client's data gives them:
//   - each spell's tick interval, school and spell power coefficient per tick
//     (SpellEffect, its periodic damage aura), whether it spends combo points (a
//     finishing move) or awards some, and each of the player's ranks' damage per
//     tick and duration;
//   - the passive talents raising its periodic damage, or lengthening it, at
//     each rank (TraitDefinitionEffectPoints curves, the talent's base points
//     without one), found by the class mask of their spell modifiers;
//   - the debuffs a spell puts on its target raising the damage it takes from
//     the caster's spells (Hemorrhage), with their bonus and duration;
//   - the marks followed (Death Mark), with their duration;
//   - the direct damage spells of the marks' classes (the strikes the marks
//     store): the weapon they strike with, normalized or not, and each rank's
//     flat damage and weapon damage percentage (and its percentage with a
//     dagger, an effect only the description names), with the passive talents
//     raising their damage.
// What the server adds in its own code (attack power) isn't in the data: it is
// measured in game, in modules/combat/dots/measured.lua. Creatures' armor
// isn't either: it comes from CMaNGOS's Classic database (tools/cmangos.ts),
// a creature's base armor by NPC class and level, and each creature's
// multiplier where it isn't 1.
//
//   bun run dots                    latest Forever (wowf) build
//   bun run dots --build 1.60.1.70888
//   bun run dots --refresh          download again instead of using tools/.cache

import { writeFile } from "node:fs/promises";
import path from "node:path";
import { CMANGOS_COMMIT, dump, sqlTable } from "./cmangos";
import { float, integer, latestBuild, parseCsv, type Row, table } from "./wago";

const OUTPUT = "modules/combat/dots/data.lua";
const CACHE = "tools/.cache/dots";

// The spells followed, by the spell ID of one rank (every rank shares the name).
// Only spells cast on the target whose ticks are all alike: not projectiles
// (they land, and miss, after the cast: refused below), nor ramping ones (Bane
// of Agony), nor health drains (Siphon Life, Devouring Plague). Each needs an
// entry in measured.lua.
export const FOLLOWED = [
    703, // Garrote
    1943, // Rupture
    772, // Rend
    1822, // Rake
    8921, // Moonfire
    5570, // Insect Swarm
    589, // Shadow Word: Pain
    14914, // Holy Fire
    172, // Corruption
    348, // Immolate
    8050, // Flame Shock
];

// Finishing moves marking the target, followed by the spell ID of one rank: the
// mark stores part of the damage the player deals the target, then deals it at
// once when it ends. How much it stores and its cap are read from its
// description; which effects it stores more of is in measured.lua.
export const MARKS = [
    1316709, // Death Mark
];

// SpellEffect, SpellMisc and SpellPower values.
const AURA_PERIODIC_DAMAGE = 3;
const AURA_ADD_FLAT_MODIFIER = 107;
const AURA_ADD_PCT_MODIFIER = 108;
const AURA_MOD_DAMAGE_FROM_CASTER = 271;
const EFFECT_SCHOOL_DAMAGE = 2;
const EFFECT_APPLY_AURA = 6;
const EFFECT_WEAPON_DAMAGE_NOSCHOOL = 17;
const EFFECT_ENERGIZE = 30;
const EFFECT_WEAPON_PERCENT_DAMAGE = 31;
const EFFECT_WEAPON_DAMAGE = 58;
const EFFECT_NORMALIZED_WEAPON_DAMAGE = 121;
const POWER_COMBO_POINTS = 4;
const SPELLMOD_DAMAGE = 0;
const SPELLMOD_DURATION = 1;
const SPELLMOD_DOT = 22;
const TARGET_UNIT_TARGET_ENEMY = 6;
const ATTRIBUTE_PASSIVE = 0x40;
const ATTRIBUTE_RANGED = 0x2;
const ATTRIBUTE3_OFF_HAND = 0x1000000;
const CLASS_MASK_WORDS = 4;
// A weapon damage percentage only the description names: "$m4% if a Dagger".
const DAGGER_PERCENT = /\$m(\d)% if a Dagger/;

export type ComboPoints = "spend" | "award" | undefined;

/** Rank spell ID → [damage per tick, before talents and bonuses; duration in seconds]. */
export type Ranks = Map<number, [number, number]>;
export type Spell = {
    spellID: number;
    key: string;
    tick: number;
    school: number;
    spellPower: number;
    comboPoints: ComboPoints;
    ranks?: Ranks;
};
/** Talent spell ID → spell key → value at each rank. */
export type Talents = Map<number, Map<string, number[]>>;
export type Amplifier = {
    spellID: number;
    key: string;
    bonus: number;
    duration: number;
    amplifies: string[];
    comboPoints: ComboPoints;
};

export type Mark = {
    spellID: number;
    key: string;
    duration: number;
    comboPoints: ComboPoints;
};

/** Rank spell ID → [flat damage, weapon damage percentage, its percentage with a dagger]. */
export type StrikeRanks = Map<number, [number, number, number | undefined]>;
export type Strike = {
    spellID: number;
    key: string;
    hand: "main" | "off" | undefined;
    normalized: boolean;
    comboPoints: ComboPoints;
    ranks?: StrikeRanks;
};

export type Tables = {
    SpellEffect: Row[];
    SpellClassOptions: Row[];
    SpellMisc: Row[];
    SpellDuration: Row[];
    SpellName: Row[];
    TraitDefinition: Row[];
    TraitNodeEntry: Row[];
    TraitDefinitionEffectPoints: Row[];
    CurvePoint: Row[];
    SkillLineAbility: Row[];
    SpellPower: Row[];
    Spell: Row[];
};

export const TABLE_NAMES: (keyof Tables)[] = [
    "SpellEffect",
    "SpellClassOptions",
    "SpellMisc",
    "SpellDuration",
    "SpellName",
    "TraitDefinition",
    "TraitNodeEntry",
    "TraitDefinitionEffectPoints",
    "CurvePoint",
    "SkillLineAbility",
    "SpellPower",
    "Spell",
];

type ClassOptions = { classSet: number; mask: number[] };

function groupBy(rows: Row[], field: string): Map<number, Row[]> {
    const groups = new Map<number, Row[]>();
    for (const row of rows) {
        const key = integer(row, field);
        groups.set(key, [...(groups.get(key) ?? []), row]);
    }
    return groups;
}

function maskOf(row: Row, prefix: string): number[] {
    return Array.from({ length: CLASS_MASK_WORDS }, (_, word) => integer(row, `${prefix}_${word}`));
}

function overlaps(a: number[], b: number[]): boolean {
    return a.some((word, index) => (word & b[index]) !== 0);
}

// "Garrote" → "garrote", "Shadow Word: Pain" → "shadow_word_pain".
function keyOf(name: string): string {
    return name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_|_$/g, "");
}

// The game's school index (GetSpellBonusDamage) of a single school mask.
function schoolOf(mask: number): number {
    const index = Math.log2(mask);
    if (!Number.isInteger(index)) {
        throw new Error(`School mask ${mask} isn't a single school`);
    }
    return index + 1;
}

function comboPointsOf(effects: Row[], durationRow: Row | undefined, costs: Row[]): ComboPoints {
    const periodic = effects.find((effect) => integer(effect, "EffectAura") === AURA_PERIODIC_DAMAGE);
    const spends =
        costs.some((cost) => integer(cost, "PowerType") === POWER_COMBO_POINTS) ||
        (periodic !== undefined && float(periodic, "EffectPointsPerResource") > 0) ||
        (durationRow !== undefined && integer(durationRow, "DurationPerResource") > 0);
    if (spends) {
        return "spend";
    }
    const awards = effects.some(
        (effect) =>
            integer(effect, "Effect") === EFFECT_ENERGIZE &&
            integer(effect, "EffectMiscValue_0") === POWER_COMBO_POINTS,
    );
    return awards ? "award" : undefined;
}

export function collect(tables: Tables, followed: number[], marked: number[]) {
    const effectsBySpell = groupBy(tables.SpellEffect, "SpellID");
    const costsBySpell = groupBy(tables.SpellPower, "SpellID");
    const costsOf = (spellID: number) => costsBySpell.get(spellID) ?? [];
    const names = new Map(tables.SpellName.map((row) => [integer(row, "ID"), row.Name_lang]));
    const classOptions = new Map<number, ClassOptions>(
        tables.SpellClassOptions.map((row) => [
            integer(row, "SpellID"),
            { classSet: integer(row, "SpellClassSet"), mask: maskOf(row, "SpellClassMask") },
        ]),
    );
    const miscBySpell = new Map(tables.SpellMisc.map((row) => [integer(row, "SpellID"), row]));
    const durations = new Map(tables.SpellDuration.map((row) => [integer(row, "ID"), row]));
    const durationOf = (spellID: number) => {
        const misc = miscBySpell.get(spellID);
        return misc && durations.get(integer(misc, "DurationIndex"));
    };
    const nameOf = (spellID: number) => {
        const name = names.get(spellID);
        if (!name) {
            throw new Error(`SpellName has no spell ${spellID}`);
        }
        return name;
    };
    const periodicOf = (spellID: number) =>
        (effectsBySpell.get(spellID) ?? []).find((effect) => integer(effect, "EffectAura") === AURA_PERIODIC_DAMAGE);

    // The player's ranks of a spell: the spells of its name a player learns (a
    // skill line's), in its class set and mask (creatures' spells of the same
    // name have neither).
    const learnable = new Set(tables.SkillLineAbility.map((row) => integer(row, "Spell")));
    const ranksOf = (spellID: number, options: ClassOptions): Ranks => {
        const ranks: Ranks = new Map();
        for (const [rankID, name] of names) {
            const rankOptions = classOptions.get(rankID);
            const periodic = periodicOf(rankID);
            const duration = durationOf(rankID);
            if (
                name !== nameOf(spellID) ||
                !learnable.has(rankID) ||
                !rankOptions ||
                rankOptions.classSet !== options.classSet ||
                !overlaps(rankOptions.mask, options.mask) ||
                !periodic ||
                !duration
            ) {
                continue;
            }
            ranks.set(rankID, [float(periodic, "EffectBasePointsF"), integer(duration, "Duration") / 1000]);
        }
        return ranks;
    };

    const spells: Spell[] = followed.map((spellID) => {
        const effects = effectsBySpell.get(spellID) ?? [];
        const periodic = periodicOf(spellID);
        if (!periodic) {
            throw new Error(`Spell ${spellID} (${names.get(spellID)}) has no periodic damage aura`);
        }
        const options = classOptions.get(spellID);
        if (!options) {
            throw new Error(`Spell ${spellID} has no SpellClassOptions: talents can't name it`);
        }
        const misc = miscBySpell.get(spellID);
        if (!misc) {
            throw new Error(`Spell ${spellID} has no SpellMisc`);
        }
        if (float(misc, "Speed") > 0) {
            throw new Error(`Spell ${spellID} (${nameOf(spellID)}) is a projectile: it lands after the cast`);
        }
        const comboPoints = comboPointsOf(effects, durationOf(spellID), costsOf(spellID));
        return {
            spellID,
            key: keyOf(nameOf(spellID)),
            tick: integer(periodic, "EffectAuraPeriod") / 1000,
            school: schoolOf(integer(misc, "SchoolMask")),
            spellPower: float(periodic, "EffectBonusCoefficient"),
            comboPoints,
            // A finishing move's damage depends on the points spent, in a formula
            // the data doesn't hold: it is read from its description instead.
            ranks: comboPoints === "spend" ? undefined : ranksOf(spellID, options),
        };
    });
    // Spell keys named by a class set and mask.
    const namedIn = (list: { spellID: number; key: string }[], classSet: number, mask: number[]) =>
        list
            .filter((spell) => {
                const options = classOptions.get(spell.spellID)!;
                return options.classSet === classSet && overlaps(options.mask, mask);
            })
            .map((spell) => spell.key);
    const named = (classSet: number, mask: number[]) => namedIn(spells, classSet, mask);

    const marks: Mark[] = marked.map((spellID) => {
        const duration = durationOf(spellID);
        if (!duration || integer(duration, "Duration") <= 0) {
            throw new Error(`Mark ${spellID} (${nameOf(spellID)}) has no duration`);
        }
        const comboPoints = comboPointsOf(effectsBySpell.get(spellID) ?? [], duration, costsOf(spellID));
        if (comboPoints !== "spend") {
            throw new Error(`Mark ${spellID} (${nameOf(spellID)}) isn't a finishing move: its description can't be read`);
        }
        if (!classOptions.get(spellID)) {
            throw new Error(`Mark ${spellID} has no SpellClassOptions: its class's strikes can't be found`);
        }
        return {
            spellID,
            key: keyOf(nameOf(spellID)),
            duration: integer(duration, "Duration") / 1000,
            comboPoints,
        };
    });

    // The direct damage spells the player of a mark's class learns (strikes):
    // weapon strikes and spells dealing damage on the spot, cast on the target
    // (no projectiles: they land, and miss, after the cast).
    const descriptions = new Map(tables.Spell.map((row) => [integer(row, "ID"), row.Description_lang ?? ""]));
    const directOf = (spellID: number) => {
        const effects = effectsBySpell.get(spellID) ?? [];
        const of = (...types: number[]) => effects.filter((effect) => types.includes(integer(effect, "Effect")));
        const flatEffects = of(
            EFFECT_NORMALIZED_WEAPON_DAMAGE,
            EFFECT_WEAPON_DAMAGE,
            EFFECT_WEAPON_DAMAGE_NOSCHOOL,
            EFFECT_SCHOOL_DAMAGE,
        );
        const percentEffect = of(EFFECT_WEAPON_PERCENT_DAMAGE)[0];
        const weapon =
            percentEffect !== undefined ||
            of(EFFECT_NORMALIZED_WEAPON_DAMAGE, EFFECT_WEAPON_DAMAGE, EFFECT_WEAPON_DAMAGE_NOSCHOOL).length > 0;
        if (!weapon && flatEffects.length === 0) {
            return undefined;
        }
        const misc = miscBySpell.get(spellID)!;
        if (weapon && (integer(misc, "Attributes_0") & ATTRIBUTE_RANGED) !== 0) {
            return undefined;
        }
        const dagger = descriptions.get(spellID)?.match(DAGGER_PERCENT);
        const daggerEffect = dagger && effects.find((effect) => integer(effect, "EffectIndex") === Number(dagger[1]) - 1);
        if (dagger && !daggerEffect) {
            throw new Error(`Spell ${spellID} (${nameOf(spellID)}) names a dagger effect it doesn't have`);
        }
        const hand: Strike["hand"] = !weapon
            ? undefined
            : (integer(misc, "Attributes_3") & ATTRIBUTE3_OFF_HAND) !== 0
              ? "off"
              : "main";
        return {
            hand,
            normalized: of(EFFECT_NORMALIZED_WEAPON_DAMAGE).length > 0,
            rank: [
                flatEffects.reduce((sum, effect) => sum + float(effect, "EffectBasePointsF"), 0),
                percentEffect ? float(percentEffect, "EffectBasePointsF") / 100 : 1,
                daggerEffect ? float(daggerEffect, "EffectBasePointsF") / 100 : undefined,
            ] as [number, number, number | undefined],
        };
    };
    const markClassSets = new Set(marks.map((mark) => classOptions.get(mark.spellID)!.classSet));
    const followedNames = new Set([...followed, ...marked].map(nameOf));
    const strikesByName = new Map<string, Strike>();
    for (const rankID of [...learnable].sort((a, b) => a - b)) {
        const options = classOptions.get(rankID);
        const misc = miscBySpell.get(rankID);
        const name = names.get(rankID);
        if (
            !options ||
            !markClassSets.has(options.classSet) ||
            !misc ||
            !name ||
            followedNames.has(name) ||
            (integer(misc, "Attributes_0") & ATTRIBUTE_PASSIVE) !== 0 ||
            float(misc, "Speed") > 0
        ) {
            continue;
        }
        const direct = directOf(rankID);
        if (!direct) {
            continue;
        }
        let strike = strikesByName.get(name);
        if (!strike) {
            const comboPoints = comboPointsOf(effectsBySpell.get(rankID) ?? [], durationOf(rankID), costsOf(rankID));
            strike = {
                spellID: rankID,
                key: keyOf(name),
                hand: direct.hand,
                normalized: direct.normalized,
                comboPoints,
                // A finishing move's damage depends on the points spent: it is read
                // from its description instead.
                ranks: comboPoints === "spend" ? undefined : new Map(),
            };
            strikesByName.set(name, strike);
        }
        strike.ranks?.set(rankID, direct.rank);
    }
    const strikes = [...strikesByName.values()];

    // Passive talents' modifiers of the followed spells: percent of periodic
    // damage, and flat duration (milliseconds, turned to seconds), and of the
    // strikes: percent of damage. Active talents (Arcane Power) only count while
    // their buff lasts: left out.
    const curves = groupBy(tables.CurvePoint, "CurveID");
    const curveByEffect = new Map(
        tables.TraitDefinitionEffectPoints.map((row) => [
            `${row.TraitDefinitionID}:${row.EffectIndex}`,
            integer(row, "CurveID"),
        ]),
    );
    const maxRanks = new Map(
        tables.TraitNodeEntry.map((row) => [integer(row, "TraitDefinitionID"), integer(row, "MaxRanks")]),
    );
    const talents: Talents = new Map();
    const durationTalents: Talents = new Map();
    const strikeTalents: Talents = new Map();
    for (const definition of tables.TraitDefinition) {
        const spellID = integer(definition, "SpellID");
        const ranks = maxRanks.get(integer(definition, "ID"));
        const options = classOptions.get(spellID);
        const misc = miscBySpell.get(spellID);
        if (!ranks || !options || !misc || (integer(misc, "Attributes_0") & ATTRIBUTE_PASSIVE) === 0) {
            continue;
        }
        for (const effect of effectsBySpell.get(spellID) ?? []) {
            const aura = integer(effect, "EffectAura");
            const modifier = integer(effect, "EffectMiscValue_0");
            let target: Talents;
            let scale: number;
            let list: { spellID: number; key: string }[] = spells;
            if (aura === AURA_ADD_PCT_MODIFIER && modifier === SPELLMOD_DOT) {
                target = talents;
                scale = 1 / 100;
            } else if (aura === AURA_ADD_FLAT_MODIFIER && modifier === SPELLMOD_DURATION) {
                target = durationTalents;
                scale = 1 / 1000;
            } else if (aura === AURA_ADD_PCT_MODIFIER && modifier === SPELLMOD_DAMAGE) {
                target = strikeTalents;
                scale = 1 / 100;
                list = strikes;
            } else {
                continue;
            }
            const keys = namedIn(list, options.classSet, maskOf(effect, "EffectSpellClassMask"));
            if (keys.length === 0) {
                continue;
            }
            const curveID = curveByEffect.get(`${definition.ID}:${effect.EffectIndex}`);
            const points = curveID ? (curves.get(curveID) ?? []) : [];
            const byRank = Array.from({ length: ranks }, (_, index) => {
                const point = points.find((row) => integer(row, "Pos_0") === index + 1);
                if (curveID && !point) {
                    throw new Error(`Curve ${curveID} of talent ${spellID} has no point for rank ${index + 1}`);
                }
                return (point ? float(point, "Pos_1") : float(effect, "EffectBasePointsF")) * scale;
            });
            const bySpell = target.get(spellID) ?? new Map<string, number[]>();
            for (const key of keys) {
                bySpell.set(key, byRank);
            }
            target.set(spellID, bySpell);
        }
    }

    // Debuffs on the target raising the damage it takes from the caster's spells.
    const amplifiers: Amplifier[] = [];
    for (const [spellID, effects] of effectsBySpell) {
        const options = classOptions.get(spellID);
        const effect = effects.find(
            (candidate) =>
                integer(candidate, "Effect") === EFFECT_APPLY_AURA &&
                integer(candidate, "EffectAura") === AURA_MOD_DAMAGE_FROM_CASTER &&
                integer(candidate, "ImplicitTarget_0") === TARGET_UNIT_TARGET_ENEMY,
        );
        if (!options || !effect) {
            continue;
        }
        const amplifies = named(options.classSet, maskOf(effect, "EffectSpellClassMask"));
        const duration = durationOf(spellID);
        const misc = miscBySpell.get(spellID);
        // A debuff cast on the target lasts a while; permanent ones (negative
        // duration) are passive effects, not something the player casts. A
        // projectile's (Haunt) lands, or misses, after the cast: left out.
        if (
            amplifies.length === 0 ||
            !duration ||
            integer(duration, "Duration") <= 0 ||
            !misc ||
            float(misc, "Speed") > 0
        ) {
            continue;
        }
        amplifiers.push({
            spellID,
            key: keyOf(nameOf(spellID)),
            bonus: float(effect, "EffectBasePointsF") / 100,
            duration: integer(duration, "Duration") / 1000,
            amplifies,
            comboPoints: comboPointsOf(effects, duration, costsOf(spellID)),
        });
    }
    amplifiers.sort((a, b) => a.spellID - b.spellID);
    return { spells, talents, durationTalents, amplifiers, marks, strikes, strikeTalents };
}

export type Armor = {
    // NPC class ID -> base armor at each level from 1.
    byClass: Map<number, number[]>;
    // NPC ID -> armor multiplier, where it isn't 1.
    multipliers: Map<number, number>;
};

// Creatures' armor in CMaNGOS: its class and level's base armor times its own
// multiplier (Creature::SelectLevel).
export function collectArmor(stats: Row[], creatures: Row[]): Armor {
    const byClass = new Map<number, number[]>();
    const sorted = [...stats].sort((a, b) => integer(a, "Level") - integer(b, "Level"));
    for (const row of sorted) {
        const classID = integer(row, "Class");
        const levels = byClass.get(classID) ?? [];
        if (integer(row, "Level") !== levels.length + 1) {
            throw new Error(`class ${classID}: no base armor at level ${levels.length + 1}`);
        }
        levels.push(integer(row, "BaseArmor"));
        byClass.set(classID, levels);
    }
    if (!byClass.has(1)) {
        throw new Error("no warrior base armor, the fallback");
    }
    const multipliers = new Map<number, number>();
    for (const creature of creatures) {
        const multiplier = float(creature, "ArmorMultiplier");
        if (multiplier < 0) {
            throw new Error(`creature ${creature.Entry}: fixed armor, not handled`);
        }
        if (multiplier !== 1) {
            multipliers.set(integer(creature, "Entry"), multiplier);
        }
    }
    return { byClass, multipliers };
}

// DB2 floats are single precision (0.2 reads 0.20000000298): 6 significant digits.
function number(value: number): string {
    return String(Number(value.toPrecision(6)));
}

function lua(value: string | number): string {
    return typeof value === "string" ? `"${value}"` : number(value);
}

// `{ key = value, ... }`, leaving out the undefined values.
function record(fields: [string, string | undefined][]): string {
    const entries = fields.filter(([, value]) => value !== undefined).map(([key, value]) => `${key} = ${value}`);
    return `{ ${entries.join(", ")} }`;
}

function talentsLua(talents: Talents): string[] {
    return [...talents.keys()]
        .sort((a, b) => a - b)
        .map((spellID) => {
            const bySpell = talents.get(spellID)!;
            const entries = [...bySpell.keys()]
                .sort()
                .map((key) => `${key} = { ${bySpell.get(key)!.map(number).join(", ")} }`);
            return `        [${spellID}] = { ${entries.join(", ")} },`;
        });
}

export function renderLua(collected: ReturnType<typeof collect>, armor: Armor, build: string): string {
    const { spells, talents, durationTalents, amplifiers, marks, strikes, strikeTalents } = collected;
    const set = (keys: string[]) => `{ ${keys.map((key) => `${key} = true`).join(", ")} }`;
    const strikeRanksLua = (ranks: StrikeRanks | undefined) => {
        if (!ranks) {
            return undefined;
        }
        const entries = [...ranks.keys()].sort((a, b) => a - b).map((rankID) => {
            const [flat, percent, dagger] = ranks.get(rankID)!;
            const values = dagger === undefined ? [flat, percent] : [flat, percent, dagger];
            return `[${rankID}] = { ${values.map(number).join(", ")} }`;
        });
        return `{ ${entries.join(", ")} }`;
    };
    const ranksLua = (ranks: Ranks | undefined) => {
        if (!ranks) {
            return undefined;
        }
        const entries = [...ranks.keys()]
            .sort((a, b) => a - b)
            .map((rankID) => `[${rankID}] = { ${ranks.get(rankID)!.map(number).join(", ")} }`);
        return `{ ${entries.join(", ")} }`;
    };
    const lines = [
        `-- Generated by tools/dots.ts from Forever's DB2 tables (build ${build}) and`,
        `-- CMaNGOS's Classic database (${CMANGOS_COMMIT.slice(0, 7)}). Do not edit.`,
        "-- The damage over time spells followed and what changes their damage, as the",
        "-- client's data gives them (measured.lua holds what the server adds, and what",
        "-- was measured to differ), and creatures' armor.",
        "",
        "local _, ns = ...",
        "",
        'local DoTs = ns:GetFeature("combat", "dots")',
        "",
        "DoTs.Data = {",
        "    -- Spell ID of one rank (ranks share the name) -> { key, tick (seconds",
        "    -- between ticks), school (GetSpellBonusDamage's index), spellPower (its",
        '    -- share added to each tick), comboPoints ("spend": a finishing move,',
        '    -- "award", or nil), ranks (rank spell ID -> { damage per tick before talents',
        "    -- and bonuses, duration }; nil for a finishing move, read from its",
        "    -- description) }.",
        "    spells = {",
        ...spells.map(
            (spell) =>
                `        [${spell.spellID}] = ${record([
                    ["key", lua(spell.key)],
                    ["tick", number(spell.tick)],
                    ["school", String(spell.school)],
                    ["spellPower", number(spell.spellPower)],
                    ["comboPoints", spell.comboPoints && lua(spell.comboPoints)],
                    ["ranks", ranksLua(spell.ranks)],
                ])},`,
        ),
        "    },",
        "    -- Passive talent spell ID -> spell key -> its periodic damage bonus at each rank.",
        "    talents = {",
        ...talentsLua(talents),
        "    },",
        "    -- Passive talent spell ID -> spell key -> the seconds it adds at each rank.",
        "    durations = {",
        ...talentsLua(durationTalents),
        "    },",
        "    -- Spell ID -> the debuff it puts on its target, raising the damage the target",
        "    -- takes from the caster's spells: { key, bonus, duration, amplifies, comboPoints }.",
        "    amplifiers = {",
        ...amplifiers.map(
            (amplifier) =>
                `        [${amplifier.spellID}] = ${record([
                    ["key", lua(amplifier.key)],
                    ["bonus", number(amplifier.bonus)],
                    ["duration", number(amplifier.duration)],
                    ["amplifies", set(amplifier.amplifies)],
                    ["comboPoints", amplifier.comboPoints && lua(amplifier.comboPoints)],
                ])},`,
        ),
        "    },",
        "    -- Spell ID of one rank -> the mark it puts on its target, storing part of the",
        "    -- damage the player deals it, dealt at once after `duration` seconds:",
        "    -- { key, duration, comboPoints } (a finishing move: what it stores and its",
        "    -- cap are read from its description).",
        "    marks = {",
        ...marks.map(
            (mark) =>
                `        [${mark.spellID}] = ${record([
                    ["key", lua(mark.key)],
                    ["duration", number(mark.duration)],
                    ["comboPoints", mark.comboPoints && lua(mark.comboPoints)],
                ])},`,
        ),
        "    },",
        "    -- Spell ID of one rank -> a direct damage spell of a mark's class, which the",
        '    -- marks store: { key, hand ("main" or "off": a weapon strike, nil: a spell),',
        "    -- normalized (its weapon damage takes attack power at the weapon type's",
        '    -- normalized speed), comboPoints, ranks (rank spell ID -> { flat damage,',
        "    -- weapon damage percentage, its percentage with a dagger in the main hand };",
        "    -- nil for a finishing move, read from its description) }.",
        "    strikes = {",
        ...strikes.map(
            (strike) =>
                `        [${strike.spellID}] = ${record([
                    ["key", lua(strike.key)],
                    ["hand", strike.hand && lua(strike.hand)],
                    ["normalized", String(strike.normalized)],
                    ["comboPoints", strike.comboPoints && lua(strike.comboPoints)],
                    ["ranks", strikeRanksLua(strike.ranks)],
                ])},`,
        ),
        "    },",
        "    -- Passive talent spell ID -> strike key -> its damage bonus at each rank.",
        "    strikeTalents = {",
        ...talentsLua(strikeTalents),
        "    },",
        "    -- NPC class ID (UnitClass's third value) -> a creature's base armor at each",
        "    -- level from 1 (CMaNGOS).",
        "    armor = {",
        ...[...armor.byClass.keys()]
            .sort((a, b) => a - b)
            .map((classID) => `        [${classID}] = { ${armor.byClass.get(classID)!.join(", ")} },`),
        "    },",
        "    -- NPC ID -> its armor multiplier, where it isn't 1 (CMaNGOS).",
        "    armorMultipliers = {",
        ...[...armor.multipliers.keys()]
            .sort((a, b) => a - b)
            .map((npcID) => `        [${npcID}] = ${number(armor.multipliers.get(npcID)!)},`),
        "    },",
        "}",
        "",
    ];
    return lines.join("\n");
}

// Writes a generated Lua file in StyLua's layout, so `bun run lint` passes on it.
async function writeLua(file: string, contents: string) {
    await writeFile(file, contents);
    const stylua = Bun.spawnSync(["stylua", file], { stdout: "inherit", stderr: "inherit" });
    if (stylua.exitCode !== 0) {
        throw new Error(`stylua failed on ${file}`);
    }
}

if (import.meta.main) {
    const args = Bun.argv.slice(2);
    const buildIndex = args.indexOf("--build");
    const build = buildIndex >= 0 ? args[buildIndex + 1] : await latestBuild();
    const refresh = args.includes("--refresh");
    const repoRoot = path.resolve(import.meta.dir, "..");

    const tables = {} as Tables;
    for (const name of TABLE_NAMES) {
        tables[name] = parseCsv(await table(path.join(repoRoot, CACHE), name, build, refresh));
    }
    const collected = collect(tables, FOLLOWED, MARKS);
    const sql = await dump(path.join(repoRoot, CACHE), refresh);
    const armor = collectArmor(
        sqlTable(sql, "creature_template_classlevelstats"),
        sqlTable(sql, "creature_template"),
    );
    await writeLua(path.join(repoRoot, OUTPUT), renderLua(collected, armor, build));
    console.log(
        `${OUTPUT}: ${collected.spells.length} spells, ${collected.talents.size} talents, ${collected.durationTalents.size} duration talents, ${collected.amplifiers.length} amplifiers, ${collected.marks.length} marks, ${collected.strikes.length} strikes, ${collected.strikeTalents.size} strike talents, ${armor.byClass.size} NPC classes' armor, ${armor.multipliers.size} armor multipliers (build ${build}, CMaNGOS ${CMANGOS_COMMIT.slice(0, 7)})`,
    );
}
