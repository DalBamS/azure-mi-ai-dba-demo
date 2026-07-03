import { z } from "zod";

/**
 * Lifecycle buckets mirror the repo layout: demos/{runtime,pre-prod,cicd}.
 */
export const Lifecycle = z.enum(["runtime", "pre-prod", "cicd"]);
export type Lifecycle = z.infer<typeof Lifecycle>;

/**
 * How a step is executed. `md` steps are human/manual guides (not run by the
 * runner); the rest map to an external interpreter in live mode.
 */
export const StepKind = z.enum(["sql", "ps1", "py", "md"]);
export type StepKind = z.infer<typeof StepKind>;

export const StepSchema = z.object({
  /** 1-based order derived from the NN_ filename prefix (fallback: list order). */
  order: z.number().int().nonnegative(),
  /** Stable id — filename without extension, e.g. "01_reproduce". */
  id: z.string().min(1),
  /** File name relative to the demo folder. */
  file: z.string().min(1),
  /** Repo-relative POSIX path, e.g. "demos/runtime/A-slow-query-index/01_reproduce.sql". */
  path: z.string().min(1),
  kind: StepKind,
  /** Human label derived from the filename ("01_reproduce" -> "reproduce"). */
  title: z.string().min(1),
  /**
   * Destructive steps mutate schema/data (remediate, rollback, apply, cleanup,
   * inject). The UI must require explicit confirmation before running these.
   */
  destructive: z.boolean(),
  /** True when this step is documentation-only (kind === "md"). */
  manual: z.boolean(),
});
export type Step = z.infer<typeof StepSchema>;

export const DemoSchema = z.object({
  /** Single-letter demo id, e.g. "A", "F", "K". */
  id: z.string().min(1),
  /** Folder slug, e.g. "A-slow-query-index". */
  slug: z.string().min(1),
  lifecycle: Lifecycle,
  /** Title parsed from the demo README H1 (falls back to the slug). */
  title: z.string().min(1),
  /** Presenter-facing one-line explanation of what the demo shows. */
  summary: z.string().min(1).optional(),
  /** Presenter-facing explanation of why AI improves this workflow. */
  whyAi: z.string().min(1).optional(),
  /** Repo-relative POSIX path to the demo folder. */
  path: z.string().min(1),
  /** Repo-relative POSIX path to the demo README, if present. */
  readme: z.string().nullable(),
  steps: z.array(StepSchema),
});
export type Demo = z.infer<typeof DemoSchema>;

export const ManifestSchema = z.object({
  version: z.literal(1),
  generatedAt: z.string(),
  /** Repo-relative root the paths are anchored to (always "."). */
  root: z.literal("."),
  demos: z.array(DemoSchema),
});
export type Manifest = z.infer<typeof ManifestSchema>;
