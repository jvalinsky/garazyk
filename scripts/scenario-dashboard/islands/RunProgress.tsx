import { useState, useEffect } from "preact/hooks";
import { useRuntime } from "../runtime.ts";

interface RunProgressProps {
  runId: string;
  startedAt: number;
  status: string;
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
  const { state } = useRuntime();
  const progress = state.value.runs.progress;

  const [elapsed, setElapsed] = useState(() => Date.now() - startedAt * 1000);
  const [secondsSinceUpdate, setSecondsSinceUpdate] = useState(0);

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
