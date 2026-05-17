/** Run history table component — shows recent runs with results. @module RunHistory */
import { Run } from "../services/types.ts";
import { formatDate, formatDurationSec } from "../utils.ts";

/** Props for the RunHistory component. */
interface RunHistoryProps {
  runs: Run[];
}

/** Render a table of past runs with timing and pass/fail/skip counts. */
export default function RunHistory({ runs }: RunHistoryProps) {
  if (runs.length === 0) {
    return (
      <div class="card" style="margin-bottom: var(--space-xl);">
        <div class="card-header">
          <h2 class="card-title">Run History</h2>
        </div>
        <div
          class="card-body"
          style="text-align: center; color: var(--color-text-secondary); padding: var(--space-2xl);"
        >
          No runs recorded yet.
        </div>
      </div>
    );
  }

  return (
    <div class="card" style="margin-bottom: var(--space-xl);">
      <div class="card-header">
        <h2 class="card-title">Run History</h2>
      </div>
      <div class="card-body" style="padding: 0;">
        <table class="history-table">
          <thead>
            <tr>
              <th>Time</th>
              <th>Run ID</th>
              <th>Results</th>
              <th>Duration</th>
            </tr>
          </thead>
          <tbody>
            {runs.map((r) => (
              <tr key={r.id}>
                <td>{formatDate(r.startedAt)}</td>
                <td>
                  <a
                    href={`/run/${r.id}`}
                    style="color: var(--color-accent); text-decoration: none;"
                  >
                    {r.id}
                  </a>
                </td>
                <td>
                  <span style="color: var(--color-success);">{r.passed}✓</span>{" "}
                  {r.failed > 0 && <span style="color: var(--color-destructive);">{r.failed}✗
                  </span>}{" "}
                  {r.skipped > 0 && <span style="color: var(--color-warning);">{r.skipped}⚠</span>}
                </td>
                <td>{r.durationS ? formatDurationSec(r.durationS) : "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
