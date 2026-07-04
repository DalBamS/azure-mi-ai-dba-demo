import { spawn } from "node:child_process";
import path from "node:path";
import { findRepoRoot } from "../manifest/paths.js";
import type { Demo, Step } from "../manifest/types.js";
import type { RunContext, RunResult, Runner } from "./types.js";

/**
 * LiveRunner executes a demo step against a real Managed Instance by shelling
 * out to sqlcmd / pwsh / python. It mirrors the connection logic in
 * scripts/lib.ps1 (env-derived, secrets NEVER hardcoded).
 *
 * Live execution is strongly guarded: construction throws unless the operator
 * has explicitly opted in via COCKPIT_ALLOW_LIVE=1 and provided SQLMI_SERVER.
 * Self-tests do not use this runner, so no live instance is contacted here.
 */
export class LiveRunner implements Runner {
  readonly mode = "live" as const;
  private readonly repoRoot: string;

  constructor(private readonly env: NodeJS.ProcessEnv = process.env) {
    if (env.COCKPIT_ALLOW_LIVE !== "1") {
      throw new Error(
        "LiveRunner refused: set COCKPIT_ALLOW_LIVE=1 to enable live execution (mock is the default).",
      );
    }
    if (!env.SQLMI_SERVER) {
      throw new Error("LiveRunner refused: SQLMI_SERVER is not set (configure .env; never hardcode).");
    }
    this.repoRoot = findRepoRoot();
  }

  async run(demo: Demo, step: Step, ctx: Partial<RunContext> = {}): Promise<RunResult> {
    const startedAt = new Date().toISOString();
    const database = ctx.database ?? this.env.SQLMI_DATABASE ?? "gamedb";
    const base = {
      demoId: demo.id,
      stepId: step.id,
      kind: step.kind,
      mode: this.mode,
      mocked: false,
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
        stdout: `Manual step — open ${step.path} and follow it.`,
        stderr: "",
      };
    }

    const abs = path.join(this.repoRoot, step.path);
    const { file, args, redacted } = this.buildInvocation(step, abs, database);

    const started = Date.now();
    const { exitCode, stdout, stderr } = await this.spawn(file, args);
    return {
      ...base,
      manual: false,
      skipped: false,
      exitCode,
      durationMs: Date.now() - started,
      command: redacted,
      stdout,
      stderr,
    };
  }

  /**
   * Build the interpreter invocation for a step. The `redacted` string is safe
   * to surface in the UI/logs — it never contains a password or secret.
   */
  private buildInvocation(
    step: Step,
    abs: string,
    database: string,
  ): { file: string; args: string[]; redacted: string } {
    switch (step.kind) {
      case "sql": {
        const args = [...this.sqlcmdArgs(database), "-i", abs];
        return {
          file: "sqlcmd",
          args,
          redacted: `sqlcmd ${this.redactSqlcmd(args).join(" ")}`,
        };
      }
      case "ps1": {
        const args = ["-NoProfile", "-NonInteractive", "-File", abs];
        return { file: "pwsh", args, redacted: `pwsh ${args.join(" ")}` };
      }
      case "py": {
        const args = [abs];
        return { file: "python", args, redacted: `python ${args.join(" ")}` };
      }
      default:
        throw new Error(`Unsupported step kind for live run: ${step.kind}`);
    }
  }

  /** Mirror scripts/lib.ps1 Get-SqlcmdArgs: build sqlcmd args from env. */
  private sqlcmdArgs(database: string): string[] {
    const env = this.env;
    const server = env.SQLMI_SERVER!;
    const port = env.SQLMI_PORT || "1433";
    const authMode = (env.AUTH_MODE || "aad-integrated").toLowerCase();

    const args = ["-S", `tcp:${server},${port}`, "-d", database, "-N"];
    if (env.ODBC_TRUST_SERVER_CERT === "yes") args.push("-C");

    switch (authMode) {
      case "sql":
        args.push("-U", env.SQL_USER ?? "", "-P", env.SQL_PASSWORD ?? "");
        break;
      case "aad-password":
        args.push("-G", "-U", env.SQL_USER ?? "", "-P", env.SQL_PASSWORD ?? "");
        break;
      default:
        args.push("-G"); // aad-integrated / service-principal via az context
    }
    return args;
  }

  /** Redact the value following any -P (password) flag. */
  private redactSqlcmd(args: string[]): string[] {
    const out = [...args];
    for (let i = 0; i < out.length - 1; i++) {
      if (out[i] === "-P") out[i + 1] = "***";
    }
    return out;
  }

  private spawn(
    file: string,
    args: string[],
  ): Promise<{ exitCode: number; stdout: string; stderr: string }> {
    return new Promise((resolve) => {
      const child = spawn(file, args, { cwd: this.repoRoot, shell: false });
      let stdout = "";
      let stderr = "";
      child.stdout.on("data", (d) => (stdout += d.toString()));
      child.stderr.on("data", (d) => (stderr += d.toString()));
      child.on("error", (err) => {
        stderr += `\n[spawn error] ${err.message}`;
        resolve({ exitCode: 127, stdout, stderr });
      });
      child.on("close", (code) => resolve({ exitCode: code ?? 0, stdout, stderr }));
    });
  }
}
