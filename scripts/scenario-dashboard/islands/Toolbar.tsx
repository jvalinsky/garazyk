import { useState, useEffect } from "preact/hooks";
import { selectedTopology, activeRun } from "../signals.ts";

export default function Toolbar() {
  const [busy, setBusy] = useState(false);
  const [topologies, setTopologies] = useState<{ name: string }[]>([]);
  const [showSettings, setShowSettings] = useState(false);
  const [availableScenarios, setAvailableScenarios] = useState<any[]>([]);
  const [params, setParams] = useState<Record<string, any>>({});

  useEffect(() => {
    fetch("/api/topologies")
      .then((res) => res.json())
      .then((data) => setTopologies(data.topologies))
      .catch((e) => console.error("Failed to fetch topologies", e));

    fetch("/api/scenarios")
      .then((res) => res.json())
      .then((data) => {
        setAvailableScenarios(data.scenarios);
        const defaults: Record<string, any> = {};
        for (const s of data.scenarios) {
          if (s.parameters) {
            for (const [key, meta] of Object.entries(s.parameters)) {
              // @ts-ignore
              defaults[key] = meta.default;
            }
          }
        }
        setParams(defaults);
      })
      .catch((e) => console.error("Failed to fetch scenarios", e));
  }, []);

  const run = activeRun.value;
  const isStarting = run?.status === "starting";
  const isRunning = run?.status === "running";
  const isStopping = run?.status === "stopping";
  const isActive = isStarting || isRunning || isStopping;

  async function runAll() {
    setBusy(true);
    setShowSettings(false);
    try {
      const ids = availableScenarios.map((s: any) => s.id);

      if (ids.length === 0) return;

      const resp = await fetch("/api/runs/start", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          topology: selectedTopology.value,
          runner: "host",
          scenarioIds: ids,
          pds2: ids.some((id: string) => id === "05" || id === "12"),
          binaryMode: false,
          scenarioParams: params,
        }),
      });

      if (resp.ok) {
        const data = await resp.json();
        window.location.href = `/run/${data.runId}`;
      }
    } catch (error) {
      console.error("Error running scenarios:", error);
    } finally {
      setBusy(false);
    }
  }

  async function stopRun() {
    if (!run) return;
    setBusy(true);
    try {
      await fetch(`/api/runs/${run.id}/stop`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ graceful: true }),
      });
    } catch (error) {
      console.error("Error stopping run:", error);
    } finally {
      setBusy(false);
    }
  }

  async function restartRun() {
    if (!run) return;
    setBusy(true);
    try {
      const resp = await fetch(`/api/runs/${run.id}/restart`, {
        method: "POST",
      });
      if (resp.ok) {
        const data = await resp.json();
        window.location.href = `/run/${data.newRunId}`;
      }
    } catch (error) {
      console.error("Error restarting run:", error);
    } finally {
      setBusy(false);
    }
  }

  const hasParameters = availableScenarios.some(s => s.parameters && Object.keys(s.parameters).length > 0);

  return (
    <header class="toolbar">
      <div class="toolbar-section">
        <span class="toolbar-title">Garazyk Scenarios</span>
      </div>
      
      <div class="toolbar-spacer" />

      <div class="toolbar-section">
        <label class="toolbar-label" for="topology-select">Topology</label>
        <select
          id="topology-select"
          class="form-select"
          value={selectedTopology.value}
          disabled={isActive}
          onChange={(e) => selectedTopology.value = (e.target as HTMLSelectElement).value}
        >
          {topologies.map((t) => (
            <option key={t.name} value={t.name}>
              {t.name}
            </option>
          ))}
        </select>
      </div>

      <div class="toolbar-section">
        {!isActive ? (
          <div style="display: flex; gap: var(--space-sm);">
            {hasParameters && (
              <button class="btn btn-secondary" onClick={() => setShowSettings(!showSettings)} disabled={busy}>
                Settings
              </button>
            )}
            <button class="btn btn-primary" onClick={runAll} disabled={busy}>
              {busy ? "Starting..." : "Run All"}
            </button>
          </div>
        ) : (
          <div style="display: flex; gap: var(--space-sm);">
            <div class="active-run-indicator">
              <span class={`status-dot ${isStopping ? "stopping" : "running"}`} />
              <span class="text-xs font-mono">{run.id}</span>
            </div>
            <button class="btn btn-sm" onClick={restartRun} disabled={busy || isStopping}>
              Restart
            </button>
            <button class="btn btn-destructive btn-sm" onClick={stopRun} disabled={busy || isStopping}>
              {isStopping ? "Stopping..." : "Stop"}
            </button>
          </div>
        )}
      </div>

      {showSettings && (
        <div class="settings-modal-backdrop">
          <div class="settings-modal">
            <div class="settings-modal-header">
              <h3>Scenario Settings</h3>
              <button class="btn-close" onClick={() => setShowSettings(false)}>×</button>
            </div>
            <div class="settings-modal-body">
              {availableScenarios.map(s => {
                if (!s.parameters || Object.keys(s.parameters).length === 0) return null;
                return (
                  <div key={s.id} class="scenario-settings-group">
                    <div class="scenario-settings-title">{s.id} {s.name}</div>
                    {Object.entries(s.parameters).map(([key, meta]: [string, any]) => (
                      <div key={key} class="setting-row">
                        <div class="setting-info">
                          <div class="setting-label">{key}</div>
                          <div class="setting-desc">{meta.description}</div>
                        </div>
                        <div class="setting-input-wrapper">
                          {meta.type === "number" ? (
                            <input
                              type="number"
                              class="form-input"
                              value={params[key]}
                              onChange={(e) => setParams({ ...params, [key]: Number((e.target as HTMLInputElement).value) })}
                            />
                          ) : meta.type === "boolean" ? (
                            <input
                              type="checkbox"
                              checked={params[key]}
                              onChange={(e) => setParams({ ...params, [key]: (e.target as HTMLInputElement).checked })}
                            />
                          ) : (
                            <input
                              type="text"
                              class="form-input"
                              value={params[key]}
                              onChange={(e) => setParams({ ...params, [key]: (e.target as HTMLInputElement).value })}
                            />
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                );
              })}
            </div>
            <div class="settings-modal-footer">
              <button class="btn btn-primary" onClick={runAll} disabled={busy}>
                Start Run with These Settings
              </button>
            </div>
          </div>
        </div>
      )}
    </header>
  );
}
