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
      <div class="card run-history-card">
        <div class="card-header">
          <h2 class="card-title">Run History</h2>
        </div>
        <div class="card-body run-history-empty">
          No runs recorded yet.
        </div>
      </div>
    );
  }

  return (
    <div class="card run-history-card">
      <div class="card-header">
        <h2 class="card-title">Run History</h2>
      </div>
      <div class="card-body run-history-body">
        <table class="history-table">
          <caption class="sr-only">
            Recent scenario runs with timing and results
          </caption>
          <thead>
            <tr>
              <th scope="col">Time</th>
              <th scope="col">Run ID</th>
              <th scope="col">Flags</th>
              <th scope="col">Results</th>
              <th scope="col">Duration</th>
            </tr>
          </thead>
          <tbody>
            {runs.map((r) => (
              <tr key={r.id}>
                <td>{formatDate(r.startedAt)}</td>
                <td>
                  <a href={`/run/${r.id}`} class="run-history-link">
                    {r.id}
                  </a>
                </td>
                <td>
                  <div class="run-history-flags">
                    {r.agentMode && (
                      <span class="badge badge-secondary">Agent</span>
                    )}
                    {r.runner && r.runner !== "host" && (
                      <span class="badge badge-info">{r.runner}</span>
                    )}
                    {r.pds2 && <span class="badge badge-info">PDS2</span>}
                    {r.binaryMode && (
                      <span class="badge badge-secondary">binary</span>
                    )}
                  </div>
                </td>
                <td>
                  <span class="result-passed">{r.passed} passed</span>{" "}
                  {r.failed > 0 && (
                    <span class="result-failed">{r.failed} failed</span>
                  )}{" "}
                  {r.skipped > 0 && (
                    <span class="result-skipped">{r.skipped} skipped</span>
                  )}
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
