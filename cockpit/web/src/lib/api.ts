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
  analysisOnly?: boolean;
  injection?: boolean;
  injectionReset?: boolean;
  concurrentPaths?: string[];
}

export interface Demo {
  id: string;
  slug: string;
  lifecycle: Lifecycle;
  title: string;
  summary?: string;
  whyAi?: string;
  aiHint?: string;
  path: string;
  readme: string | null;
  steps: Step[];
}

export interface DemoSummary {
  id: string;
  slug: string;
  lifecycle: Lifecycle;
  title: string;
  summary?: string;
  whyAi?: string;
  aiHint?: string;
  stepCount: number;
}

export interface Health {
  ok: boolean;
  mode: "mock" | "live";
  resolvedMode: "mock" | "live";
  aiMode: "mock" | "live";
  aiModel: string;
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

export type RunVariant = "pass" | "fail";

export interface AiResult {
  answerMarkdown: string;
  model: string;
  latencyMs: number;
  mode: "mock" | "live";
  mocked: boolean;
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
  run: (demoId: string, stepId: string, variant: RunVariant = "pass") =>
    fetch("/api/run", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId, stepId, variant }),
    }).then(json<RunResult>),
  ask: (demoId: string, question: string, contextText = "") =>
    fetch("/api/ai/ask", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId, question, contextText }),
    }).then(json<AiResult>),
};
