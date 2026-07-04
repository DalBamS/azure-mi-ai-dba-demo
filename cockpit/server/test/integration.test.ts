import { describe, it, expect, beforeAll, afterAll } from "vitest";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/api/server.js";
import { createRunner } from "../src/runner/index.js";
import { loadManifest } from "../src/manifest/load.js";
import { findRepoRoot } from "../src/manifest/paths.js";

/**
 * Integration self-test: exercises the SAME wiring the shipped server uses
 * (loadManifest + createRunner + createApp) over real HTTP, then drives every
 * runnable step of every demo through POST /api/run — all in mock mode, so no
 * Managed Instance is contacted. This is the cross-cutting Phase-5 check that
 * ties manifest -> API -> runner together.
 */
let server: Server;
let base: string;

beforeAll(async () => {
  const app = createApp({ manifest: loadManifest(), runner: createRunner({}) });
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

describe("integration (mock, end-to-end)", () => {
  it("serves mock mode and the full demo catalog", async () => {
    const health = await (await fetch(`${base}/api/health`)).json();
    expect(health.mode).toBe("mock");
    expect(health.demos).toBe(11);
  });

  it("runs every runnable step of every demo through the HTTP API", async () => {
    const demos = await (await fetch(`${base}/api/demos`)).json();
    let ran = 0;
    let analysisOnly = 0;

    for (const summary of demos as Array<{ id: string }>) {
      const demo = await (await fetch(`${base}/api/demos/${summary.id}`)).json();
      for (const step of demo.steps as Array<{ id: string; kind: string; analysisOnly?: boolean }>) {
        if (step.analysisOnly) {
          analysisOnly++;
          continue;
        }
        const res = await (
          await fetch(`${base}/api/run`, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({ demoId: demo.id, stepId: step.id }),
          })
        ).json();

        expect(res.mocked).toBe(true);
        expect(res.exitCode).toBe(0);
        expect(res.stderr).toBe("");
        // A real password flag must never surface in the command string.
        expect(res.command).not.toMatch(/-P\s+\S/);
        if (step.kind !== "md") {
          expect(res.stdout).toContain("no Managed Instance was contacted");
        }
        ran++;
      }
    }

    // 11 demos, 72 steps total: 70 runnable, 2 analysis-only samples blocked by design.
    expect(ran).toBe(70);
    expect(analysisOnly).toBe(2);
  });

  it("exposes the mocked eval FAIL path through the real HTTP wiring", async () => {
    const res = await fetch(`${base}/api/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A", stepId: "03_eval", variant: "fail" }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.mocked).toBe(true);
    expect(body.mode).toBe("mock");
    expect(body.exitCode).not.toBe(0);
    expect(body.stdout).toContain("logical_reads_ok    FAIL");
    expect(body.stdout).toContain("no Managed Instance was contacted");
    expect(body.command).not.toMatch(/-P\s+\S/);
  });

  it("ships a built web bundle that references the API", () => {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const repoRoot = findRepoRoot(here);
    const dist = path.join(repoRoot, "cockpit", "web", "dist");
    // The web bundle is a build artifact (git-ignored); only assert on it when
    // present so the backend self-test stays independent of a prior web build.
    if (!fs.existsSync(dist)) return;
    const indexHtml = path.join(dist, "index.html");
    expect(fs.existsSync(indexHtml)).toBe(true);
    const assetsDir = path.join(dist, "assets");
    const bundled = fs
      .readdirSync(assetsDir)
      .filter((f) => f.endsWith(".js"))
      .map((f) => fs.readFileSync(path.join(assetsDir, f), "utf8"))
      .join("\n");
    expect(bundled).toContain("/api/");
  });
});
