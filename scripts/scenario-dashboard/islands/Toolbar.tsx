/** Toolbar island — topology selector, run/stop/restart controls, settings modal. @module Toolbar */
import { useEffect } from "preact/hooks";
import { useRuntime } from "../runtime.ts";

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

  const isStarting = run?.status === "starting";
  const isRunning = run?.status === "running";
  const isStopping = run?.status === "stopping";
  const isActive = isStarting || isRunning || isStopping;

  const hasParameters = scenarios.some((sc) =>
    sc.parameters && Object.keys(sc.parameters).length > 0
  );

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

      <div class="toolbar-spacer" />

      <div class="toolbar-section">
        <label class="toolbar-label" for="topology-select">Topology</label>
        <select
          id="topology-select"
          class="form-select"
          value={s.topology.selected}
          disabled={isActive}
          onChange={(e) =>
            dispatch({ type: "topology/selected", name: (e.target as HTMLSelectElement).value })}
        >
          {topologies.map((t) => (
            <option key={t.name} value={t.name}>
              {t.name}
            </option>
          ))}
        </select>
      </div>

      <div class="toolbar-section">
        {!isActive
          ? (
            <div style="display: flex; gap: var(--space-sm);">
              {hasParameters && (
                <button
                  class="btn btn-secondary"
                  onClick={() => dispatch({ type: "ux/toggleSettings" })}
                  disabled={busy}
                >
                  Settings
                </button>
              )}
              <button class="btn btn-primary" onClick={runAll} disabled={busy}>
                {busy ? "Starting..." : "Run All"}
              </button>
            </div>
          )
          : (
            <div style="display: flex; gap: var(--space-sm);">
              <div class="active-run-indicator">
                <span class={`status-dot ${isStopping ? "stopping" : "running"}`} />
                <span class="text-xs font-mono">{run.id}</span>
              </div>
              <button class="btn btn-sm" onClick={restartRun} disabled={busy || isStopping}>
                Restart
              </button>
              <button
                class="btn btn-destructive btn-sm"
                onClick={stopRun}
                disabled={busy || isStopping}
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
              <button class="btn-close" onClick={() => dispatch({ type: "ux/toggleSettings" })}>
                ×
              </button>
            </div>
            <div class="settings-modal-body">
              {scenarios.map((sc) => {
                if (!sc.parameters || Object.keys(sc.parameters).length === 0) return null;
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
                                      value: Number((e.target as HTMLInputElement).value),
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
                                      value: (e.target as HTMLInputElement).checked,
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
                                      value: (e.target as HTMLInputElement).value,
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
