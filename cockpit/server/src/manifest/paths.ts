import { fileURLToPath } from "node:url";
import path from "node:path";
import fs from "node:fs";

/**
 * Resolve the repository root by walking up from this file until we find a
 * directory that contains both a `demos` folder and the repo README. This keeps
 * the generator correct whether it runs from src (tsx) or dist (node).
 */
export function findRepoRoot(startDir?: string): string {
  let dir = startDir ?? path.dirname(fileURLToPath(import.meta.url));
  // Walk up a bounded number of levels to avoid an infinite loop.
  for (let i = 0; i < 12; i++) {
    const hasDemos = fs.existsSync(path.join(dir, "demos"));
    const hasReadme = fs.existsSync(path.join(dir, "README.md"));
    if (hasDemos && hasReadme) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error(
    "Could not locate repo root (a directory containing both 'demos' and 'README.md').",
  );
}

/** Convert an absolute path to a repo-relative POSIX path. */
export function toRepoRelative(repoRoot: string, absPath: string): string {
  return path.relative(repoRoot, absPath).split(path.sep).join("/");
}
