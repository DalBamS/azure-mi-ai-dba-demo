import { describe, it, expect, afterEach, vi } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { findRepoRoot } from "../src/manifest/paths.js";
import { loadManifest, findDemo } from "../src/manifest/load.js";
import { buildManifest } from "../src/manifest/generate.js";
import { ManifestSchema } from "../src/manifest/types.js";
import {
  MockRunner,
  LiveRunner,
  createRunner,
  resolveMode,
} from "../src/runner/index.js";

const repoRoot = findRepoRoot();
const manifest = loadManifest(repoRoot);

/** Matches the forbidden real-infra / secret tokens the repo must never contain. */
const FORBIDDEN = /(mieuson20260630|e0d6055acbac|c18a5af0|MngEnvMCAP842578|38a6f9e9)/;

afterEach(() => {
  vi.restoreAllMocks();
});

describe("manifest", () => {
  it("loads and validates against the schema", () => {
    expect(() => ManifestSchema.parse(manifest)).not.toThrow();
    expect(manifest.demos.length).toBe(11);
  });

  it("committed manifest matches a fresh scan of demos/**", () => {
    const fresh = buildManifest(repoRoot);
    const strip = (m: typeof manifest) => ({
      ...m,
      generatedAt: "",
      demos: m.demos,
    });
    expect(strip(fresh)).toEqual(strip(manifest));
  });

  it("includes curated presenter annotations for every demo", () => {
    for (const demo of manifest.demos) {
      expect(demo.summary, `${demo.id} summary`).toBeTruthy();
      expect(demo.whyAi, `${demo.id} whyAi`).toBeTruthy();
    }
  });

  it("orders cicd nested assets by README narrative", () => {
    expect(findDemo(manifest, "I")?.steps.map((s) => s.id)).toEqual([
      "prompts/nl-request",
      "migrations/001_add_season_id_to_leaderboard.up",
      "migrations/001_add_season_id_to_leaderboard.down",
      "migrations/002_add_inventory_soft_delete.up",
      "migrations/002_add_inventory_soft_delete.down",
      "db-project/Tables/currency_ledger",
      "db-project/Tables/inventory",
      "db-project/Tables/leaderboard",
      "db-project/Tables/matches",
      "db-project/Tables/players",
      "db-project/Tables/seasons",
    ]);
    expect(findDemo(manifest, "J")?.steps.map((s) => s.id)).toEqual([
      "sample-migrations/risky_alter_inventory",
      "sample-migrations/risky_drop_column",
      "ai-review/risk-rubric",
      "ai-review/risk-report",
      "ai-review/pr-review-comments",
      "security-gate/over-privilege",
      "security-gate/masking-gap",
      "security-gate/secret-scan",
    ]);
    expect(findDemo(manifest, "K")?.steps.map((s) => s.id)).toEqual([
      "scripts/drift-check",
      "scripts/smoke-load",
      "scripts/summarize-failure",
    ]);
  });

  it("gates down migrations as destructive", () => {
    for (const demo of manifest.demos) {
      for (const step of demo.steps.filter((s) => /\.down$/i.test(s.id))) {
        expect(step.destructive, `${demo.id}/${step.id}`).toBe(true);
      }
    }
  });

  it("references only files that exist on disk", () => {
    for (const demo of manifest.demos) {
      for (const step of demo.steps) {
        const abs = path.join(repoRoot, step.path);
        expect(fs.existsSync(abs), `${step.path} should exist`).toBe(true);
      }
    }
  });

  it("contains no forbidden real-infra / secret tokens", () => {
    expect(FORBIDDEN.test(JSON.stringify(manifest))).toBe(false);
  });
});

describe("mode resolution (mock is the safe default)", () => {
  it("defaults to mock with an empty env", () => {
    expect(resolveMode({})).toBe("mock");
  });

  it("stays mock when live is requested without full opt-in", () => {
    expect(resolveMode({ COCKPIT_MODE: "live" })).toBe("mock");
    expect(resolveMode({ COCKPIT_MODE: "live", COCKPIT_ALLOW_LIVE: "1" })).toBe("mock");
    expect(
      resolveMode({ COCKPIT_MODE: "live", SQLMI_SERVER: "placeholder.example" }),
    ).toBe("mock");
  });

  it("only resolves live when ALL conditions are met", () => {
    expect(
      resolveMode({
        COCKPIT_MODE: "live",
        COCKPIT_ALLOW_LIVE: "1",
        SQLMI_SERVER: "placeholder.example",
      }),
    ).toBe("live");
  });

  it("createRunner returns a MockRunner by default", () => {
    expect(createRunner({}).mode).toBe("mock");
  });

  it("LiveRunner refuses to construct without explicit opt-in", () => {
    expect(() => new LiveRunner({})).toThrow(/COCKPIT_ALLOW_LIVE/);
    expect(() => new LiveRunner({ COCKPIT_ALLOW_LIVE: "1" })).toThrow(/SQLMI_SERVER/);
  });
});

describe("mock runner contacts no Managed Instance", () => {
  it("its source imports no process-spawning or network modules", () => {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const src = fs.readFileSync(path.join(here, "../src/runner/mock.ts"), "utf8");
    // MockRunner must be pure: no child_process, net, http(s), dns, or fetch.
    expect(src).not.toMatch(/child_process/);
    expect(src).not.toMatch(/node:(net|http|https|dns|tls)/);
    expect(src).not.toMatch(/\bfetch\s*\(/);
  });

  it("returns mocked results for every step of every demo", async () => {
    const runner = new MockRunner();

    let executed = 0;
    let manual = 0;
    for (const demo of manifest.demos) {
      for (const step of demo.steps) {
        const res = await runner.run(demo, step);
        expect(res.mocked).toBe(true);
        expect(res.mode).toBe("mock");
        expect(res.exitCode).toBe(0);
        expect(res.stderr).toBe("");
        // Command strings must never leak a password.
        expect(res.command).not.toMatch(/-P\s+\S/);
        expect(FORBIDDEN.test(res.command + res.stdout)).toBe(false);

        if (step.kind === "md") {
          expect(res.manual).toBe(true);
          expect(res.skipped).toBe(true);
          manual++;
        } else {
          expect(res.skipped).toBe(false);
          expect(res.stdout.length).toBeGreaterThan(0);
          expect(res.stdout).toContain("no Managed Instance was contacted");
          executed++;
        }
      }
    }

    expect(executed).toBeGreaterThan(0);
    // Sanity: total steps covered equals the manifest's step count.
    const total = manifest.demos.reduce((n, d) => n + d.steps.length, 0);
    expect(executed + manual).toBe(total);
  });

  it("returns a mocked eval failure without exposing live connectivity", async () => {
    const runner = new MockRunner();
    const demo = findDemo(manifest, "A")!;
    const step = demo.steps.find((s) => s.id === "03_eval")!;
    const res = await runner.run(demo, step, { variant: "fail" });

    expect(res.mocked).toBe(true);
    expect(res.mode).toBe("mock");
    expect(res.exitCode).not.toBe(0);
    expect(res.stdout).toContain("logical_reads_ok    FAIL");
    expect(res.stdout).toContain("no Managed Instance was contacted");
    expect(res.command).not.toMatch(/-P\s+\S/);
  });
});

describe("findDemo", () => {
  it("resolves by id and by slug, case-insensitively", () => {
    expect(findDemo(manifest, "a")?.slug).toBe("A-slow-query-index");
    expect(findDemo(manifest, "A-slow-query-index")?.id).toBe("A");
    expect(findDemo(manifest, "nope")).toBeUndefined();
  });
});
