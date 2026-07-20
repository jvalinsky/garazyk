/** Trigger offline replay export for a run. @module ExportReplayButton */

interface ExportReplayButtonProps {
  runId: string;
}

/** Open exported replay HTML in a new tab (generates bundle on first request). */
export default function ExportReplayButton({ runId }: ExportReplayButtonProps) {
  const exportUrl = `/api/runs/${encodeURIComponent(runId)}/export`;

  return (
    <a
      href={exportUrl}
      target="_blank"
      rel="noopener noreferrer"
      class="btn btn-secondary btn-sm text-decoration-none"
    >
      Export replay
    </a>
  );
}
