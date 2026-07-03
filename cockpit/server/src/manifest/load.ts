import fs from "node:fs";
import { buildManifest, manifestAbsPath } from "./generate.js";
import { findRepoRoot } from "./paths.js";
import { ManifestSchema, type Demo, type Manifest } from "./types.js";

/**
 * Load the manifest. Prefers the committed cockpit/manifest.json; if it is
 * missing or fails validation, falls back to scanning demos/** in-memory so the
 * server always has a usable manifest.
 */
export function loadManifest(repoRoot = findRepoRoot()): Manifest {
  const abs = manifestAbsPath(repoRoot);
  if (fs.existsSync(abs)) {
    try {
      const raw = JSON.parse(fs.readFileSync(abs, "utf8"));
      return ManifestSchema.parse(raw);
    } catch (err) {
      console.warn(
        `[cockpit] ${abs} invalid (${(err as Error).message}); rebuilding from demos/**.`,
      );
    }
  }
  return buildManifest(repoRoot);
}

export function findDemo(manifest: Manifest, idOrSlug: string): Demo | undefined {
  const needle = idOrSlug.toLowerCase();
  return manifest.demos.find(
    (d) => d.id.toLowerCase() === needle || d.slug.toLowerCase() === needle,
  );
}
