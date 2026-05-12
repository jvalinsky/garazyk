interface ScenarioCardProps {
  id: string;
  name: string;
  status?: "passed" | "failed" | "skipped" | "running" | null;
  passed?: number;
  failed?: number;
  skipped?: number;
}

const STATUS_ICONS: Record<string, string> = {
  passed: "✓",
  failed: "✗",
  skipped: "⚠",
  running: "⟳",
};

export default function ScenarioCard(
  { id, name, status, passed = 0, failed = 0, skipped = 0 }: ScenarioCardProps,
) {
  const icon = status ? STATUS_ICONS[status] || "?" : "";

  return (
    <a href={`/scenario/${id}`} class="scenario-card">
      <div class="card-id">{id}</div>
      <div class="card-name">{name}</div>
      {status && (
        <div class={`card-status badge badge-${status === "passed" ? "success" : status === "failed" ? "destructive" : "warning"}`}>
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
