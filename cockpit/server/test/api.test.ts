import { describe, it, expect, beforeAll, afterAll, vi } from "vitest";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { createApp } from "../src/api/server.js";
import { MockRunner, type Runner } from "../src/runner/index.js";
import { loadManifest } from "../src/manifest/load.js";

let server: Server;
let base: string;
const manifest = loadManifest();

beforeAll(async () => {
  // Force mock runner explicitly so the API self-test never contacts a MI.
  const app = createApp({ manifest, runner: new MockRunner() });
  await new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      const { port } = server.address() as AddressInfo;
      base = `http://127.0.0.1:${port}`;
      resolve();
    });
  });
});

afterAll(async () => {
  await new Promise<void>((resolve) => server.close(() => resolve()));
});

describe("HTTP API (mock)", () => {
  it("GET /api/health reports mock mode and 11 demos", async () => {
    const res = await fetch(`${base}/api/health`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.mode).toBe("mock");
    expect(body.demos).toBe(11);
  });

  it("GET /api/demos lists all demos with step counts", async () => {
    const res = await fetch(`${base}/api/demos`);
    const body = await res.json();
    expect(Array.isArray(body)).toBe(true);
    expect(body.length).toBe(11);
    expect(body.every((d: { stepCount: number }) => d.stepCount > 0)).toBe(true);
  });

  it("GET /api/manifest returns the complete validated manifest", async () => {
    const res = await fetch(`${base}/api/manifest`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.version).toBe(1);
    expect(body.demos).toHaveLength(11);
    expect(body.demos.reduce((n: number, d: { steps: unknown[] }) => n + d.steps.length, 0)).toBe(
      72,
    );
  });

  it("GET /api/demos/:id returns steps; unknown -> 404", async () => {
    const ok = await fetch(`${base}/api/demos/A`);
    expect(ok.status).toBe(200);
    expect((await ok.json()).steps.length).toBeGreaterThan(0);

    const miss = await fetch(`${base}/api/demos/ZZZ`);
    expect(miss.status).toBe(404);
  });

  it("POST /api/run returns a mocked PASS result by default", async () => {
    const res = await fetch(`${base}/api/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A", stepId: "03_eval" }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.mocked).toBe(true);
    expect(body.exitCode).toBe(0);
    expect(body.stdout).toContain("logical_reads_ok    PASS");
    expect(body.stdout).toContain("no Managed Instance was contacted");
  });

  it("POST /api/run can return a mocked eval FAIL regression", async () => {
    const res = await fetch(`${base}/api/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A", stepId: "03_eval", variant: "fail" }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.mocked).toBe(true);
    expect(body.exitCode).not.toBe(0);
    expect(body.stdout).toContain("logical_reads_ok    FAIL");
    expect(body.stdout).toContain("no Managed Instance was contacted");
    expect(body.command).not.toMatch(/-P\s+\S/);
  });

  it("POST /api/run validates the body", async () => {
    const res = await fetch(`${base}/api/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A" }),
    });
    expect(res.status).toBe(400);
  });

  it("POST /api/run rejects invalid variants before runner execution", async () => {
    const res = await fetch(`${base}/api/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A", stepId: "03_eval", variant: "regress" }),
    });
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("invalid body");
    expect(body.details.fieldErrors.variant).toBeTruthy();
  });

  it("POST /api/run 404s on unknown demo", async () => {
    const res = await fetch(`${base}/api/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "ZZZ", stepId: "03_eval" }),
    });
    expect(res.status).toBe(404);
  });

  it("POST /api/run 404s on unknown step", async () => {
    const res = await fetch(`${base}/api/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A", stepId: "99_nope" }),
    });
    expect(res.status).toBe(404);
  });

  it("POST /api/run rejects analysis-only steps before runner execution", async () => {
    const runner: Runner = {
      mode: "mock",
      run: vi.fn(),
    };
    const app = createApp({ manifest, runner });
    const localServer = await new Promise<Server>((resolve) => {
      const listening = app.listen(0, () => resolve(listening));
    });
    const { port } = localServer.address() as AddressInfo;

    try {
      const res = await fetch(`http://127.0.0.1:${port}/api/run`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          demoId: "J",
          stepId: "sample-migrations/risky_drop_column",
        }),
      });
      expect(res.status).toBe(403);
      await expect(res.json()).resolves.toEqual({
        error: "analysis-only step is not executable",
        stepId: "sample-migrations/risky_drop_column",
      });
      expect(runner.run).not.toHaveBeenCalled();
    } finally {
      await new Promise<void>((resolve) => localServer.close(() => resolve()));
    }
  });
});
