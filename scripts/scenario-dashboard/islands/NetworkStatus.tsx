/** Network status island — displays ATProto service table with start/stop controls. @module NetworkStatus */
import { useRuntime } from "../runtime.ts";

/** Render the network services table with start/stop/start-pds2 buttons. */
export default function NetworkStatus() {
  const { state, dispatch } = useRuntime();
  const { services } = state.value.network;
  const busy = state.value.ux.busy;
  const runner = state.value.ux.runner;

  function startAll() {
    dispatch({ type: "network/startRequested", pds2: false, runner });
  }

  function startPds2() {
    dispatch({ type: "network/startRequested", pds2: true, runner });
  }

  function stopAll() {
    dispatch({ type: "network/stopRequested", runner });
  }

  return (
    <div class="card" style="margin-bottom: var(--space-xl);">
      <div class="card-header">
        <h2 class="card-title">Network Status</h2>
        <div style="display: flex; gap: var(--space-sm);">
          <button class="btn btn-primary btn-sm" onClick={startAll} disabled={busy}>
            {busy ? "Starting..." : "Start All"}
          </button>
          <button class="btn btn-sm" onClick={startPds2} disabled={busy}>
            Start with PDS2
          </button>
          <button class="btn btn-destructive btn-sm" onClick={stopAll} disabled={busy}>
            Stop All
          </button>
        </div>
      </div>
      <div class="card-body" style="padding: 0;">
        <table class="network-table">
          <thead>
            <tr>
              <th>Service</th>
              <th>URL</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {services.map((s) => (
              <tr key={s.name}>
                <td>
                  <span
                    class={`health-dot ${
                      s.status === "running"
                        ? s.healthy ? "healthy" : "unhealthy"
                        : s.status === "starting"
                        ? "starting"
                        : "stopped"
                    }`}
                  />
                  {s.label}
                </td>
                <td style="font-family: var(--font-system); font-size: var(--font-size-xs); color: var(--color-text-secondary);">
                  {s.url}
                </td>
                <td>
                  <span
                    class={`badge ${
                      s.status === "running"
                        ? s.healthy ? "badge-success" : "badge-warning"
                        : s.status === "starting"
                        ? "badge-warning"
                        : s.status === "error"
                        ? "badge-destructive"
                        : "badge-secondary"
                    }`}
                  >
                    {s.status}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
