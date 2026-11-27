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
    // Not `all`: bumpp then refuses to start on a dirty working tree (untracked files included),
    // and commits only the files it updated, so unfinished work never lands in a release commit.
    all: false,
    commit: "chore: release v%s",
    execute: async (operation) => {
        const { options, state } = operation;
        await updateTocVersion(options.cwd, state.newVersion);
        await generateChangelog(options.cwd, state.newVersion);
        const written = [...tocFiles, "CHANGELOG.md"].map((file) => path.join(options.cwd, file));
        operation.update({ updatedFiles: [...state.updatedFiles, ...written] });
    },
    files: ["package.json"],
    noGitCheck: false,
    tag: "v%s",
});
