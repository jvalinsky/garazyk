/** Run progress island — live progress bar, elapsed time, and activity indicator. @module RunProgress */
import { useEffect, useState } from "preact/hooks";
import { useRuntime } from "../runtime.ts";

/** Props for the RunProgress component. */
interface RunProgressProps {
  runId: string;
  startedAt: number;
  status: string;
  totalScenarios?: number;
  completedScenarios?: number;
  agentMode?: boolean;
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
export default function RunProgress(
  { runId, startedAt, status, totalScenarios = 0, completedScenarios = 0, agentMode = false }:
    RunProgressProps,
) {
  const { state, dispatch } = useRuntime();
  const progress = state.value.runs.progressByRunId[runId];
  const startedAtMs = startedAt < 10_000_000_000 ? startedAt * 1000 : startedAt;
  const isActive = status === "running" || status === "starting" ||
    status === "stopping";

  const [elapsed, setElapsed] = useState(() => Date.now() - startedAtMs);
  const [secondsSinceUpdate, setSecondsSinceUpdate] = useState(0);

  useEffect(() => {
    dispatch({ type: "runs/viewRun", runId });
  }, [runId]);

  useEffect(() => {
    if (!isActive) return;
    const tick = setInterval(() => {
      const now = Date.now();
      setElapsed(now - startedAtMs);
      if (progress?.updatedAt) {
        setSecondsSinceUpdate(Math.floor((now - progress.updatedAt) / 1000));
      }
    }, 1000);
    return () => clearInterval(tick);
  }, [startedAtMs, isActive, progress?.updatedAt]);

  if (!isActive) return null;

  const level = staleLevel(secondsSinceUpdate);
  const total = Math.max(0, progress?.total ?? totalScenarios);
  const completed = total > 0
    ? Math.max(0, Math.min(progress?.completed ?? completedScenarios, total))
    : 0;
  const remaining = Math.max(0, total - completed);
  const pct = total > 0 ? Math.round((completed / total) * 100) : 0;
  const statusLabel = status === "starting"
    ? "Starting"
    : status === "stopping"
    ? "Stopping"
    : "Running";
  const currentScenario = progress?.currentScenario
    ? `${
      progress.currentScenarioId ? `${progress.currentScenarioId}: ` : ""
    }${progress.currentScenario}`
    : null;

  return (
    <div class="run-progress">
      <div class="run-progress-header">
        <div>
          <div class="run-progress-kicker">Run progress</div>
          <div class="run-progress-title">
            {total > 0 ? `${remaining} scenarios left` : "Preparing scenarios"}
          </div>
        </div>
        <div class="run-progress-meta">
          {agentMode && <span class="run-progress-agent-badge">Agent</span>}
          <span class="run-progress-status">{statusLabel}</span>
          <span class="run-progress-elapsed">
            {formatElapsedShort(elapsed)}
          </span>
        </div>
      </div>

      <div
        class="run-progress-bar-track"
        role="progressbar"
        aria-label="Scenario run progress"
        aria-valuemin={0}
        aria-valuemax={total}
        aria-valuenow={completed}
      >
        <div
          class="run-progress-bar-fill"
          style={{ width: `${pct}%` }}
        />
      </div>

      <div class="run-progress-body">
        {progress?.exists && total > 0
          ? (
            <div class="run-progress-scenario">
              {completed}/{total} complete
              {currentScenario ? ` - ${currentScenario}` : ""}
            </div>
          )
          : (
            <div class="run-progress-scenario run-progress-muted">
              Waiting for the first scenario update
            </div>
          )}

        <div class={`run-progress-activity run-progress-activity--${level}`}>
          <span class="run-progress-dot" />
          {secondsSinceUpdate > 0
            ? `Last activity: ${
              formatElapsedShort(secondsSinceUpdate * 1000)
            } ago`
            : "Waiting for activity..."}
        </div>
      </div>
    </div>
  );
}
