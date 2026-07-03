import type { DemoSummary, Lifecycle } from "@/lib/api";
import { cn } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";

const LIFECYCLE_ORDER: Lifecycle[] = ["runtime", "pre-prod", "cicd"];
const LIFECYCLE_LABEL: Record<Lifecycle, string> = {
  runtime: "운영 · Runtime",
  "pre-prod": "사전검증 · Pre-prod",
  cicd: "CI/CD",
};

interface Props {
  demos: DemoSummary[];
  selectedId: string | null;
  onSelect: (id: string) => void;
}

export function DemoSidebar({ demos, selectedId, onSelect }: Props) {
  return (
    <nav className="flex flex-col gap-4">
      {LIFECYCLE_ORDER.map((lifecycle) => {
        const group = demos.filter((d) => d.lifecycle === lifecycle);
        if (group.length === 0) return null;
        return (
          <div key={lifecycle}>
            <div className="mb-1.5 px-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              {LIFECYCLE_LABEL[lifecycle]}
            </div>
            <ul className="space-y-1">
              {group.map((demo) => {
                const active = demo.id === selectedId;
                return (
                  <li key={demo.id}>
                    <button
                      onClick={() => onSelect(demo.id)}
                      className={cn(
                        "flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm transition-colors",
                        active ? "bg-accent text-accent-foreground" : "hover:bg-accent/50",
                      )}
                    >
                      <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-primary/15 text-xs font-bold text-primary">
                        {demo.id}
                      </span>
                      <span className="flex-1 truncate">{demo.title}</span>
                      <Badge variant="outline" className="shrink-0">
                        {demo.stepCount}
                      </Badge>
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
        );
      })}
    </nav>
  );
}
