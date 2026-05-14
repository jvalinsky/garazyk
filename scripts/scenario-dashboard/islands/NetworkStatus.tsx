import { useState, useEffect } from "preact/hooks";

interface ServiceInfo {
  name: string;
  label: string;
  url: string;
  status: "running" | "stopped" | "starting" | "error";
  healthy?: boolean;
}

interface NetworkStatusProps {
  services: ServiceInfo[];
}

export default function NetworkStatus({ services: initial }: NetworkStatusProps) {
  const [services, setServices] = useState(initial);
  const [busy, setBusy] = useState(false);

  async function refresh() {
    try {
      const res = await fetch("/api/network/health");
      const data = await res.json();
      if (data.services) {
        setServices(Object.values(data.services));
      }
    } catch (e) {
      console.error("Failed to refresh network status:", e);
    }
  }

  useEffect(() => {
    const id = setInterval(refresh, 5000);
    return () => clearInterval(id);
  }, []);

  async function startAll() {
    setBusy(true);
    await fetch("/api/network/start", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
    await refresh();
    setBusy(false);
  }

  async function startPds2() {
    setBusy(true);
    await fetch("/api/network/start", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ pds2: true }) });
    await refresh();
    setBusy(false);
  }

  async function stopAll() {
    setBusy(true);
    await fetch("/api/network/stop", { method: "POST" });
    await refresh();
    setBusy(false);
  }

  async function startService(name: string) {
    setBusy(true);
    // placeholder — per-service start not implemented yet
    setBusy(false);
  }

  async function stopService(name: string) {
    setBusy(true);
    // placeholder — per-service stop not implemented yet
    setBusy(false);
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
                <td style="color: var(--color-text-tertiary); font-size: var(--font-size-xs);">
                  Per-service control not yet available
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
