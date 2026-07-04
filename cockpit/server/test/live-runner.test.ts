import { EventEmitter } from "node:events";
import { spawn } from "node:child_process";
import { describe, it, expect, beforeEach, vi } from "vitest";
import { LiveRunner, createRunner } from "../src/runner/index.js";
import { findDemo, loadManifest } from "../src/manifest/load.js";

vi.mock("node:child_process", () => ({
  spawn: vi.fn(),
}));

const manifest = loadManifest();

class FakeChild extends EventEmitter {
  readonly stdout = new EventEmitter();
  readonly stderr = new EventEmitter();
}

describe("live runner safety boundaries", () => {
  beforeEach(() => {
    vi.mocked(spawn).mockReset();
  });

  it("falls back to mock unless live mode has the full explicit opt-in", () => {
    expect(createRunner({ COCKPIT_MODE: "live" }).mode).toBe("mock");
    expect(createRunner({ COCKPIT_MODE: "live", COCKPIT_ALLOW_LIVE: "1" }).mode).toBe("mock");
  });

  it("builds a redacted sqlcmd command without exposing the password", async () => {
    let captured:
      | {
          file: string;
          args: string[];
        }
      | undefined;
    vi.mocked(spawn).mockImplementation((file, args) => {
      captured = { file, args: [...(args as string[])] };
      const child = new FakeChild();
      queueMicrotask(() => {
        child.stdout.emit("data", Buffer.from("live stdout\n"));
        child.emit("close", 0);
      });
      return child as never;
    });

    const runner = new LiveRunner({
      COCKPIT_ALLOW_LIVE: "1",
      SQLMI_SERVER: "example.invalid",
      SQLMI_DATABASE: "gamedb",
      AUTH_MODE: "sql",
      SQL_USER: "demo-user",
      SQL_PASSWORD: "super-secret",
    });
    const demo = findDemo(manifest, "A")!;
    const step = demo.steps.find((s) => s.id === "03_eval")!;
    const result = await runner.run(demo, step, { variant: "fail" });

    expect(captured?.file).toBe("sqlcmd");
    expect(captured?.args).toContain("super-secret");
    expect(result.mocked).toBe(false);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("live stdout");
    expect(result.stdout).not.toContain("logical_reads_ok    FAIL");
    expect(result.command).toContain("-P ***");
    expect(result.command).not.toContain("super-secret");
  });

  it("runs a single injection step through one sqlcmd process", async () => {
    let capturedArgs: string[] = [];
    vi.mocked(spawn).mockImplementation((_file, args) => {
      capturedArgs = [...(args as string[])];
      const child = new FakeChild();
      queueMicrotask(() => {
        child.stdout.emit("data", Buffer.from("injected missing index\n"));
        child.emit("close", 0);
      });
      return child as never;
    });

    const runner = new LiveRunner({
      COCKPIT_ALLOW_LIVE: "1",
      SQLMI_SERVER: "example.invalid",
      SQLMI_DATABASE: "gamedb",
    });
    const demo = findDemo(manifest, "A")!;
    const step = demo.steps.find((s) => s.id === "00_inject")!;
    const result = await runner.run(demo, step);

    expect(spawn).toHaveBeenCalledTimes(1);
    expect(capturedArgs).toContain("-i");
    expect(capturedArgs.at(-1)).toMatch(/issue-injection[\\/]+01_missing_index\.sql$/);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("injected missing index");
    expect(result.command).toContain("sqlcmd");
  });

  it("runs concurrentPaths by spawning one sqlcmd process per path and merging labeled output", async () => {
    const capturedArgs: string[][] = [];
    vi.mocked(spawn).mockImplementation((_file, args) => {
      const callIndex = capturedArgs.length;
      capturedArgs.push([...(args as string[])]);
      const child = new FakeChild();
      queueMicrotask(() => {
        child.stdout.emit("data", Buffer.from(`stdout ${callIndex + 1}\n`));
        child.stderr.emit("data", Buffer.from(`stderr ${callIndex + 1}\n`));
        child.emit("close", 0);
      });
      return child as never;
    });

    const runner = new LiveRunner({
      COCKPIT_ALLOW_LIVE: "1",
      SQLMI_SERVER: "example.invalid",
      SQLMI_DATABASE: "gamedb",
      AUTH_MODE: "sql",
      SQL_USER: "demo-user",
      SQL_PASSWORD: "super-secret",
    });
    const demo = findDemo(manifest, "B")!;
    const step = demo.steps.find((s) => s.id === "00_inject")!;
    const result = await runner.run(demo, step);

    expect(spawn).toHaveBeenCalledTimes(2);
    expect(capturedArgs[0]).toContain("-i");
    expect(capturedArgs[1]).toContain("-i");
    expect(capturedArgs[0]!.at(-1)).toMatch(/issue-injection[\\/]+02_blocking_deadlock\.sessionA\.sql$/);
    expect(capturedArgs[1]!.at(-1)).toMatch(/issue-injection[\\/]+02_blocking_deadlock\.sessionB\.sql$/);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("[SESSION A] issue-injection/02_blocking_deadlock.sessionA.sql");
    expect(result.stdout).toContain("[SESSION B] issue-injection/02_blocking_deadlock.sessionB.sql");
    expect(result.stdout).toContain("stdout 1");
    expect(result.stdout).toContain("stdout 2");
    expect(result.stderr).toContain("[SESSION A] issue-injection/02_blocking_deadlock.sessionA.sql");
    expect(result.stderr).toContain("[SESSION B] issue-injection/02_blocking_deadlock.sessionB.sql");
    expect(result.command).toContain("[SESSION A] sqlcmd");
    expect(result.command).toContain("[SESSION B] sqlcmd");
    expect(result.command).toContain("-P ***");
    expect(result.command).not.toContain("super-secret");
  });

  it("does not pass the mock-only variant to live process invocations", async () => {
    let capturedArgs: string[] = [];
    vi.mocked(spawn).mockImplementation((_file, args) => {
      capturedArgs = [...(args as string[])];
      const child = new FakeChild();
      queueMicrotask(() => {
        child.stdout.emit("data", Buffer.from("live stdout\n"));
        child.emit("close", 0);
      });
      return child as never;
    });

    const runner = new LiveRunner({
      COCKPIT_ALLOW_LIVE: "1",
      SQLMI_SERVER: "example.invalid",
      SQLMI_DATABASE: "gamedb",
    });
    const demo = findDemo(manifest, "A")!;
    const step = demo.steps.find((s) => s.id === "03_eval")!;

    await runner.run(demo, step, { variant: "fail" });

    expect(capturedArgs).not.toContain("fail");
  });

  it("refuses analysis-only steps before spawning a live process", async () => {
    const runner = new LiveRunner({
      COCKPIT_ALLOW_LIVE: "1",
      SQLMI_SERVER: "example.invalid",
      SQLMI_DATABASE: "gamedb",
    });
    const demo = findDemo(manifest, "J")!;
    const step = demo.steps.find((s) => s.id === "sample-migrations/risky_drop_column")!;

    const result = await runner.run(demo, step);

    expect(spawn).not.toHaveBeenCalled();
    expect(result).toMatchObject({
      mocked: false,
      manual: true,
      skipped: true,
      exitCode: 0,
      durationMs: 0,
      command: "(analysis-only) not executed",
      stdout: "Analysis-only step — intentionally-risky sample for AI review. Not executed.",
      stderr: "",
    });
  });
});
