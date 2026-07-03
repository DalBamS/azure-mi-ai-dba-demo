import type { Demo, Step } from "../manifest/types.js";

export type RunMode = "mock" | "live";

export interface RunContext {
  mode: RunMode;
  /** Optional database override; defaults to env SQLMI_DATABASE / "gamedb". */
  database?: string;
}

export interface RunResult {
  demoId: string;
  stepId: string;
  kind: Step["kind"];
  mode: RunMode;
  /** True when the output was simulated and nothing external was executed. */
  mocked: boolean;
  /** True for documentation-only (md) steps that are not executed. */
  manual: boolean;
  /** True when the step was intentionally not executed (e.g. manual, or live disabled). */
  skipped: boolean;
  exitCode: number;
  durationMs: number;
  startedAt: string;
  /** Human-readable command, with any secrets redacted. Never includes credentials. */
  command: string;
  stdout: string;
  stderr: string;
}

export interface Runner {
  readonly mode: RunMode;
  run(demo: Demo, step: Step, ctx?: Partial<RunContext>): Promise<RunResult>;
}

/**
 * Resolve the effective run mode from the environment. Live mode is opt-in and
 * requires ALL of: COCKPIT_MODE=live, COCKPIT_ALLOW_LIVE=1, and SQLMI_SERVER set.
 * Anything short of that falls back to the safe default: mock.
 */
export function resolveMode(env: NodeJS.ProcessEnv = process.env): RunMode {
  const requested = (env.COCKPIT_MODE ?? "mock").toLowerCase();
  if (requested === "live" && env.COCKPIT_ALLOW_LIVE === "1" && env.SQLMI_SERVER) {
    return "live";
  }
  return "mock";
}
