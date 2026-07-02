import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { findRepoRoot, toRepoRelative } from "./paths.js";
import {
  DemoSchema,
  ManifestSchema,
  StepSchema,
  type Demo,
  type Lifecycle,
  type Manifest,
  type Step,
  type StepKind,
} from "./types.js";

const LIFECYCLES: Lifecycle[] = ["runtime", "pre-prod", "cicd"];

const KIND_BY_EXT: Record<string, StepKind> = {
  ".sql": "sql",
  ".ps1": "ps1",
  ".py": "py",
  ".md": "md",
};

// Step ids whose execution mutates schema/data. The UI gates these behind an
// explicit confirmation, and mock mode still simulates them without side effects.
const DESTRUCTIVE = /(rollback|remediate|apply|cleanup|inject|reset|\.down$)/i;

function kindForFile(file: string): StepKind | null {
  return KIND_BY_EXT[path.extname(file).toLowerCase()] ?? null;
}

/** "01_reproduce" -> order 1; "generate_ai_report" -> order 0 (unnumbered). */
function orderForId(id: string): number {
  const m = /^(\d+)/.exec(id);
  return m ? Number.parseInt(m[1]!, 10) : 0;
}

/** "01_reproduce" -> "reproduce"; "generate_ai_report" -> "generate ai report". */
function titleForId(id: string): string {
  return id
    .replace(/^\d+[_-]?/, "")
    .replace(/[_-]+/g, " ")
    .trim() || id;
}

function readReadmeTitle(readmeAbs: string, fallback: string): string {
  try {
    const text = fs.readFileSync(readmeAbs, "utf8");
    for (const raw of text.split(/\r?\n/)) {
      const line = raw.trim();
      if (line.startsWith("# ")) return line.slice(2).trim() || fallback;
    }
  } catch {
    /* fall through */
  }
  return fallback;
}

function buildSteps(repoRoot: string, demoAbs: string): Step[] {
  const entries = fs
    .readdirSync(demoAbs, { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.toLowerCase() !== "readme.md");

  const steps: Step[] = [];
  for (const entry of entries) {
    const kind = kindForFile(entry.name);
    if (!kind) continue;
    const id = entry.name.replace(/\.[^.]+$/, "");
    const abs = path.join(demoAbs, entry.name);
    steps.push(
      StepSchema.parse({
        order: orderForId(id),
        id,
        file: entry.name,
        path: toRepoRelative(repoRoot, abs),
        kind,
        title: titleForId(id),
        destructive: DESTRUCTIVE.test(id),
        manual: kind === "md",
      } satisfies Step),
    );
  }

  steps.sort((a, b) => a.order - b.order || a.id.localeCompare(b.id));
  return steps;
}

function buildDemo(
  repoRoot: string,
  lifecycle: Lifecycle,
  slug: string,
): Demo | null {
  const demoAbs = path.join(repoRoot, "demos", lifecycle, slug);
  if (!fs.statSync(demoAbs).isDirectory()) return null;

  const idMatch = /^([A-Za-z0-9]+)/.exec(slug);
  const id = (idMatch?.[1] ?? slug).toUpperCase();

  const readmeAbs = path.join(demoAbs, "README.md");
  const hasReadme = fs.existsSync(readmeAbs);
  const title = hasReadme ? readReadmeTitle(readmeAbs, slug) : slug;

  return DemoSchema.parse({
    id,
    slug,
    lifecycle,
    title,
    path: toRepoRelative(repoRoot, demoAbs),
    readme: hasReadme ? toRepoRelative(repoRoot, readmeAbs) : null,
    steps: buildSteps(repoRoot, demoAbs),
  } satisfies Demo);
}

/** Scan demos/** and produce a validated manifest object. */
export function buildManifest(repoRoot = findRepoRoot()): Manifest {
  const demos: Demo[] = [];

  for (const lifecycle of LIFECYCLES) {
    const lifecycleAbs = path.join(repoRoot, "demos", lifecycle);
    if (!fs.existsSync(lifecycleAbs)) continue;
    const slugs = fs
      .readdirSync(lifecycleAbs, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort((a, b) => a.localeCompare(b));

    for (const slug of slugs) {
      const demo = buildDemo(repoRoot, lifecycle, slug);
      if (demo) demos.push(demo);
    }
  }

  return ManifestSchema.parse({
    version: 1,
    generatedAt: new Date().toISOString(),
    root: ".",
    demos,
  } satisfies Manifest);
}

/** Repo-relative location of the generated manifest. */
export const MANIFEST_RELATIVE = "cockpit/manifest.json";

export function manifestAbsPath(repoRoot = findRepoRoot()): string {
  return path.join(repoRoot, MANIFEST_RELATIVE);
}

/** CLI entry: regenerate cockpit/manifest.json. */
function main(): void {
  const repoRoot = findRepoRoot();
  const manifest = buildManifest(repoRoot);
  const out = manifestAbsPath(repoRoot);
  fs.writeFileSync(out, JSON.stringify(manifest, null, 2) + "\n", "utf8");
  const stepCount = manifest.demos.reduce((n, d) => n + d.steps.length, 0);
  console.log(
    `Wrote ${toRepoRelative(repoRoot, out)} — ${manifest.demos.length} demos, ${stepCount} steps.`,
  );
}

// Run main only when invoked directly (not when imported).
const invoked = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (invoked && invoked === path.resolve(fileURLToPath(import.meta.url))) main();
