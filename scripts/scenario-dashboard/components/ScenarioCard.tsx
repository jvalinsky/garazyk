import { ScenarioStatus } from "../services/types.ts";
import { STATUS_ICONS } from "../utils.ts";

interface ScenarioCardProps {
  id: string;
  name: string;
  status?: ScenarioStatus | null;
  passed?: number;
  failed?: number;
  skipped?: number;
  runId?: string;
}

export default function ScenarioCard(
  { id, name, status, passed = 0, failed = 0, skipped = 0, runId }: ScenarioCardProps,
) {
  const icon = status ? STATUS_ICONS[status] || "?" : "";
  const href = runId ? `/scenario/${id}?runId=${runId}` : `/scenario/${id}`;
  const badgeVariant = status === "passed" ? "success"
                     : status === "failed" ? "destructive"
                     : status === "running" ? "info"
                     : "secondary";

  return (
    <a href={href} class="scenario-card">
      <div class="card-id">{id}</div>
      <div class="card-name">{name}</div>
      {status && (
        <div class={`card-status badge badge-${badgeVariant}`}>
          {icon} {status}
        </div>
      )}
      {(passed + failed + skipped) > 0 && (
        <div style="font-size: var(--font-size-xs); color: var(--color-text-tertiary); margin-top: var(--space-xs);">
          {passed}✓ {failed}✗ {skipped}⚠
        </div>
      )}
    </a>
  );
}
