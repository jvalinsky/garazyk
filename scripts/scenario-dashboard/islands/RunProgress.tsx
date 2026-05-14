import { useState, useEffect } from "preact/hooks";

interface RunProgressProps {
  runId: string;
  startedAt: number;
  status: string;
}

interface ProgressData {
  exists: boolean;
  runId: string;
  total: number;
  completed: number;
  currentScenario: string | null;
  currentScenarioId: string | null;
  elapsedMs: number;
  updatedAt: number;
  now: number;
  running: boolean;
}

function formatElapsed(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  if (totalSec < 60) return `${totalSec}s`;
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  if (m < 60) return `${m}m ${s}s`;
  const h = Math.floor(m / 60);
  const rm = m % 60;
  return `${h}h ${rm}m`;
}

function formatElapsedShort(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  if (totalSec < 60) return `${totalSec}s`;
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m}m ${s}s`;
}

function staleLevel(secondsSinceUpdate: number): "active" | "slow" | "stale" {
  if (secondsSinceUpdate < 30) return "active";
  if (secondsSinceUpdate < 90) return "slow";
  return "stale";
}

export default function RunProgress({ runId, startedAt, status }: RunProgressProps) {
  const [progress, setProgress] = useState<ProgressData | null>(null);
  const [elapsed, setElapsed] = useState(() => Date.now() - startedAt * 1000);
  const [secondsSinceUpdate, setSecondsSinceUpdate] = useState(0);

  // Poll progress endpoint
  useEffect(() => {
    if (status !== "running") return;

    const poll = async () => {
      try {
        const res = await fetch(`/api/runs/${runId}/progress`);
        if (res.ok) {
          const data: ProgressData = await res.json();
          setProgress(data);
        }
      } catch {
        // ignore
      }
    };

    poll();
    const interval = setInterval(poll, 3000);
    return () => clearInterval(interval);
  }, [runId, status]);

  // Poll run status for completion detection
  useEffect(() => {
    if (status !== "running") return;

    const poll = async () => {
      try {
        const res = await fetch(`/api/runs/${runId}`);
        const data = await res.json();
        if (data.status !== "running") {
          window.location.reload();
        }
      } catch {
        // ignore
      }
    };

    const interval = setInterval(poll, 3000);
    return () => clearInterval(interval);
  }, [runId, status]);

  // Update elapsed time and staleness every second
  useEffect(() => {
    if (status !== "running") return;

    const tick = setInterval(() => {
      const now = Date.now();
      setElapsed(now - startedAt * 1000);
      if (progress?.updatedAt) {
        setSecondsSinceUpdate(Math.floor((now - progress.updatedAt) / 1000));
      }
    }, 1000);

    return () => clearInterval(tick);
  }, [startedAt, status, progress?.updatedAt]);

  if (status !== "running") return null;

  const level = staleLevel(secondsSinceUpdate);
  const pct = progress && progress.total > 0
    ? Math.round((progress.completed / progress.total) * 100)
    : 0;

  return (
    <div class="run-progress">
      <div class="run-progress-header">
        <span class="run-progress-status">
          <span class="run-progress-spinner">⟳</span>
          Running
        </span>
        <span class="run-progress-elapsed">{formatElapsedShort(elapsed)}</span>
      </div>

      <div class="run-progress-bar-track">
        <div
          class="run-progress-bar-fill"
          style={{ width: `${pct}%` }}
        />
      </div>

      <div class="run-progress-body">
        {progress?.exists && progress.total > 0
          ? (
            <div class="run-progress-scenario">
              Scenario {Math.min(progress.completed + 1, progress.total)}
              /{progress.total}: {progress.currentScenario ?? "..."}
            </div>
          )
          : (
            <div class="run-progress-scenario run-progress-muted">
              Starting...
            </div>
          )}

        <div class={`run-progress-activity run-progress-activity--${level}`}>
          <span class="run-progress-dot" />
          {secondsSinceUpdate > 0
            ? `Last activity: ${formatElapsedShort(secondsSinceUpdate * 1000)} ago`
            : "Waiting for activity..."}
        </div>
      </div>
    </div>
  );
}
