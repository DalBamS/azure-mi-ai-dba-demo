import { useCallback, useEffect, useState } from "react";
import { Gauge, PlayCircle, FileCode2, AlertTriangle } from "lucide-react";
import {
  api,
  type Demo,
  type DemoSummary,
  type Health,
  type RunResult,
  type RunVariant,
  type Step,
} from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DemoSidebar } from "@/components/DemoSidebar";
import { StepItem } from "@/components/StepItem";
import { OutputPanel } from "@/components/OutputPanel";

export default function App() {
  const [health, setHealth] = useState<Health | null>(null);
  const [demos, setDemos] = useState<DemoSummary[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [demo, setDemo] = useState<Demo | null>(null);
  const [runningStep, setRunningStep] = useState<string | null>(null);
  const [result, setResult] = useState<RunResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [runVariant, setRunVariant] = useState<RunVariant>("pass");

  useEffect(() => {
    Promise.all([api.health(), api.demos()])
      .then(([h, d]) => {
        setHealth(h);
        setDemos(d);
        if (d.length > 0) setSelectedId(d[0].id);
      })
      .catch((e: Error) => setError(e.message));
  }, []);

  useEffect(() => {
    if (!selectedId) return;
    setDemo(null);
    api.demo(selectedId).then(setDemo).catch((e: Error) => setError(e.message));
  }, [selectedId]);

  const runStep = useCallback(
    async (step: Step) => {
      if (!demo) return;
      setRunningStep(step.id);
      setError(null);
      try {
        const res = await api.run(demo.id, step.id, runVariant);
        setResult(res);
      } catch (e) {
        setError((e as Error).message);
      } finally {
        setRunningStep(null);
      }
    },
    [demo, runVariant],
  );

  const runAllSafe = useCallback(async () => {
    if (!demo) return;
    const steps = demo.steps.filter((s) => !s.analysisOnly && !s.destructive && !s.manual);
    for (const step of steps) {
      setRunningStep(step.id);
      try {
        const res = await api.run(demo.id, step.id, runVariant);
        setResult(res);
      } catch (e) {
        setError((e as Error).message);
        break;
      }
    }
    setRunningStep(null);
  }, [demo, runVariant]);

  const live = health?.mode === "live";

  return (
    <div className="flex h-screen flex-col">
      <header className="flex items-center gap-3 border-b px-5 py-3">
        <Gauge className="h-6 w-6 text-primary" />
        <div>
          <h1 className="text-base font-semibold leading-tight">데모 조종석 · Demo Cockpit</h1>
          <p className="text-xs text-muted-foreground">Azure SQL MI · AI DBA 데모 오케스트레이션</p>
        </div>
        <div className="ml-auto flex items-center gap-2">
          {health && (
            <Badge variant={live ? "destructive" : "secondary"} className="gap-1">
              {live ? <AlertTriangle className="h-3 w-3" /> : null}
              {live ? "LIVE 모드" : "MOCK 모드"}
            </Badge>
          )}
          {health && <Badge variant="outline">{health.demos} demos</Badge>}
        </div>
      </header>

      <div className="grid min-h-0 flex-1 grid-cols-[minmax(240px,300px)_1fr]">
        <aside className="min-h-0 overflow-auto border-r p-3">
          <DemoSidebar demos={demos} selectedId={selectedId} onSelect={setSelectedId} />
        </aside>

        <main className="grid min-h-0 grid-rows-[1fr_minmax(180px,40%)] gap-4 p-4">
          <section className="min-h-0 overflow-auto">
            {demo ? (
              <div className="space-y-3">
                <div className="flex items-start gap-3">
                  <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-primary/15 text-sm font-bold text-primary">
                    {demo.id}
                  </div>
                  <div className="flex-1 space-y-2">
                    <h2 className="text-lg font-semibold">{demo.title}</h2>
                    <div className="mt-0.5 flex items-center gap-2 text-xs text-muted-foreground">
                      <Badge variant="outline">{demo.lifecycle}</Badge>
                      <span className="font-mono">{demo.path}</span>
                    </div>
                    {(demo.summary || demo.whyAi) && (
                      <div className="grid gap-2 rounded-lg border bg-muted/30 p-3 text-sm">
                        {demo.summary && (
                          <p>
                            <span className="font-semibold text-foreground">무엇을 보여주나: </span>
                            <span className="text-muted-foreground">{demo.summary}</span>
                          </p>
                        )}
                        {demo.whyAi && (
                          <p>
                            <span className="font-semibold text-foreground">왜 AI인가: </span>
                            <span className="text-muted-foreground">{demo.whyAi}</span>
                          </p>
                        )}
                      </div>
                    )}
                  </div>
                  <div className="flex shrink-0 flex-col items-end gap-2">
                    <label className="flex cursor-pointer items-center gap-2 rounded-md border px-3 py-2 text-xs">
                      <input
                        type="checkbox"
                        checked={runVariant === "fail"}
                        onChange={(e) => setRunVariant(e.target.checked ? "fail" : "pass")}
                        className="h-4 w-4 accent-destructive"
                      />
                      <span>회귀 시나리오(FAIL 재현)</span>
                    </label>
                    <Button variant="outline" size="sm" onClick={runAllSafe} disabled={!!runningStep}>
                      <PlayCircle className="h-4 w-4" /> 안전 스텝 일괄 실행
                    </Button>
                  </div>
                </div>

                <div className="space-y-1.5">
                  {demo.steps.map((step) => (
                    <StepItem
                      key={step.id}
                      step={step}
                      running={runningStep === step.id}
                      active={result?.stepId === step.id}
                      onRun={runStep}
                    />
                  ))}
                </div>
              </div>
            ) : (
              <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
                <FileCode2 className="mr-2 h-4 w-4" /> 데모를 선택하세요.
              </div>
            )}
          </section>

          <OutputPanel result={result} error={error} />
        </main>
      </div>
    </div>
  );
}
