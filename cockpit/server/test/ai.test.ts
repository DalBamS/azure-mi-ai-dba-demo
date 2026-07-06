import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { buildMessages } from "../src/ai/prompt.js";
import {
  DEFAULT_SLM_MODEL,
  LiveAiClient,
  MockAiClient,
  createAiClient,
  type AiClient,
} from "../src/ai/client.js";
import { createApp } from "../src/api/server.js";
import { loadManifest } from "../src/manifest/load.js";
import { MockRunner } from "../src/runner/index.js";

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

describe("MockAiClient", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("is deterministic, returns markdown, performs no fetch, and does not read SLM_API_KEY", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("fetch forbidden"));
    const env = { COCKPIT_MODE: "mock" } as NodeJS.ProcessEnv;
    Object.defineProperty(env, "SLM_API_KEY", {
      get() {
        throw new Error("SLM_API_KEY should not be read in mock mode");
      },
    });
    const client = createAiClient(env);

    const input = {
      demoId: "A",
      question: "secret-key-in-question",
      contextText: "logical_reads = 999",
    };
    const first = await client.ask(input);
    const second = await client.ask(input);

    expect(client).toBeInstanceOf(MockAiClient);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(first.answerMarkdown).toContain("### AI 진단");
    expect(first.answerMarkdown).toBe(second.answerMarkdown);
    expect(JSON.stringify(first)).not.toContain("secret-key-in-question");
  });
});

describe("LiveAiClient", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("uses qwen2.5 defaults and Ollama keep-alive request options", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(
        JSON.stringify({
          choices: [{ message: { content: "진단 결과" } }],
        }),
        { status: 200 },
      ),
    );
    const client = new LiveAiClient({
      COCKPIT_MODE: "live",
      COCKPIT_ALLOW_LIVE: "1",
      SLM_ENDPOINT: "http://127.0.0.1:11434/v1",
    });

    const result = await client.ask({
      demoId: "A",
      question: "랭킹 조회가 느려요",
      contextText: "table=dbo.leaderboard column=rating",
    });

    expect(result).toMatchObject({
      answerMarkdown: "진단 결과",
      model: DEFAULT_SLM_MODEL,
      mode: "live",
      mocked: false,
    });
    expect(fetchSpy).toHaveBeenCalledTimes(1);
    const [url, init] = fetchSpy.mock.calls[0]!;
    expect(url).toBe("http://127.0.0.1:11434/v1/chat/completions");
    expect(init?.signal).toBeInstanceOf(AbortSignal);
    expect(JSON.parse(init?.body as string)).toMatchObject({
      model: "qwen2.5:3b",
      stream: false,
      temperature: 0.2,
      max_tokens: 256,
      keep_alive: -1,
    });
  });
});

describe("POST /api/ai/ask", () => {
  let server: Server;
  let base: string;

  beforeAll(async () => {
    const aiClient: AiClient = new MockAiClient();
    const app = createApp({
      manifest: loadManifest(),
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
    expect(body.answerMarkdown).toEqual(expect.any(String));
    expect(body.answerMarkdown.length).toBeGreaterThan(0);
  });

  it("rejects invalid ask bodies with 400", async () => {
    const res = await fetch(`${base}/api/ai/ask`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ demoId: "A", question: "" }),
    });

    expect(res.status).toBe(400);
  });

  it("does not surface SLM_API_KEY in controlled mock answers", async () => {
    const secret = "slm-api-key-that-must-not-leak";
    process.env.SLM_API_KEY = secret;
    const client = new MockAiClient();

    try {
      const result = await client.ask({
        demoId: "M",
        question: secret,
        contextText: `audit token ${secret}`,
      });
      expect(JSON.stringify(result)).not.toContain(secret);
    } finally {
      delete process.env.SLM_API_KEY;
    }
  });
});
