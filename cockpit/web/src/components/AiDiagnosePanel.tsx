import { useEffect, useMemo, useState } from "react";
import { BrainCircuit } from "lucide-react";
import { api, type AiResult, type Demo, type RunResult } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface Props {
  demo: Demo;
  latestResult: RunResult | null;
}

const FALLBACK_HINT =
  "방금 실행한 diagnose/evidence 출력만 근거로 원인과 사람이 검토할 해결책을 설명해 주세요.";

function contextFromResult(demo: Demo, result: RunResult | null): string {
  if (!result || result.demoId !== demo.id) return "";
  return [
    `demoId: ${result.demoId}`,
    `stepId: ${result.stepId}`,
    `exitCode: ${result.exitCode}`,
    "STDOUT:",
    result.stdout || "(empty)",
    ...(result.stderr ? ["", "STDERR:", result.stderr] : []),
  ].join("\n");
}

export function AiDiagnosePanel({ demo, latestResult }: Props) {
  const [question, setQuestion] = useState(demo.aiHint ?? FALLBACK_HINT);
  const [answer, setAnswer] = useState<AiResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const contextText = useMemo(() => contextFromResult(demo, latestResult), [demo, latestResult]);

  useEffect(() => {
    setQuestion(demo.aiHint ?? FALLBACK_HINT);
    setAnswer(null);
    setError(null);
  }, [demo.id, demo.aiHint]);

  const askAi = async () => {
    const trimmed = question.trim();
    if (!trimmed) return;
    setLoading(true);
    setError(null);
    try {
      setAnswer(await api.ask(demo.id, trimmed, contextText));
    } catch (e) {
      setError((e as Error).message);
      setAnswer(null);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader className="space-y-2">
        <div className="flex items-center gap-2">
          <BrainCircuit className="h-4 w-4 text-primary" />
          <CardTitle className="text-sm">AI 진단 (SLM)</CardTitle>
          <Badge variant={contextText ? "secondary" : "outline"} className="ml-auto">
            {contextText ? "최근 출력 포함" : "진단 출력 없음"}
          </Badge>
        </div>
        <p className="text-xs text-muted-foreground">
          읽기전용 AI 진단 · 제안된 DDL은 사람이 검토·승인 후 적용
        </p>
      </CardHeader>
      <CardContent className="space-y-3">
        <textarea
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          className="min-h-20 w-full rounded-md border bg-background p-3 text-sm outline-none focus:ring-2 focus:ring-ring"
          placeholder="진단 질문을 입력하세요."
        />
        {!contextText && (
          <p className="text-xs text-muted-foreground">
            정확한 답변을 위해 먼저 diagnose/evidence 스텝을 실행한 뒤 물어보세요.
          </p>
        )}
        <div className="flex items-center gap-2">
          <Button onClick={askAi} disabled={loading || !question.trim()} size="sm">
            {loading ? "질문 중..." : "물어보기"}
          </Button>
          {answer && (
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant="outline">{answer.model}</Badge>
              <Badge variant="outline">{answer.latencyMs}ms</Badge>
              <Badge variant={answer.mode === "live" ? "destructive" : "secondary"}>
                {answer.mode}
              </Badge>
            </div>
          )}
        </div>
        {error && <pre className="whitespace-pre-wrap text-xs text-destructive">{error}</pre>}
        {answer && (
          <div className="rounded-md border bg-muted/30 p-3 text-sm leading-relaxed">
            <pre className="whitespace-pre-wrap font-sans">{answer.answerMarkdown}</pre>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
