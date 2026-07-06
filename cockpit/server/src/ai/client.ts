import { buildMessages, type ChatMessage } from "./prompt.js";

export type AiMode = "mock" | "live";

export interface AiInput {
  demoId: string;
  question: string;
  contextText?: string;
}

export interface AiResult {
  answerMarkdown: string;
  model: string;
  latencyMs: number;
  mode: AiMode;
  mocked: boolean;
}

export interface AiClient {
  readonly mode: AiMode;
  ask(input: AiInput): Promise<AiResult>;
}

interface ChatCompletionResponse {
  choices?: Array<{
    message?: {
      content?: string;
    };
  }>;
}

export const DEFAULT_SLM_ENDPOINT = "http://127.0.0.1:11434/v1";
export const DEFAULT_SLM_MODEL = "qwen2.5:3b";
const LIVE_AI_TIMEOUT_MS = 120_000;

function modelFromEnv(env: NodeJS.ProcessEnv): string {
  return env.SLM_MODEL?.trim() || DEFAULT_SLM_MODEL;
}

function endpointFromEnv(env: NodeJS.ProcessEnv): string {
  return (env.SLM_ENDPOINT?.trim() || DEFAULT_SLM_ENDPOINT).replace(/\/+$/, "");
}

export function resolveAiMode(env: NodeJS.ProcessEnv = process.env): AiMode {
  const requested = (env.COCKPIT_MODE ?? "mock").toLowerCase();
  if (requested === "live" && env.COCKPIT_ALLOW_LIVE === "1" && env.SLM_ENDPOINT?.trim()) {
    return "live";
  }
  return "mock";
}

export function resolveAiModel(env: NodeJS.ProcessEnv = process.env): string {
  return modelFromEnv(env);
}

export function resolveAiEndpointHost(env: NodeJS.ProcessEnv = process.env): string {
  try {
    return new URL(endpointFromEnv(env)).host;
  } catch {
    return "(invalid SLM_ENDPOINT)";
  }
}

export class MockAiClient implements AiClient {
  readonly mode = "mock" as const;
  private readonly model = "mock-slm";

  async ask(input: AiInput): Promise<AiResult> {
    const started = Date.now();
    const hasContext = Boolean(input.contextText?.trim());
    const answerMarkdown = hasContext
      ? [
          "### AI 진단 (mock)",
          "",
          "- 제공된 DIAGNOSE OUTPUT만 근거로 해석하는 안전한 mock 응답입니다.",
          `- Demo ${input.demoId}: 증상과 DMV/실행 결과를 연결해 병목 원인을 확인하세요.`,
          "- 인덱스 누락이 근거로 확인되면 예시는 `CREATE INDEX IX_leaderboard_rating ON dbo.leaderboard(rating DESC) INCLUDE (player_id);` 입니다.",
          "- 제안된 DDL은 절대 자동 적용되지 않으며, 반드시 사람이 검토·승인 후 적용해야 합니다.",
        ].join("\n")
      : [
          "### AI 진단 (mock)",
          "",
          "DIAGNOSE OUTPUT이 비어 있습니다. 먼저 diagnose/evidence 스텝을 실행한 뒤 다시 질문하세요.",
          "",
          "제안된 DDL은 절대 자동 적용되지 않으며, 반드시 사람이 검토·승인 후 적용해야 합니다.",
        ].join("\n");

    return {
      answerMarkdown,
      model: this.model,
      latencyMs: Date.now() - started,
      mode: this.mode,
      mocked: true,
    };
  }
}

export class LiveAiClient implements AiClient {
  readonly mode = "live" as const;
  private readonly endpoint: string;
  private readonly model: string;
  private readonly apiKey?: string;

  constructor(env: NodeJS.ProcessEnv = process.env) {
    this.endpoint = endpointFromEnv(env);
    this.model = modelFromEnv(env);
    this.apiKey = env.SLM_API_KEY?.trim() || undefined;
  }

  async ask(input: AiInput): Promise<AiResult> {
    const started = Date.now();
    const messages: ChatMessage[] = buildMessages(input);
    const headers: Record<string, string> = { "content-type": "application/json" };
    if (this.apiKey) headers.authorization = `Bearer ${this.apiKey}`;
    const abort = new AbortController();
    const timeout = setTimeout(() => abort.abort(), LIVE_AI_TIMEOUT_MS);

    let response: Response;
    try {
      response = await fetch(`${this.endpoint}/chat/completions`, {
        method: "POST",
        headers,
        signal: abort.signal,
        body: JSON.stringify({
          model: this.model,
          messages,
          stream: false,
          temperature: 0.2,
          max_tokens: 256,
          keep_alive: -1,
        }),
      });
    } catch (err) {
      throw new Error(`SLM request failed: ${(err as Error).message}`);
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      throw new Error(`SLM request failed with HTTP ${response.status}`);
    }

    const body = (await response.json()) as ChatCompletionResponse;
    const answerMarkdown = body.choices?.[0]?.message?.content?.trim();
    if (!answerMarkdown) {
      throw new Error("SLM response did not include choices[0].message.content");
    }

    return {
      answerMarkdown,
      model: this.model,
      latencyMs: Date.now() - started,
      mode: this.mode,
      mocked: false,
    };
  }
}

export function createAiClient(env: NodeJS.ProcessEnv = process.env): AiClient {
  if (resolveAiMode(env) === "live") {
    return new LiveAiClient(env);
  }
  return new MockAiClient();
}
