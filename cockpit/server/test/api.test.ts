import { describe, it, expect, beforeAll, afterAll } from "vitest";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { createApp } from "../src/api/server.js";
import { MockRunner } from "../src/runner/index.js";
import { loadManifest } from "../src/manifest/load.js";

let server: Server;
let base: string;

beforeAll(async () => {
  // Force mock runner explicitly so the API self-test never contacts a MI.
  const app = createApp({ manifest: loadManifest(), runner: new MockRunner() });
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

  it("GET /api/demos/:id returns steps; unknown -> 404", async () => {
    const ok = await fetch(`${base}/api/demos/A`);
    expect(ok.status).toBe(200);
    expect((await ok.json()).steps.length).toBeGreaterThan(0);

    const miss = await fetch(`${base}/api/demos/ZZZ`);
    expect(miss.status).toBe(404);
  });

  it("POST /api/run returns a mocked result", async () => {
    const res = await fetch(`${base}/api/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A", stepId: "03_eval" }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.mocked).toBe(true);
    expect(body.exitCode).toBe(0);
    expect(body.stdout).toContain("no Managed Instance was contacted");
  });

  it("POST /api/run validates the body", async () => {
    const res = await fetch(`${base}/api/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A" }),
    });
    expect(res.status).toBe(400);
  });

  it("POST /api/run 404s on unknown step", async () => {
    const res = await fetch(`${base}/api/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A", stepId: "99_nope" }),
    });
    expect(res.status).toBe(404);
  });
});
