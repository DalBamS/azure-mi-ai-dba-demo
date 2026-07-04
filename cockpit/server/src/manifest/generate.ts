import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DEMO_ANNOTATIONS } from "./annotations.js";
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
const DESTRUCTIVE =
  /(rollback|remediate|apply|cleanup|inject|reset|drop|risky|alter|\.down(?:\.sql)?$)/i;

const ANALYSIS_ONLY = new Set<string>([
  "demos/cicd/J-pr-risk-review/sample-migrations/risky_alter_inventory.sql",
  "demos/cicd/J-pr-risk-review/sample-migrations/risky_drop_column.sql",
]);

type InjSpec = {
  title: string;
  path?: string;
  concurrentPaths?: string[];
  resetPath: string;
  resetTitle: string;
};

const INJECTIONS: Record<string, InjSpec> = {
  A: {
    title: "이슈 주입 — 누락 인덱스 DROP",
    path: "issue-injection/01_missing_index.sql",
    resetPath: "issue-injection/01_missing_index.rollback.sql",
    resetTitle: "주입 원복 — 인덱스 재생성",
  },
  C: {
    title: "이슈 주입 — plan regression",
    path: "issue-injection/03_plan_regression.sql",
    resetPath: "issue-injection/03_plan_regression.rollback.sql",
    resetTitle: "주입 원복 — proc/plan 복구",
  },
  M: {
    title: "이슈 주입 — 취약 proc 생성",
    path: "issue-injection/06_sql_injection.sql",
    resetPath: "issue-injection/06_sql_injection.rollback.sql",
    resetTitle: "주입 원복 — 취약 proc 제거",
  },
  B: {
    title: "이슈 주입 — deadlock 2세션 동시 실행",
    concurrentPaths: [
      "issue-injection/02_blocking_deadlock.sessionA.sql",
      "issue-injection/02_blocking_deadlock.sessionB.sql",
    ],
    resetPath: "issue-injection/02_blocking_deadlock.rollback.sql",
    resetTitle: "주입 원복 — deadlock 정리",
  },
};

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

interface ReadmeMatcher {
  index: number;
  matches: (step: Step) => boolean;
}

function globPatternToRegex(pattern: string): RegExp {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
  return new RegExp(`^${escaped}$`, "i");
}

