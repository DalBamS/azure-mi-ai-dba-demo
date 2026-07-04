import type { Demo, Step } from "../manifest/types.js";
import type { RunContext, RunResult, Runner } from "./types.js";

/**
 * MockRunner produces deterministic, human-plausible output for a demo step
 * WITHOUT touching the network, spawning a process, or reading any secret.
 *
 * It is the default runner and the only one exercised by self-tests, so the
 * cockpit can be demonstrated fully offline and no live Managed Instance is
 * ever contacted in mock mode.
 */
export class MockRunner implements Runner {
  readonly mode = "mock" as const;

  async run(demo: Demo, step: Step, ctx: Partial<RunContext> = {}): Promise<RunResult> {
    const startedAt = new Date().toISOString();
    const database = ctx.database ?? "gamedb";
    const base = {
      demoId: demo.id,
      stepId: step.id,
      kind: step.kind,
      mode: this.mode,
      mocked: true,
      startedAt,
    };

    if (step.analysisOnly === true) {
      return {
        ...base,
        manual: true,
        skipped: true,
        exitCode: 0,
        durationMs: 0,
        command: "(analysis-only) not executed",
        stdout: "Analysis-only step — intentionally-risky sample for AI review. Not executed.",
        stderr: "",
      };
    }

    if (step.kind === "md") {
      return {
        ...base,
        manual: true,
        skipped: true,
        exitCode: 0,
        durationMs: 0,
        command: `(manual) open ${step.path}`,
        stdout: this.manualGuide(demo, step),
        stderr: "",
      };
    }

    const command = this.describeCommand(demo, step, database);
    const variant = ctx.variant ?? "pass";
    const stdout = this.simulate(demo, step, database, variant);
    const exitCode = variant === "fail" && /eval/i.test(step.id) ? 1 : 0;
    // A small deterministic pseudo-duration keeps the UI lively without randomness.
    const durationMs = 40 + ((step.id.length * 7 + step.order * 11) % 260);

    return {
      ...base,
      manual: false,
      skipped: false,
      exitCode,
      durationMs,
      command,
      stdout,
      stderr: "",
    };
  }

  private describeCommand(demo: Demo, step: Step, database: string): string {
    if (step.concurrentPaths?.length) {
      return step.concurrentPaths
        .map((repoRel, index) => {
          const label = `SESSION ${String.fromCharCode(65 + index)}`;
          return `[mock][${label}] sqlcmd -d ${database} -i ${repoRel}`;
        })
        .join("\n");
    }

    switch (step.kind) {
      case "sql":
        return `[mock] sqlcmd -d ${database} -i ${step.path}`;
      case "ps1":
        return `[mock] pwsh -File ${step.path}`;
      case "py":
        return `[mock] python ${step.path}`;
      default:
        return `[mock] ${step.path}`;
    }
  }

  private simulate(demo: Demo, step: Step, database: string, variant: "pass" | "fail"): string {
    const header =
      `── MOCK RUN ─────────────────────────────────────────\n` +
      `demo   : ${demo.id} (${demo.lifecycle}) ${demo.title}\n` +
      `step   : ${step.order.toString().padStart(2, "0")} ${step.title} [${step.kind}]\n` +
      `source : ${step.path}\n` +
      `db     : ${database}\n` +
      `note   : simulated output — no Managed Instance was contacted.\n` +
      `─────────────────────────────────────────────────────\n`;

    const body =
      step.kind === "sql"
        ? this.simulateSql(step, variant)
        : step.kind === "py"
          ? `Synthesizing profile / driver output (mock)…\nOK: produced 1 artifact for '${step.id}'.`
          : `Executing helper script (mock)…\nOK: '${step.id}' completed with 0 warnings.`;

    return header + body + "\n";
  }

  private simulateSql(step: Step, variant: "pass" | "fail"): string {
    if (step.concurrentPaths?.length) {
      return step.concurrentPaths
        .map((repoRel, index) => {
          const label = `SESSION ${String.fromCharCode(65 + index)}`;
          const outcome =
            index === 0
              ? "completed transaction after peer rollback (simulated)"
              : "deadlock victim 1205 captured and handled (simulated)";
          return `[${label}] ${repoRel}\n${outcome}\nCommands completed successfully.`;
        })
        .join("\n");
    }

    if (step.destructive) {
      return (
        `(mock) applied change set for '${step.id}'.\n` +
        `Commands completed successfully.\n` +
        `(0 rows affected against a live instance — simulated)`
      );
    }
    if (/eval/i.test(step.id)) {
      if (variant === "fail") {
        return (
          `eval_check          result\n` +
          `------------------  ------\n` +
          `precondition_met    PASS\n` +
          `logical_reads_ok    FAIL\n` +
          `(2 rows) [simulated eval regression]`
        );
      }
      return (
        `eval_check          result\n` +
        `------------------  ------\n` +
        `precondition_met    PASS\n` +
        `logical_reads_ok    PASS\n` +
        `(2 rows) [simulated eval]`
      );
    }
    if (/diagnose|observe|capture|collect|classify/i.test(step.id)) {
      return (
        `metric              value\n` +
        `------------------  ---------\n` +
        `rows_scanned        123456\n` +
        `logical_reads       9012\n` +
        `top_wait            PAGEIOLATCH_SH\n` +
        `(3 rows) [simulated diagnostics]`
      );
    }
    return (
      `Commands completed successfully.\n` +
      `(mock) executed '${step.id}' read-only. [simulated]`
    );
  }

  private manualGuide(demo: Demo, step: Step): string {
    return (
      `This step is a manual / documentation guide, not an executable script.\n` +
      `Open ${step.path} and follow it during the demo.\n` +
      `(demo ${demo.id} — ${demo.title})`
    );
  }
}
