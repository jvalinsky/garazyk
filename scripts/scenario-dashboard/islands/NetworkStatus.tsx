/** Network status island — displays ATProto service table with start/stop controls. @module NetworkStatus */
import { useRuntime } from "../runtime.ts";

/** Render the network services table with start/stop/start-pds2 buttons. */
export default function NetworkStatus() {
  const { state, dispatch } = useRuntime();
  const { services } = state.value.network;
  const busy = state.value.ux.busy;
  const runner = state.value.ux.runner;
  const runningServices =
    services.filter((service) => service.status === "running").length;
  const serviceCount = services.length;

  function startAll() {
    dispatch({ type: "network/startRequested", pds2: false, runner });
  }

  function startPds2() {
    const ok = globalThis.confirm?.(
      `Start ${serviceCount} services with PDS2 on the ${runner} runner? This changes the network under test.`,
    );
    if (ok === false) return;
    dispatch({ type: "network/startRequested", pds2: true, runner });
  }

  function stopAll() {
    const ok = globalThis.confirm?.(
      `Stop all ${serviceCount} services on the ${runner} runner?`,
    );
    if (ok === false) return;
    dispatch({ type: "network/stopRequested", runner });
  }

  return (
    <div id="network-status" class="card" style="margin-bottom: var(--space-xl);">
      <div class="card-header">
        <div>
          <h2 class="card-title">Network Status</h2>
          <div class="control-scope-line">
            <span>runner: {runner}</span>
            <span>services: {runningServices}/{serviceCount}</span>
            <span>PDS2: optional</span>
          </div>
        </div>
        <div class="network-actions">
          <button
            class="btn btn-primary btn-sm"
            onClick={startAll}
            disabled={busy}
            title={`Start ${serviceCount} services with ${runner} runner`}
          >
            {busy ? "Starting..." : `Start ${serviceCount || "All"}`}
          </button>
          <button
            class="btn btn-sm"
            onClick={startPds2}
            disabled={busy}
            title={`Start ${serviceCount} services with PDS2 using ${runner} runner`}
          >
            Start with PDS2
          </button>
          <button
            class="btn btn-destructive btn-sm"
            onClick={stopAll}
            disabled={busy}
            title={`Stop ${serviceCount} services managed by the ${runner} runner`}
          >
            Stop {serviceCount || "All"}
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
                <td class="network-table-url">
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
