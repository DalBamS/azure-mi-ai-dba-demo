import { buildMessages, type ChatMessage } from "./prompt.js";

export type AiMode = "mock" | "live";

export interface AiResult {
  answer: string;
  model: string;
  latencyMs: number;
  mode: AiMode;
  mocked: boolean;
}

export interface AiClient {
  readonly mode: AiMode;
  ask(question: string, contextText?: string): Promise<AiResult>;
}

interface ChatCompletionResponse {
  choices?: Array<{
    message?: {
      content?: string;
    };
  }>;
}

export const MOCK_AI_MODEL = "mock-foundry";

function modelFromEnv(env: NodeJS.ProcessEnv): string {
  return env.AI_FOUNDRY_DEPLOYMENT?.trim() || MOCK_AI_MODEL;
}

function endpointFromEnv(env: NodeJS.ProcessEnv): string | undefined {
  return env.AI_FOUNDRY_ENDPOINT?.trim() || undefined;
}

function apiKeyFromEnv(env: NodeJS.ProcessEnv): string | undefined {
  return env.AI_FOUNDRY_API_KEY?.trim() || undefined;
}

function authModeFromEnv(env: NodeJS.ProcessEnv): "api-key" | "bearer" {
  return env.AI_FOUNDRY_AUTH?.trim().toLowerCase() === "bearer" ? "bearer" : "api-key";
}

export function resolveAiMode(env: NodeJS.ProcessEnv = process.env): AiMode {
  const requested = (env.COCKPIT_MODE ?? "mock").toLowerCase();
  if (
    requested === "live" &&
    env.COCKPIT_ALLOW_LIVE === "1" &&
    endpointFromEnv(env) &&
    apiKeyFromEnv(env)
  ) {
    return "live";
  }
  return "mock";
}

export function resolveAiModel(env: NodeJS.ProcessEnv = process.env): string {
  return modelFromEnv(env);
}

export function isAiEndpointConfigured(env: NodeJS.ProcessEnv = process.env): boolean {
  return Boolean(endpointFromEnv(env));
}

export function resolveAiEndpointHost(env: NodeJS.ProcessEnv = process.env): string {
  const endpoint = endpointFromEnv(env);
  if (!endpoint) return "(not configured)";
  try {
    return new URL(endpoint).host;
  } catch {
    return "(invalid AI_FOUNDRY_ENDPOINT)";
  }
}

export class MockAiClient implements AiClient {
  readonly mode = "mock" as const;
  private readonly model = MOCK_AI_MODEL;

  async ask(_question: string, contextText?: string): Promise<AiResult> {
    const started = Date.now();
    const hasContext = Boolean(contextText?.trim());
    const answer = hasContext
      ? [
          "### AI 진단 (mock)",
          "",
          "- 제공된 DIAGNOSE OUTPUT만 근거로 해석하는 안전한 rehearsal 응답입니다.",
          "- `dbo.leaderboard` 랭킹 조회는 시즌별 상위 rating 정렬 경로에서 인덱스 누락이 병목일 가능성이 높습니다.",
          "- 사람이 검토할 후보 DDL: `CREATE INDEX IX_leaderboard_rating ON dbo.leaderboard(season, rating DESC) INCLUDE(player_id, wins, losses);`",
          "- 적용 전 실행계획, Query Store/DMV logical reads, 쓰기 부하 영향을 DBA가 확인하세요.",
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
      answer,
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
  private readonly apiKey: string;
  private readonly authMode: "api-key" | "bearer";
  private readonly timeoutMs: number;

  constructor(env: NodeJS.ProcessEnv = process.env, timeoutMs = 60_000) {
    const endpoint = endpointFromEnv(env);
    const apiKey = apiKeyFromEnv(env);
    if (!endpoint) throw new Error("AI_FOUNDRY_ENDPOINT is not set");
    if (!apiKey) throw new Error("AI_FOUNDRY_API_KEY is not set");
    this.endpoint = endpoint;
    this.model = modelFromEnv(env);
    this.apiKey = apiKey;
    this.authMode = authModeFromEnv(env);
    this.timeoutMs = timeoutMs;
  }

  async ask(question: string, contextText?: string): Promise<AiResult> {
    const started = Date.now();
    const messages: ChatMessage[] = buildMessages({ question, contextText });
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (this.authMode === "bearer") {
      headers.authorization = `Bearer ${this.apiKey}`;
    } else {
      headers["api-key"] = this.apiKey;
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    let response: Response;
    try {
      response = await fetch(this.endpoint, {
        method: "POST",
        headers,
        signal: controller.signal,
        body: JSON.stringify({
          model: this.model,
          messages,
          temperature: 0.2,
          max_tokens: 512,
          stream: false,
        }),
      });
    } catch (err) {
      if ((err as Error).name === "AbortError") {
        throw new Error("Azure AI Foundry request timed out");
      }
      throw new Error(`Azure AI Foundry request failed: ${(err as Error).message}`);
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      throw new Error(`Azure AI Foundry request failed with HTTP ${response.status}`);
    }

    let body: ChatCompletionResponse;
    try {
      body = (await response.json()) as ChatCompletionResponse;
    } catch {
      throw new Error("Azure AI Foundry response was not valid JSON");
    }
    const answer = body.choices?.[0]?.message?.content?.trim();
    if (!answer) {
      throw new Error("Azure AI Foundry response did not include choices[0].message.content");
    }

    return {
      answer,
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
