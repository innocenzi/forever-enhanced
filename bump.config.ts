import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { defineConfig } from "bumpp";
import { generateChangelog } from "./tools/changelog";

const tocFiles = ["ForeverEnhanced.toc"];

async function updateTocVersion(repoRoot: string, version: string): Promise<void> {
    for (const tocFile of tocFiles) {
        const tocPath = path.join(repoRoot, tocFile);
        const toc = await readFile(tocPath, "utf8");
        const versionMatch = toc.match(/^(\s*##\s*Version:\s*)(.+?)(\s*)$/m);

        if (!versionMatch) {
            throw new Error(`Could not update ## Version in ${tocPath}`);
        }

        if (versionMatch[2].trim() === version) {
            continue;
        }

        const updatedToc = toc.replace(/^(\s*##\s*Version:\s*).+?(\s*)$/m, `$1${version}$2`);
        await writeFile(tocPath, updatedToc);
    }
}

export default defineConfig({
    all: true,
    commit: "chore: release v%s",
    execute: async ({ options, state }) => {
        await updateTocVersion(options.cwd, state.newVersion);
        await generateChangelog(options.cwd, state.newVersion);
        // `all` commits with `git commit --all`, which skips untracked files.
        execFileSync("git", ["add", "CHANGELOG.md"], { cwd: options.cwd });
    },
    files: ["package.json"],
    noGitCheck: false,
    tag: "v%s",
});
