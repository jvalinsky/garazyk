/** Run progress island — live progress bar, elapsed time, and activity indicator. @module RunProgress */
import { useEffect, useState } from "preact/hooks";
import { useRuntime } from "../runtime.ts";

/** Props for the RunProgress component. */
interface RunProgressProps {
  runId: string;
  startedAt: number;
  status: string;
}

/** Format ms as a short human-readable elapsed time. */
function formatElapsedShort(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  if (totalSec < 60) return `${totalSec}s`;
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m}m ${s}s`;
}

/** Categorize staleness of last activity update. */
function staleLevel(secondsSinceUpdate: number): "active" | "slow" | "stale" {
  if (secondsSinceUpdate < 30) return "active";
  if (secondsSinceUpdate < 90) return "slow";
  return "stale";
}

/** RunProgress island for live progress, elapsed time, and activity indicator. */
export default function RunProgress({ runId, startedAt, status }: RunProgressProps) {
  const { state, dispatch } = useRuntime();
  const progress = state.value.runs.progressByRunId[runId];
  const startedAtMs = startedAt < 10_000_000_000 ? startedAt * 1000 : startedAt;

  const [elapsed, setElapsed] = useState(() => Date.now() - startedAtMs);
  const [secondsSinceUpdate, setSecondsSinceUpdate] = useState(0);

  useEffect(() => {
    dispatch({ type: "runs/viewRun", runId });
  }, [runId]);

  useEffect(() => {
    if (status !== "running") return;
    const tick = setInterval(() => {
      const now = Date.now();
      setElapsed(now - startedAtMs);
      if (progress?.updatedAt) {
        setSecondsSinceUpdate(Math.floor((now - progress.updatedAt) / 1000));
      }
    }, 1000);
    return () => clearInterval(tick);
  }, [startedAtMs, status, progress?.updatedAt]);

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
