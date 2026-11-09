import { readFile } from "node:fs/promises";
import path from "node:path";
import { runGitCliff, type Options } from "git-cliff";

const tocFile = "ForeverEnhanced.toc";
const changelogFile = "CHANGELOG.md";
const cliffConfigFile = "cliff.toml";

export async function readTocVersion(repoRoot: string): Promise<string> {
    const tocPath = path.join(repoRoot, tocFile);
    const toc = await readFile(tocPath, "utf8");
    const match = toc.match(/^\s*##\s*Version:\s*(.+?)\s*$/m);
    if (!match) {
        throw new Error(`Could not find ## Version in ${tocPath}`);
    }

    return match[1].trim();
}

export async function generateChangelog(repoRoot: string, version: string): Promise<void> {
    const options: Options = {
        config: cliffConfigFile,
        output: changelogFile,
        tag: `v${version}`,
    };

    await runGitCliff(options, {
        cwd: repoRoot,
        stdio: "inherit",
    });
}

if (import.meta.main) {
    const repoRoot = path.resolve(import.meta.dir, "..");
    const version = await readTocVersion(repoRoot);
    await generateChangelog(repoRoot, version);
}