function buildReadmeMatchers(readmeAbs: string | null): ReadmeMatcher[] {
  if (!readmeAbs || !fs.existsSync(readmeAbs)) return [];

  const text = fs.readFileSync(readmeAbs, "utf8");
  const matches: ReadmeMatcher[] = [];
  let match: RegExpExecArray | null;
  const tokenPattern = /`([^`]+)`/g;
  let wildcardContext = "";

  while ((match = tokenPattern.exec(text))) {
    const raw = match[1]!.trim();
    if (!raw || /\s/.test(raw)) continue;
    let token = raw.replace(/\\/g, "/").replace(/^\.\//, "");
    if (token.startsWith("../") || token.startsWith("/") || token.includes("<")) continue;
    if (!/[/*.]|\.sql$|\.md$|\.py$|\.ps1$/i.test(token)) continue;

    const index = matches.length;
    if (token.includes("*")) {
      if (!token.includes("/")) {
        if (!wildcardContext) continue;
        token = `${wildcardContext}${token}`;
      }
      wildcardContext = token.slice(0, token.indexOf("*"));
      const regex = globPatternToRegex(token);
      matches.push({
        index,
        matches: (step) => regex.test(step.file) || regex.test(path.posix.basename(step.file)),
      });
      continue;
    }
    wildcardContext = "";

    if (token.endsWith("/") || path.posix.extname(token) === "") {
      const prefix = token.endsWith("/") ? token : `${token}/`;
      matches.push({ index, matches: (step) => step.file.startsWith(prefix) });
      continue;
    }

    matches.push({
      index,
      matches: (step) => step.file === token || path.posix.basename(step.file) === token,
    });
  }

  return matches;
}

function readmeOrder(step: Step, matchers: ReadmeMatcher[]): number {
  return matchers.find((m) => m.matches(step))?.index ?? Number.POSITIVE_INFINITY;
}

function upDownPriority(file: string): number {
  if (/\.up\.sql$/i.test(file)) return 0;
  if (/\.down\.sql$/i.test(file)) return 1;
  return 2;
}

function compareWithinFolder(a: Step, b: Step): number {
  const aOrder = a.order > 0 ? a.order : Number.MAX_SAFE_INTEGER;
  const bOrder = b.order > 0 ? b.order : Number.MAX_SAFE_INTEGER;
  return (
    aOrder - bOrder ||
    upDownPriority(a.file) - upDownPriority(b.file) ||
    a.file.localeCompare(b.file)
  );
}

/**
 * Collect step files for a demo. Top-level numbered files (01_*.sql …) are the
 * primary sequence; some demos (cicd I/J/K) keep runnable assets one or more
 * folders deep, so we recurse and use the demo-relative POSIX path as the step
 * id to keep ids unique and to let the UI group by folder.
 */
function buildSteps(repoRoot: string, demoAbs: string, readmeAbs: string | null): Step[] {
  const steps: Step[] = [];

  const walk = (dirAbs: string): void => {
    for (const entry of fs.readdirSync(dirAbs, { withFileTypes: true })) {
      const abs = path.join(dirAbs, entry.name);
      if (entry.isDirectory()) {
        walk(abs);
        continue;
      }
      if (!entry.isFile()) continue;
      if (entry.name.toLowerCase() === "readme.md") continue;
      const kind = kindForFile(entry.name);
      if (!kind) continue;

      // Demo-relative POSIX path, e.g. "migrations/001_add_x.up.sql".
      const rel = path.relative(demoAbs, abs).split(path.sep).join("/");
      const repoRel = toRepoRelative(repoRoot, abs);
      const id = rel.replace(/\.[^.]+$/, "");
      const leaf = path.basename(entry.name).replace(/\.[^.]+$/, "");

      steps.push(
        StepSchema.parse({
          order: orderForId(leaf),
          id,
          file: rel,
          path: repoRel,
          kind,
          title: titleForId(leaf),
          destructive: DESTRUCTIVE.test(rel),
          manual: kind === "md",
          analysisOnly: ANALYSIS_ONLY.has(repoRel),
          injection: false,
          injectionReset: false,
        } satisfies Step),
      );
    }
  };

  walk(demoAbs);
  const readmeMatchers = buildReadmeMatchers(readmeAbs);

  // Top-level numbered steps remain the main sequence. Nested/no-prefix assets
  // follow the README narrative when available, otherwise group by folder.
  steps.sort((a, b) => {
    const aTopLevel = a.id.includes("/") ? 0 : 1;
    const bTopLevel = b.id.includes("/") ? 0 : 1;
    if (aTopLevel !== bTopLevel) return bTopLevel - aTopLevel;
    if (aTopLevel && bTopLevel) {
      return a.order - b.order || a.id.localeCompare(b.id);
    }

    const aReadme = readmeOrder(a, readmeMatchers);
    const bReadme = readmeOrder(b, readmeMatchers);
    if (aReadme !== bReadme) return aReadme - bReadme;

    const aDir = path.posix.dirname(a.file);
    const bDir = path.posix.dirname(b.file);
    return aDir.localeCompare(bDir) || compareWithinFolder(a, b);
  });
  return steps;
}

function withInjectionSteps(demo: Demo): Step[] {
  const spec = INJECTIONS[demo.id];
  if (!spec) return demo.steps;

  const primaryPath = spec.path ?? spec.concurrentPaths?.[0];
  if (!primaryPath) throw new Error(`Injection for demo ${demo.id} must define a path.`);

  const inject = StepSchema.parse({
    order: 0,
    id: "00_inject",
    file: path.posix.basename(primaryPath),
    path: primaryPath,
    kind: "sql",
    title: spec.title,
    destructive: true,
    manual: false,
    analysisOnly: false,
    injection: true,
    injectionReset: false,
    ...(spec.concurrentPaths ? { concurrentPaths: spec.concurrentPaths } : {}),
  } satisfies Step);

  const reset = StepSchema.parse({
    order: 99,
    id: "99_reset",
    file: path.posix.basename(spec.resetPath),
    path: spec.resetPath,
    kind: "sql",
    title: spec.resetTitle,
    destructive: true,
    manual: false,
    analysisOnly: false,
    injection: false,
    injectionReset: true,
  } satisfies Step);

  return [inject, ...demo.steps, reset].sort((a, b) => a.order - b.order || a.id.localeCompare(b.id));
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
  const annotation = DEMO_ANNOTATIONS[id];

  const demo = DemoSchema.parse({
    id,
    slug,
    lifecycle,
    title,
    ...(annotation ?? {}),
    path: toRepoRelative(repoRoot, demoAbs),
    readme: hasReadme ? toRepoRelative(repoRoot, readmeAbs) : null,
    steps: buildSteps(repoRoot, demoAbs, hasReadme ? readmeAbs : null),
  } satisfies Demo);

  return { ...demo, steps: withInjectionSteps(demo) };
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

function manifestJson(manifest: Manifest): string {
  return (
    JSON.stringify(
      manifest,
      (key, value) =>
        ["analysisOnly", "injection", "injectionReset"].includes(key) && value === false
          ? undefined
          : value,
      2,
    ) + "\n"
  );
}

/** Keep generated manifest diffs reviewable by preserving the committed timestamp. */
export function preserveExistingGeneratedAt(repoRoot: string, manifest: Manifest): Manifest {
  const out = manifestAbsPath(repoRoot);
  if (!fs.existsSync(out)) return manifest;

  try {
    const existing = ManifestSchema.parse(JSON.parse(fs.readFileSync(out, "utf8")));
    return { ...manifest, generatedAt: existing.generatedAt };
  } catch (err) {
    console.warn(
      `[cockpit] ${out} invalid (${(err as Error).message}); writing a fresh generatedAt.`,
    );
  }

  return manifest;
}

/** CLI entry: regenerate cockpit/manifest.json. */
function main(): void {
  const repoRoot = findRepoRoot();
  const manifest = preserveExistingGeneratedAt(repoRoot, buildManifest(repoRoot));
  const out = manifestAbsPath(repoRoot);
  fs.writeFileSync(out, manifestJson(manifest), "utf8");
  const stepCount = manifest.demos.reduce((n, d) => n + d.steps.length, 0);
  console.log(
    `Wrote ${toRepoRelative(repoRoot, out)} — ${manifest.demos.length} demos, ${stepCount} steps.`,
  );
}

// Run main only when invoked directly (not when imported).
const invoked = process.argv[1] ? path.resolve(process.argv[1]) : "";
if (invoked && invoked === path.resolve(fileURLToPath(import.meta.url))) main();
