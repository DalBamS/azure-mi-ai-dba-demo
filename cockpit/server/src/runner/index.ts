import { MockRunner } from "./mock.js";
import { LiveRunner } from "./live.js";
import { resolveMode, type Runner, type RunMode } from "./types.js";

export { MockRunner } from "./mock.js";
export { LiveRunner } from "./live.js";
export * from "./types.js";

/**
 * Create the runner for the effective mode. Live mode is only selected when the
 * operator has explicitly opted in (see resolveMode); otherwise, and on any
 * LiveRunner construction failure, we fall back to the safe MockRunner.
 */
export function createRunner(env: NodeJS.ProcessEnv = process.env): Runner {
  const mode: RunMode = resolveMode(env);
  if (mode === "live") {
    try {
      return new LiveRunner(env);
    } catch (err) {
      console.warn(`[cockpit] live mode unavailable, using mock: ${(err as Error).message}`);
      return new MockRunner();
    }
  }
  return new MockRunner();
}
