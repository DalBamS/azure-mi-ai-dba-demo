export type Lifecycle = "runtime" | "pre-prod" | "cicd";
export type StepKind = "sql" | "ps1" | "py" | "md";

export interface Step {
  order: number;
  id: string;
  file: string;
  path: string;
  kind: StepKind;
  title: string;
  destructive: boolean;
  manual: boolean;
}

export interface Demo {
  id: string;
  slug: string;
  lifecycle: Lifecycle;
  title: string;
  path: string;
  readme: string | null;
  steps: Step[];
}

export interface DemoSummary {
  id: string;
  slug: string;
  lifecycle: Lifecycle;
  title: string;
  stepCount: number;
}

export interface Health {
  ok: boolean;
  mode: "mock" | "live";
  resolvedMode: "mock" | "live";
  demos: number;
}

export interface RunResult {
  demoId: string;
  stepId: string;
  kind: StepKind;
  mode: "mock" | "live";
  mocked: boolean;
  manual: boolean;
  skipped: boolean;
  exitCode: number;
  durationMs: number;
  startedAt: string;
  command: string;
  stdout: string;
  stderr: string;
}

async function json<T>(res: Response): Promise<T> {
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`${res.status} ${res.statusText}: ${body}`);
  }
  return res.json() as Promise<T>;
}

export const api = {
  health: () => fetch("/api/health").then(json<Health>),
  demos: () => fetch("/api/demos").then(json<DemoSummary[]>),
  demo: (id: string) => fetch(`/api/demos/${id}`).then(json<Demo>),
  run: (demoId: string, stepId: string) =>
    fetch("/api/run", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId, stepId }),
    }).then(json<RunResult>),
};
