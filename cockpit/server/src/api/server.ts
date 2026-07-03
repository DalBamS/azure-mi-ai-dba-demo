import express, { type Express, type Request, type Response } from "express";
import cors from "cors";
import { z } from "zod";
import { findDemo, loadManifest } from "../manifest/load.js";
import type { Manifest } from "../manifest/types.js";
import { createRunner, resolveMode, type Runner } from "../runner/index.js";

const RunBody = z.object({
  demoId: z.string().min(1),
  stepId: z.string().min(1),
  database: z.string().min(1).optional(),
  variant: z.enum(["pass", "fail"]).default("pass"),
});

export interface AppOptions {
  manifest?: Manifest;
  runner?: Runner;
}

/**
 * Build the Express app. Dependencies are injectable so tests can supply a
 * fixed manifest and a mock runner.
 */
export function createApp(opts: AppOptions = {}): Express {
  const manifest = opts.manifest ?? loadManifest();
  const runner = opts.runner ?? createRunner();
  const app = express();

  app.use(cors());
  app.use(express.json());

  app.get("/api/health", (_req: Request, res: Response) => {
    res.json({
      ok: true,
      mode: runner.mode,
      resolvedMode: resolveMode(),
      demos: manifest.demos.length,
    });
  });

  app.get("/api/manifest", (_req: Request, res: Response) => {
    res.json(manifest);
  });

  app.get("/api/demos", (_req: Request, res: Response) => {
    res.json(
      manifest.demos.map((d) => ({
        id: d.id,
        slug: d.slug,
        lifecycle: d.lifecycle,
        title: d.title,
        summary: d.summary,
        whyAi: d.whyAi,
        stepCount: d.steps.length,
      })),
    );
  });

  app.get("/api/demos/:id", (req: Request, res: Response) => {
    const demo = findDemo(manifest, req.params.id);
    if (!demo) {
      res.status(404).json({ error: `demo not found: ${req.params.id}` });
      return;
    }
    res.json(demo);
  });

  app.post("/api/run", async (req: Request, res: Response) => {
    const parsed = RunBody.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "invalid body", details: parsed.error.flatten() });
      return;
    }
    const demo = findDemo(manifest, parsed.data.demoId);
    if (!demo) {
      res.status(404).json({ error: `demo not found: ${parsed.data.demoId}` });
      return;
    }
    const step = demo.steps.find((s) => s.id === parsed.data.stepId);
    if (!step) {
      res.status(404).json({ error: `step not found: ${parsed.data.stepId}` });
      return;
    }
    try {
      const result = await runner.run(demo, step, {
        database: parsed.data.database,
        variant: parsed.data.variant,
      });
      res.json(result);
    } catch (err) {
      res.status(500).json({ error: (err as Error).message });
    }
  });

  return app;
}
