import { useEffect } from "preact/hooks";

interface RunPollerProps {
  runId: string;
  status: string;
}

export default function RunPoller({ runId, status }: RunPollerProps) {
  useEffect(() => {
    if (status !== "running") return;

    const pollInterval = setInterval(async () => {
      try {
        const res = await fetch(`/api/runs/${runId}`);
        const data = await res.json();
        if (data.status !== "running") {
          clearInterval(pollInterval);
          window.location.reload();
        }
      } catch (e) {
        console.error("Poll failed:", e);
      }
    }, 3000);

    return () => clearInterval(pollInterval);
  }, [runId, status]);

  if (status !== "running") return null;

  return (
    <div class="badge badge-warning" style="margin-bottom: var(--space-lg);">
      ⟳ Run in progress — auto-refreshing every 3s…
    </div>
  );
}
