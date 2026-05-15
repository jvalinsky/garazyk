import { ScenarioStatus } from "../services/types.ts";
import { STATUS_ICONS } from "../utils.ts";
import { topologyPreview } from "../signals.ts";

interface ScenarioCardProps {
  id: string;
  name: string;
  status?: ScenarioStatus | null;
  passed?: number;
  failed?: number;
  skipped?: number;
  runId?: string;
  requires?: string[];
  needsPds2?: boolean;
}

export default function ScenarioCard(
  { id, name, status, passed = 0, failed = 0, skipped = 0, runId, requires = [], needsPds2 = false }: ScenarioCardProps,
) {
  const icon = status ? STATUS_ICONS[status] || "?" : "";
  const href = runId ? `/scenario/${id}?runId=${runId}` : `/scenario/${id}`;
  
  // Check compatibility
  const preview = topologyPreview.value;
  const missing: string[] = [];
  
  if (preview) {
    if (needsPds2 && !preview.roles.includes("pds2")) {
      missing.push("pds2");
    }
    for (const req of requires) {
      if (!preview.capabilities.includes(req) && !preview.roles.includes(req.split(":")[0])) {
        // Simple check: if it's role:capability, check if either is present
        // (This is a bit simplified compared to the real logic)
        missing.push(req);
      }
    }
  }

  const isCompatible = missing.length === 0;

  const badgeVariant = status === "passed" ? "success"
                     : status === "failed" ? "destructive"
                     : status === "running" ? "info"
                     : "secondary";

  return (
    <a href={href} class={`scenario-card ${!isCompatible ? "incompatible" : ""}`}>
      <div class="card-id">{id}</div>
      <div class="card-name">{name}</div>
      
      {!isCompatible && (
        <div class="compatibility-warning" title={`Missing: ${missing.join(", ")}`}>
          ⚠️ Incompatible
        </div>
      )}

      {status && (
        <div class={`card-status badge badge-${badgeVariant}`}>
          {icon} {status}
        </div>
      )}
      {(passed + failed + skipped) > 0 && (
        <div style="font-size: var(--font-size-xs); color: var(--color-text-tertiary); margin-top: var(--space-xs);">
          {passed}✓ {failed}✗ {skipped}–
        </div>
      )}
    </a>
  );
}
