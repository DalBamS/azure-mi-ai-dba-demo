import { useState } from "react";
import { Loader2, Play, ShieldAlert, FileText } from "lucide-react";
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

interface Props {
  step: Step;
  running: boolean;
  active: boolean;
  onRun: (step: Step) => void;
}

export function StepItem({ step, running, active, onRun }: Props) {
  const [confirmOpen, setConfirmOpen] = useState(false);

  const runNow = () => {
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
      </div>
      <Button
        size="sm"
        variant={step.destructive ? "destructive" : step.manual ? "secondary" : "default"}
        disabled={running}
        onClick={runNow}
      >
        {running ? (
          <Loader2 className="h-3.5 w-3.5 animate-spin" />
        ) : (
          <Play className="h-3.5 w-3.5" />
        )}
        {step.manual ? "열기" : "실행"}
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
