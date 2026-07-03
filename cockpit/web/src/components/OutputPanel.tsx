import { Terminal, CheckCircle2, XCircle, Clock } from "lucide-react";
import type { RunResult } from "@/lib/api";
import { Badge } from "@/components/ui/badge";

interface Props {
  result: RunResult | null;
  error: string | null;
}

export function OutputPanel({ result, error }: Props) {
  return (
    <div className="flex h-full flex-col rounded-lg border bg-card">
      <div className="flex items-center gap-2 border-b px-4 py-2.5">
        <Terminal className="h-4 w-4 text-muted-foreground" />
        <span className="text-sm font-semibold">출력 · Output</span>
        {result && (
          <div className="ml-auto flex items-center gap-2">
            <Badge variant={result.exitCode === 0 ? "secondary" : "destructive"} className="gap-1">
              {result.exitCode === 0 ? (
                <CheckCircle2 className="h-3 w-3" />
              ) : (
                <XCircle className="h-3 w-3" />
              )}
              exit {result.exitCode}
            </Badge>
            <Badge variant="outline" className="gap-1">
              <Clock className="h-3 w-3" />
              {result.durationMs}ms
            </Badge>
            {result.mocked && <Badge variant="secondary">mock</Badge>}
          </div>
        )}
      </div>
      <div className="min-h-0 flex-1 overflow-auto p-4">
        {error && <pre className="whitespace-pre-wrap text-sm text-destructive">{error}</pre>}
        {!error && !result && (
          <p className="text-sm text-muted-foreground">
            스텝의 <span className="font-medium">실행</span> 버튼을 눌러 결과를 확인하세요.
          </p>
        )}
        {result && (
          <div className="space-y-3">
            <div className="font-mono text-xs text-muted-foreground">
              <span className="text-foreground">$</span> {result.command}
            </div>
            <pre className="whitespace-pre-wrap rounded-md bg-black/40 p-3 font-mono text-xs leading-relaxed">
              {result.stdout || "(no output)"}
            </pre>
            {result.stderr && (
              <pre className="whitespace-pre-wrap rounded-md bg-destructive/10 p-3 font-mono text-xs text-destructive">
                {result.stderr}
              </pre>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
