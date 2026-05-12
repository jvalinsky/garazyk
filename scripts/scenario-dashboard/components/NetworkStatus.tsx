export interface ServiceInfo {
  name: string;
  label: string;
  url: string;
  status: "running" | "stopped" | "starting" | "error";
  healthy?: boolean;
}

interface NetworkStatusProps {
  services: ServiceInfo[];
  onStartAll?: () => void;
  onStopAll?: () => void;
  onStartPds2?: () => void;
  onStartService?: (name: string) => void;
  onStopService?: (name: string) => void;
  onViewLogs?: (name: string) => void;
}

export default function NetworkStatus(
  { services, onStartAll, onStopAll, onStartPds2, onStartService, onStopService, onViewLogs }:
    NetworkStatusProps,
) {
  return (
    <div class="card" style="margin-bottom: var(--space-xl);">
      <div class="card-header">
        <h2 class="card-title">Network Status</h2>
        <div style="display: flex; gap: var(--space-sm);">
          <button class="btn btn-primary btn-sm" onClick={onStartAll}>
            Start All
          </button>
          <button class="btn btn-sm" onClick={onStartPds2}>
            Start with PDS2
          </button>
          <button class="btn btn-destructive btn-sm" onClick={onStopAll}>
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
              <th>Actions</th>
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
                  <span class={`badge ${
                    s.status === "running"
                      ? s.healthy ? "badge-success" : "badge-warning"
                      : s.status === "starting"
                      ? "badge-warning"
                      : s.status === "error"
                      ? "badge-destructive"
                      : "badge-secondary"
                  }`}>
                    {s.status}
                  </span>
                </td>
                <td>
                  <div style="display: flex; gap: var(--space-xs);">
                    {s.status === "running" ? (
                      <button class="btn btn-sm" onClick={() => onStopService?.(s.name)}>
                        Stop
                      </button>
                    ) : (
                      <button class="btn btn-sm" onClick={() => onStartService?.(s.name)}>
                        Start
                      </button>
                    )}
                    {s.status === "running" && (
                      <button class="btn btn-sm" onClick={() => onViewLogs?.(s.name)}>
                        Log
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
