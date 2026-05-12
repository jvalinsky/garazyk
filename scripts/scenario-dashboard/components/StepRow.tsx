interface StepRowProps {
  name: string;
  status: "passed" | "failed" | "skipped";
  detail?: string;
  durationMs?: number;
}

const STATUS_ICONS: Record<string, string> = {
  passed: "✓",
  failed: "✗",
  skipped: "⚠",
};

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

export default function StepRow({ name, status, detail, durationMs }: StepRowProps) {
  return (
    <>
      <div class="step-row">
        <span class={`step-icon ${status}`}>{STATUS_ICONS[status]}</span>
        <span class="step-name">{name}</span>
        <span class="step-duration">{durationMs ? formatDuration(durationMs) : ""}</span>
      </div>
      {detail && <div class="step-detail">{detail}</div>}
    </>
  );
}
