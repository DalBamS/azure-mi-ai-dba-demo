import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { buildMessages } from "../src/ai/prompt.js";
import {
  LiveAiClient,
  MockAiClient,
  createAiClient,
  isAiEndpointConfigured,
  resolveAiEndpointHost,
  resolveAiMode,
  type AiClient,
} from "../src/ai/client.js";
import { createApp } from "../src/api/server.js";
import { loadManifest } from "../src/manifest/load.js";
import { MockRunner, type Runner } from "../src/runner/index.js";

const foundryEndpoint =
  "https://demo.services.ai.azure.com/models/chat/completions?api-version=2024-05-01-preview";

function completionResponse(content = "### Azure AI Foundry 진단\n사람 승인 후 적용하세요.") {
  return new Response(JSON.stringify({ choices: [{ message: { content } }] }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

describe("AI prompt", () => {
  it("builds system and user messages with context and human approval guardrails", () => {
    const messages = buildMessages({
      question: "랭킹 조회가 느려요, 원인과 해결책은?",
      contextText: "missing_index_count = 1\navg_duration_ms = 1200",
    });

    expect(messages).toHaveLength(2);
    expect(messages[0]).toMatchObject({ role: "system" });
    expect(messages[0]?.content).toContain("사람이 검토·승인 후 적용");
    expect(messages[0]?.content).toContain("없는 수치나 사실은 만들지 마세요");
    expect(messages[1]).toMatchObject({ role: "user" });
    expect(messages[1]?.content).toContain("DIAGNOSE OUTPUT");
    expect(messages[1]?.content).toContain("missing_index_count = 1");
  });
});

describe("resolveAiMode", () => {
  it.each([
    ["defaults to mock", {}, "mock"],
    [
      "requires COCKPIT_MODE=live",
      {
        COCKPIT_ALLOW_LIVE: "1",
        AI_FOUNDRY_ENDPOINT: foundryEndpoint,
        AI_FOUNDRY_API_KEY: "test-key",
      },
      "mock",
    ],
    [
      "requires COCKPIT_ALLOW_LIVE=1",
      {
        COCKPIT_MODE: "live",
        AI_FOUNDRY_ENDPOINT: foundryEndpoint,
        AI_FOUNDRY_API_KEY: "test-key",
      },
      "mock",
    ],
    [
      "requires AI_FOUNDRY_ENDPOINT",
      {
        COCKPIT_MODE: "live",
        COCKPIT_ALLOW_LIVE: "1",
        AI_FOUNDRY_API_KEY: "test-key",
      },
      "mock",
    ],
    [
      "requires AI_FOUNDRY_API_KEY",
      {
        COCKPIT_MODE: "live",
        COCKPIT_ALLOW_LIVE: "1",
        AI_FOUNDRY_ENDPOINT: foundryEndpoint,
      },
      "mock",
    ],
    [
      "enables live only when all guards are present",
      {
        COCKPIT_MODE: "live",
        COCKPIT_ALLOW_LIVE: "1",
        AI_FOUNDRY_ENDPOINT: foundryEndpoint,
        AI_FOUNDRY_API_KEY: "test-key",
      },
      "live",
    ],
  ])("%s", (_name, env, expected) => {
    expect(resolveAiMode(env as NodeJS.ProcessEnv)).toBe(expected);
  });

  it("reports only endpoint configuration and endpoint host", () => {
    const env = {
      AI_FOUNDRY_ENDPOINT: foundryEndpoint,
      AI_FOUNDRY_API_KEY: "secret-test-key",
    } as NodeJS.ProcessEnv;

    expect(isAiEndpointConfigured(env)).toBe(true);
    expect(resolveAiEndpointHost(env)).toBe("demo.services.ai.azure.com");
    expect(resolveAiEndpointHost(env)).not.toContain("secret-test-key");
  });
});

describe("MockAiClient", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("is deterministic, returns grounded Korean markdown, performs no fetch, and reads no secret", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("fetch forbidden"));
    const env = { COCKPIT_MODE: "mock" } as NodeJS.ProcessEnv;
    Object.defineProperty(env, "AI_FOUNDRY_API_KEY", {
      get() {
        throw new Error("AI_FOUNDRY_API_KEY should not be read in mock mode");
      },
    });
    const client = createAiClient(env);

    const first = await client.ask("secret-key-in-question", "logical_reads = 999");
    const second = await client.ask("secret-key-in-question", "logical_reads = 999");

    expect(client).toBeInstanceOf(MockAiClient);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(first.answer).toContain("### AI 진단");
    expect(first.answer).toContain("dbo.leaderboard");
    expect(first.answer).toContain(
      "CREATE INDEX IX_leaderboard_rating ON dbo.leaderboard(season, rating DESC) INCLUDE(player_id, wins, losses)",
    );
    expect(first.answer).toBe(second.answer);
    expect(JSON.stringify(first)).not.toContain("secret-key-in-question");
  });
});

