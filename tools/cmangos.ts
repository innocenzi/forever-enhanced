// CMaNGOS's Classic database (GPL-3.0, github.com/cmangos/classic-db), for what
// the client's data doesn't hold because the server keeps it: creature stats.
// Its values are the emulator's (from the original game where it could tell),
// not Blizzard's: check what is built on them in game.
// The full dump at CMANGOS_COMMIT is downloaded once into tools/.cache.

import path from "node:path";
import type { Row } from "./wago";
import { cached } from "./wago";

export const CMANGOS_COMMIT = "28ef6259c782928b08a8dc9cacf6bc02e64f2b29";
const DUMP = "Full_DB/ClassicDB_1_12_1_z2815.sql.gz";

/** The SQL dump at CMANGOS_COMMIT, kept in `cacheDir/cmangos/`. */
export async function dump(cacheDir: string, refresh: boolean): Promise<string> {
    const url = `https://raw.githubusercontent.com/cmangos/classic-db/${CMANGOS_COMMIT}/${DUMP}`;
    const gzipped = await cached(path.join(cacheDir, "cmangos", `${CMANGOS_COMMIT}.sql.gz`), url, refresh);
    return new TextDecoder().decode(Bun.gunzipSync(new Uint8Array(gzipped)));
}

// One row's values from a `(...)` tuple of an INSERT, from `start` (just past
// its opening parenthesis); returns them and the index past its closing one.
function tuple(body: string, start: number): [string[], number] {
    const values: string[] = [];
    let value = "";
    let quoted = false;
    for (let i = start; i < body.length; i++) {
        const c = body[i];
        if (quoted) {
            if (c === "\\") {
                value += body[++i];
            } else if (c === "'") {
                quoted = false;
            } else {
                value += c;
            }
        } else if (c === "'") {
            quoted = true;
        } else if (c === ",") {
            values.push(value);
            value = "";
        } else if (c === ")") {
            values.push(value);
            return [values, i + 1];
        } else {
            value += c;
        }
    }
    throw new Error("unterminated row");
}

/** A table's rows, by column name (the dump's mysqldump layout). */
export function sqlTable(sql: string, name: string): Row[] {
    const create = sql.indexOf(`CREATE TABLE \`${name}\` (`);
    if (create < 0) {
        throw new Error(`no table ${name} in the dump`);
    }
    const columns: string[] = [];
    for (const line of sql.slice(create, sql.indexOf(") ENGINE", create)).split("\n").slice(1)) {
        const column = line.match(/^ {2}`(\w+)`/);
        if (column) {
            columns.push(column[1]);
        }
    }
    const rows: Row[] = [];
    const prefix = `INSERT INTO \`${name}\` VALUES `;
    for (const line of sql.split("\n")) {
        if (!line.startsWith(prefix)) {
            continue;
        }
        for (let i = prefix.length; i < line.length; ) {
            if (line[i] !== "(") {
                i++;
                continue;
            }
            const [values, next] = tuple(line, i + 1);
            if (values.length !== columns.length) {
                throw new Error(`${name}: ${values.length} values for ${columns.length} columns`);
            }
            rows.push(Object.fromEntries(columns.map((column, index) => [column, values[index]])));
            i = next;
        }
    }
    return rows;
}
