import { useState, useEffect } from "preact/hooks";
import { selectedTopology, activeRun } from "../signals.ts";

export default function Toolbar() {
  const [busy, setBusy] = useState(false);
  const [topologies, setTopologies] = useState<{ name: string }[]>([]);

  useEffect(() => {
    fetch("/api/topologies")
      .then((res) => res.json())
      .then((data) => setTopologies(data.topologies))
      .catch((e) => console.error("Failed to fetch topologies", e));
  }, []);

  const run = activeRun.value;
  const isStarting = run?.status === "starting";
  const isRunning = run?.status === "running";
  const isStopping = run?.status === "stopping";
  const isActive = isStarting || isRunning || isStopping;

  async function runAll() {
    setBusy(true);
    try {
      const scenariosResp = await fetch("/api/scenarios");
      const { scenarios } = await scenariosResp.json();
      const ids = scenarios.map((s: any) => s.id);

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
          <button class="btn btn-primary" onClick={runAll} disabled={busy}>
            {busy ? "Starting..." : "Run All"}
          </button>
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
    </header>
  );
}