describe("LiveAiClient", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("posts exactly to AI_FOUNDRY_ENDPOINT using api-key auth by default", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(completionResponse());
    const client = new LiveAiClient({
      AI_FOUNDRY_ENDPOINT: foundryEndpoint,
      AI_FOUNDRY_API_KEY: "test-foundry-key",
      AI_FOUNDRY_DEPLOYMENT: "gpt-demo",
    } as NodeJS.ProcessEnv);

    const result = await client.ask("원인?", "DIAGNOSE OUTPUT");

    expect(result).toMatchObject({ mode: "live", mocked: false, model: "gpt-demo" });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const [url, init] = fetchSpy.mock.calls[0]!;
    expect(url).toBe(foundryEndpoint);
    expect((init as RequestInit).method).toBe("POST");
    expect((init as RequestInit).headers).toMatchObject({
      "Content-Type": "application/json",
      "api-key": "test-foundry-key",
    });
    expect((init as RequestInit).headers).not.toHaveProperty("authorization");
    const body = JSON.parse((init as RequestInit).body as string);
    expect(body).toMatchObject({
      model: "gpt-demo",
      max_completion_tokens: 2000,
    });
    expect(body).not.toHaveProperty("max_tokens");
    expect(body).not.toHaveProperty("stream");
    expect(body).not.toHaveProperty("temperature");
    expect(body).not.toHaveProperty("reasoning_effort");
    expect(body).not.toHaveProperty("keep_alive");
    expect(body.messages[1].content).toContain("DIAGNOSE OUTPUT");
  });

  it("includes optional temperature and max completion token overrides", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(completionResponse());
    const client = new LiveAiClient({
      AI_FOUNDRY_ENDPOINT: foundryEndpoint,
      AI_FOUNDRY_API_KEY: "test-foundry-key",
      AI_FOUNDRY_DEPLOYMENT: "gpt-demo",
      AI_FOUNDRY_TEMPERATURE: "0.5",
      AI_FOUNDRY_MAX_COMPLETION_TOKENS: "1234",
    } as NodeJS.ProcessEnv);

    await client.ask("원인?", "DIAGNOSE OUTPUT");

    const [, init] = fetchSpy.mock.calls[0]!;
    const body = JSON.parse((init as RequestInit).body as string);
    expect(body).toMatchObject({
      model: "gpt-demo",
      max_completion_tokens: 1234,
      temperature: 0.5,
    });
    expect(body).not.toHaveProperty("max_tokens");
    expect(body).not.toHaveProperty("stream");
  });

  it("includes optional reasoning effort when configured", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(completionResponse());
    const client = new LiveAiClient({
      AI_FOUNDRY_ENDPOINT: foundryEndpoint,
      AI_FOUNDRY_API_KEY: "test-foundry-key",
      AI_FOUNDRY_DEPLOYMENT: "gpt-demo",
      AI_FOUNDRY_REASONING_EFFORT: "low",
    } as NodeJS.ProcessEnv);

    await client.ask("원인?", "DIAGNOSE OUTPUT");

    const [, init] = fetchSpy.mock.calls[0]!;
    const body = JSON.parse((init as RequestInit).body as string);
    expect(body).toMatchObject({
      model: "gpt-demo",
      max_completion_tokens: 2000,
      reasoning_effort: "low",
    });
  });

  it("omits invalid reasoning effort values", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(completionResponse());
    const client = new LiveAiClient({
      AI_FOUNDRY_ENDPOINT: foundryEndpoint,
      AI_FOUNDRY_API_KEY: "test-foundry-key",
      AI_FOUNDRY_DEPLOYMENT: "gpt-demo",
      AI_FOUNDRY_REASONING_EFFORT: "turbo",
    } as NodeJS.ProcessEnv);

    await client.ask("원인?", "DIAGNOSE OUTPUT");

    const [, init] = fetchSpy.mock.calls[0]!;
    const body = JSON.parse((init as RequestInit).body as string);
    expect(body).not.toHaveProperty("reasoning_effort");
  });

  it("uses bearer auth only when AI_FOUNDRY_AUTH=bearer", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(completionResponse());
    const client = new LiveAiClient({
      AI_FOUNDRY_ENDPOINT: foundryEndpoint,
      AI_FOUNDRY_API_KEY: "test-foundry-key",
      AI_FOUNDRY_DEPLOYMENT: "gpt-demo",
      AI_FOUNDRY_AUTH: "bearer",
    } as NodeJS.ProcessEnv);

    await client.ask("원인?", "DIAGNOSE OUTPUT");

    const [, init] = fetchSpy.mock.calls[0]!;
    expect((init as RequestInit).headers).toMatchObject({
      authorization: "Bearer test-foundry-key",
    });
    expect((init as RequestInit).headers).not.toHaveProperty("api-key");
  });

  it("throws clean failures without exposing the key", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(new Response("nope", { status: 503 }));
    const client = new LiveAiClient({
      AI_FOUNDRY_ENDPOINT: foundryEndpoint,
      AI_FOUNDRY_API_KEY: "test-foundry-key",
      AI_FOUNDRY_DEPLOYMENT: "gpt-demo",
    } as NodeJS.ProcessEnv);

    await expect(client.ask("원인?", "DIAGNOSE OUTPUT")).rejects.toThrow(
      "Azure AI Foundry request failed with HTTP 503",
    );
    await expect(client.ask("원인?", "DIAGNOSE OUTPUT")).rejects.not.toThrow("test-foundry-key");
  });
});

