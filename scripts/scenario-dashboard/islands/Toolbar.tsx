/** Toolbar island — topology selector, run/stop/restart controls, settings modal. @module Toolbar */
import { useEffect } from "preact/hooks";
import { useRuntime } from "../runtime.ts";

const IS_BROWSER = typeof globalThis !== "undefined" &&
  "document" in globalThis;

/** Toolbar island for topology selection and run controls. */
export default function Toolbar() {
  const { state, dispatch } = useRuntime();
  const s = state.value;
  const topologies = s.topology.available;
  const run = s.runs.active;
  const busy = s.ux.busy;
  const showSettings = s.ux.settingsOpen;
  const params = s.ux.scenarioParams;
  const scenarios = s.scenarios.all;
  const services = s.network.services;

  useEffect(() => {
    if (!IS_BROWSER) return;
    const saved = localStorage.getItem("garazyk-dashboard-agentMode");
    if (saved === "true" && !state.peek().ux.agentMode) {
      dispatch({ type: "ux/setAgentMode", agentMode: true });
    }
  }, []);

  useEffect(() => {
    if (!IS_BROWSER) return;
    localStorage.setItem("garazyk-dashboard-agentMode", String(s.ux.agentMode));
  }, [s.ux.agentMode]);

  useEffect(() => {
    if (!IS_BROWSER) return;
    const saved = localStorage.getItem("garazyk-dashboard-topology");
    if (saved && saved !== state.peek().topology.selected) {
      dispatch({ type: "topology/selected", name: saved });
    }
  }, [topologies.length]);

  useEffect(() => {
    if (!IS_BROWSER) return;
    localStorage.setItem("garazyk-dashboard-topology", s.topology.selected);
  }, [s.topology.selected]);

  useEffect(() => {
    if (!IS_BROWSER) return;
    const saved = localStorage.getItem("garazyk-dashboard-runner");
    if (
      saved && (saved === "host" || saved === "docker") &&
      saved !== state.peek().ux.runner
    ) {
      dispatch({ type: "ux/setRunner", runner: saved });
    }
  }, []);

  useEffect(() => {
    if (!IS_BROWSER) return;
    localStorage.setItem("garazyk-dashboard-runner", s.ux.runner);
  }, [s.ux.runner]);

  const isStarting = run?.status === "starting";
  const isRunning = run?.status === "running";
  const isStopping = run?.status === "stopping";
  const isActive = isStarting || isRunning || isStopping;

  const hasParameters = scenarios.some((sc) =>
    sc.parameters && Object.keys(sc.parameters).length > 0
  );
  const needsPds2 = scenarios.some((sc) => sc.needsPds2);
  const runningServices =
    services.filter((service) => service.status === "running").length;
  const serviceScope = services.length > 0
    ? `${runningServices}/${services.length}`
    : "0";
  const runScopeLabel = isActive && run
    ? `${run.status} run ${run.id}`
    : `${scenarios.length} scenarios`;

  function runAll() {
    const ids = scenarios.map((sc) => sc.id);
    if (ids.length === 0) return;
    if (state.peek().ux.settingsOpen) {
      dispatch({ type: "ux/toggleSettings" });
    }
    const byId = new Map(scenarios.map((sc) => [sc.id, sc]));
    dispatch({
      type: "runs/startRequested",
      scenarioIds: ids,
      pds2: ids.some((id) => byId.get(id)?.needsPds2),
      runner: s.ux.runner,
    });
  }

  function stopRun() {
    dispatch({ type: "runs/stopRequested" });
  }

  function restartRun() {
    dispatch({ type: "runs/restartRequested" });
  }

  return (
    <header class="toolbar">
      <div class="toolbar-section">
        <span class="toolbar-title">Garazyk Scenarios</span>
      </div>

      <div class="command-scope" aria-label="Current command scope">
        <span class="scope-pill scope-pill-strong">Garazyk</span>
        <span class="scope-pill">
          <span class="scope-label">topology</span>
          <span class="scope-value">{s.topology.selected}</span>
        </span>
        <span class="scope-pill">
          <span class="scope-label">runner</span>
          <span class="scope-value">{s.ux.runner}</span>
        </span>
        <span class="scope-pill">
          <span class="scope-label">scope</span>
          <span class="scope-value">{runScopeLabel}</span>
        </span>
        <span class="scope-pill">
          <span class="scope-label">services</span>
          <span class="scope-value">{serviceScope}</span>
        </span>
        <span class="scope-pill">
          <span class="scope-label">PDS2</span>
          <span class="scope-value">
            {needsPds2 ? "included" : "not required"}
          </span>
        </span>
      </div>

      <div class="toolbar-spacer" />

      <div class="toolbar-section">
        <label class="toolbar-label" for="topology-select">Topology</label>
        <select
          id="topology-select"
          class="form-select"
          value={s.topology.selected}
          disabled={isActive}
          onChange={(e) =>
            dispatch({
              type: "topology/selected",
              name: (e.target as HTMLSelectElement).value,
            })}
        >
          {topologies.map((t) => (
            <option key={t.name} value={t.name}>
              {t.name}
            </option>
          ))}
        </select>
      </div>

      <div class="toolbar-section">
        <label class="toolbar-label" for="runner-select">Runner</label>
        <select
          id="runner-select"
          class="form-select"
          value={s.ux.runner}
          disabled={isActive}
          onChange={(e) =>
            dispatch({
              type: "ux/setRunner",
              runner: (e.target as HTMLSelectElement).value as
                | "host"
                | "docker",
            })}
        >
          <option value="host">host</option>
          <option value="docker">docker</option>
        </select>
      </div>

      <div class="toolbar-section">
        {!isActive
          ? (
            <div style="display: flex; gap: var(--space-sm);">
              {hasParameters && (
                <button
                  type="button"
                  class="btn btn-secondary"
                  onClick={() => dispatch({ type: "ux/toggleSettings" })}
                  disabled={busy}
                >
                  Settings
                </button>
              )}
              <label
                class="toolbar-checkbox"
                title="Use hamownia agent run with NDJSON event streaming"
              >
                <input
                  id="agentMode"
                  type="checkbox"
                  checked={s.ux.agentMode}
                  disabled={busy}
                  onChange={(e) =>
                    dispatch({
                      type: "ux/setAgentMode",
                      agentMode: (e.target as HTMLInputElement).checked,
                    })}
                />
                <span>Agent</span>
              </label>
              <button
                type="button"
                class="btn btn-primary"
                onClick={runAll}
                disabled={busy}
                title={`Run ${scenarios.length} scenarios on ${s.topology.selected} with ${s.ux.runner} runner${
                  needsPds2 ? " and PDS2" : ""
                }`}
              >
                {busy ? "Starting..." : "Run All"}
              </button>
            </div>
          )
          : (
            <div style="display: flex; gap: var(--space-sm);">
              <div class="active-run-indicator">
                <span
                  class={`status-dot ${isStopping ? "stopping" : "running"}`}
                />
                <span class="text-xs font-mono">{run.id}</span>
              </div>
              <button
                type="button"
                class="btn btn-sm"
                onClick={restartRun}
                disabled={busy || isStopping}
                title={`Restart run ${run.id} on ${s.topology.selected}`}
              >
                Restart
              </button>
              <button
                type="button"
                class="btn btn-destructive btn-sm"
                onClick={stopRun}
                disabled={busy || isStopping}
                title={`Stop run ${run.id}`}
              >
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
              <button
                type="button"
                class="btn-close"
                onClick={() => dispatch({ type: "ux/toggleSettings" })}
              >
                ×
              </button>
            </div>
            <div class="settings-modal-body">
              {scenarios.map((sc) => {
                if (!sc.parameters || Object.keys(sc.parameters).length === 0) {
                  return null;
                }
                return (
                  <div key={sc.id} class="scenario-settings-group">
                    <div class="scenario-settings-title">{sc.id} {sc.name}</div>
                    {Object.entries(sc.parameters).map(([key, meta]) => {
                      const value = params[key] ?? meta.default;
                      return (
                        <div key={key} class="setting-row">
                          <div class="setting-info">
                            <div class="setting-label">{key}</div>
                            <div class="setting-desc">{meta.description}</div>
                          </div>
                          <div class="setting-input-wrapper">
                            {meta.type === "number"
                              ? (
                                <input
                                  type="number"
                                  class="form-input"
                                  value={value as number}
                                  onChange={(e) =>
                                    dispatch({
                                      type: "ux/setScenarioParam",
                                      key,
                                      value: Number(
                                        (e.target as HTMLInputElement).value,
                                      ),
                                    })}
                                />
                              )
                              : meta.type === "boolean"
                              ? (
                                <input
                                  type="checkbox"
                                  checked={value as boolean}
                                  onChange={(e) =>
                                    dispatch({
                                      type: "ux/setScenarioParam",
                                      key,
                                      value:
                                        (e.target as HTMLInputElement).checked,
                                    })}
                                />
                              )
                              : (
                                <input
                                  type="text"
                                  class="form-input"
                                  value={value as string}
                                  onChange={(e) =>
                                    dispatch({
                                      type: "ux/setScenarioParam",
                                      key,
                                      value:
                                        (e.target as HTMLInputElement).value,
                                    })}
                                />
                              )}
                          </div>
                        </div>
                      );
                    })}
                  </div>
                );
              })}
            </div>
            <div class="settings-modal-footer">
              <button
                type="button"
                class="btn btn-primary"
                onClick={runAll}
                disabled={busy}
              >
                Start Run with These Settings
              </button>
            </div>
          </div>
        </div>
      )}
    </header>
  );
}
