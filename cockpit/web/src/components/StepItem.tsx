import { useState } from "react";
import { Loader2, Play, ShieldAlert, FileText, RotateCcw } from "lucide-react";
import type { Step } from "@/lib/api";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

const KIND_STYLE: Record<Step["kind"], string> = {
  sql: "bg-sky-500/15 text-sky-400",
  ps1: "bg-violet-500/15 text-violet-400",
  py: "bg-amber-500/15 text-amber-400",
  md: "bg-zinc-500/15 text-zinc-400",
};

const ANALYSIS_ONLY_DESCRIPTION = "의도적으로 위험한 샘플 — AI 진단 대상, 실행 안 함";

interface Props {
  step: Step;
  running: boolean;
  active: boolean;
  onRun: (step: Step) => void;
}

export function StepItem({ step, running, active, onRun }: Props) {
  const [confirmOpen, setConfirmOpen] = useState(false);

  const runNow = () => {
    if (step.analysisOnly) return;
    if (step.destructive) setConfirmOpen(true);
    else onRun(step);
  };

  return (
    <div
      className={cn(
        "flex items-center gap-3 rounded-md border px-3 py-2",
        active ? "border-primary/60 bg-accent/40" : "border-border",
      )}
    >
      <span className="w-6 text-right text-xs tabular-nums text-muted-foreground">
        {step.order || "·"}
      </span>
      <span
        className={cn(
          "flex h-6 items-center rounded px-1.5 text-[10px] font-bold uppercase",
          KIND_STYLE[step.kind],
        )}
      >
        {step.kind}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="truncate text-sm font-medium">{step.title}</span>
          {step.analysisOnly && (
            <Badge className="gap-1 border-yellow-500/40 bg-yellow-500/15 text-yellow-300">
              <ShieldAlert className="h-3 w-3" /> 분석 전용
            </Badge>
          )}
          {step.injection && (
            <Badge className="gap-1 border-orange-500/40 bg-orange-500/15 text-orange-300">
              <ShieldAlert className="h-3 w-3" /> 이슈 주입
            </Badge>
          )}
          {step.injectionReset && (
            <Badge className="gap-1 border-emerald-500/40 bg-emerald-500/15 text-emerald-300">
              <RotateCcw className="h-3 w-3" /> 원복
            </Badge>
          )}
          {step.destructive && (
            <Badge variant="destructive" className="gap-1">
              <ShieldAlert className="h-3 w-3" /> 파괴적
            </Badge>
          )}
          {step.manual && (
            <Badge variant="secondary" className="gap-1">
              <FileText className="h-3 w-3" /> 수동
            </Badge>
          )}
        </div>
        <div className="truncate font-mono text-[11px] text-muted-foreground">{step.file}</div>
        {step.analysisOnly && (
          <div className="mt-0.5 text-xs text-yellow-300">{ANALYSIS_ONLY_DESCRIPTION}</div>
        )}
      </div>
      <Button
        size="sm"
        variant={step.analysisOnly || step.manual ? "secondary" : step.destructive ? "destructive" : "default"}
        disabled={running || step.analysisOnly}
        onClick={runNow}
      >
        {running ? (
          <Loader2 className="h-3.5 w-3.5 animate-spin" />
        ) : (
          <Play className="h-3.5 w-3.5" />
        )}
        {step.analysisOnly ? "실행 불가" : step.manual ? "열기" : "실행"}
      </Button>

      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <ShieldAlert className="h-5 w-5 text-destructive" /> 파괴적 스텝 확인
            </DialogTitle>
            <DialogDescription>
              <span className="font-mono">{step.file}</span> 는 스키마/데이터를 변경할 수 있는
              스텝입니다. 목(mock) 모드에서는 시뮬레이션만 되지만, 라이브 모드에서는 실제로
              적용됩니다. 계속하시겠습니까?
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setConfirmOpen(false)}>
              취소
            </Button>
            <Button
              variant="destructive"
              onClick={() => {
                setConfirmOpen(false);
                onRun(step);
              }}
            >
              실행
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