describe("POST /api/ai/ask", () => {
  let server: Server;
  let base: string;
  const manifest = loadManifest();

  beforeAll(async () => {
    const aiClient: AiClient = new MockAiClient();
    const app = createApp({
      manifest,
      runner: new MockRunner(),
      aiClient,
    });
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

  it("returns a mock AI diagnosis without outbound model calls", async () => {
    const res = await fetch(`${base}/api/ai/ask`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        demoId: "A",
        question: "랭킹 조회가 느려요, 원인과 해결책은?",
        contextText: "missing index recommendation: IX_leaderboard_rating",
      }),
    });

    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.mode).toBe("mock");
    expect(body.mocked).toBe(true);
    expect(body.answer).toEqual(expect.any(String));
    expect(body.answer.length).toBeGreaterThan(0);
  });

  it("rejects invalid ask bodies with 400", async () => {
    const res = await fetch(`${base}/api/ai/ask`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A", question: "" }),
    });

    expect(res.status).toBe(400);
  });

  it("returns 502 when the AI client fails", async () => {
    const app = createApp({
      manifest,
      runner: new MockRunner(),
      aiClient: {
        mode: "live",
        ask: vi.fn().mockRejectedValue(new Error("endpoint unavailable")),
      },
    });
    const localServer = await new Promise<Server>((resolve) => {
      const listening = app.listen(0, () => resolve(listening));
    });
    const { port } = localServer.address() as AddressInfo;

    try {
      const res = await fetch(`http://127.0.0.1:${port}/api/ai/ask`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ demoId: "A", question: "원인?", contextText: "evidence" }),
      });
      expect(res.status).toBe(502);
      expect(await res.json()).toEqual({
        error: "AI diagnosis unavailable: endpoint unavailable",
      });
    } finally {
      await new Promise<void>((resolve) => localServer.close(() => resolve()));
    }
  });

  it("never executes SQL or calls the runner from /api/ai/ask", async () => {
    const runner: Runner = {
      mode: "live",
      run: vi.fn().mockRejectedValue(new Error("SQL execution forbidden")),
    };
    const aiClient: AiClient = {
      mode: "mock",
      ask: vi.fn().mockResolvedValue({
        answer: "safe mock answer",
        model: "mock-foundry",
        latencyMs: 0,
        mode: "mock",
        mocked: true,
      }),
    };
    const app = createApp({ manifest, runner, aiClient });
    const localServer = await new Promise<Server>((resolve) => {
      const listening = app.listen(0, () => resolve(listening));
    });
    const { port } = localServer.address() as AddressInfo;

    try {
      const res = await fetch(`http://127.0.0.1:${port}/api/ai/ask`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ demoId: "A", question: "원인?", contextText: "evidence" }),
      });
      expect(res.status).toBe(200);
      expect(runner.run).not.toHaveBeenCalled();
      expect(aiClient.ask).toHaveBeenCalledWith("원인?", "evidence");
    } finally {
      await new Promise<void>((resolve) => localServer.close(() => resolve()));
    }
  });

  it("exposes AI health fields without the key or full endpoint URL", async () => {
    const previous = {
      AI_FOUNDRY_ENDPOINT: process.env.AI_FOUNDRY_ENDPOINT,
      AI_FOUNDRY_API_KEY: process.env.AI_FOUNDRY_API_KEY,
      AI_FOUNDRY_DEPLOYMENT: process.env.AI_FOUNDRY_DEPLOYMENT,
    };
    process.env.AI_FOUNDRY_ENDPOINT = foundryEndpoint;
    process.env.AI_FOUNDRY_API_KEY = "health-secret-key";
    process.env.AI_FOUNDRY_DEPLOYMENT = "health-model";

    const app = createApp({ manifest, runner: new MockRunner(), aiClient: new MockAiClient() });
    const localServer = await new Promise<Server>((resolve) => {
      const listening = app.listen(0, () => resolve(listening));
    });
    const { port } = localServer.address() as AddressInfo;

    try {
      const res = await fetch(`http://127.0.0.1:${port}/api/health`);
      const body = await res.json();
      const serialized = JSON.stringify(body);
      expect(body).toMatchObject({
        aiMode: "mock",
        aiModel: "health-model",
        aiEndpointConfigured: true,
      });
      expect(serialized).not.toContain("health-secret-key");
      expect(serialized).not.toContain(foundryEndpoint);
    } finally {
      for (const [key, value] of Object.entries(previous)) {
        if (value === undefined) {
          delete process.env[key];
        } else {
          process.env[key] = value;
        }
      }
      await new Promise<void>((resolve) => localServer.close(() => resolve()));
    }
  });
});
