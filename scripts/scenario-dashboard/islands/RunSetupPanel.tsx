/** Inline run setup panel — scenario parameters beside command scope. @module RunSetupPanel */
import { useEffect, useId, useRef } from "preact/hooks";
import { useRuntime } from "../runtime.ts";

function fieldId(scenarioId: string, key: string): string {
  return `run-param-${scenarioId}-${key}`.replace(/[^a-zA-Z0-9_-]/g, "-");
}

/** Collapsible parameter editor shown below the toolbar on the home page. */
export default function RunSetupPanel() {
  const panelRef = useRef<HTMLElement>(null);
  const titleId = useId();
  const { state, dispatch } = useRuntime();
  const s = state.value;
  const params = s.ux.scenarioParams;
  const scenarios = s.scenarios.all;
  const busy = s.ux.busy;

  const parameterized = scenarios.filter((sc) =>
    sc.parameters && Object.keys(sc.parameters).length > 0
  );

  useEffect(() => {
    if (!s.ux.settingsOpen) return;
    const focusTarget = panelRef.current?.querySelector<HTMLElement>(
      "input, select, button",
    );
    focusTarget?.focus();
  }, [s.ux.settingsOpen]);

  if (!s.ux.settingsOpen || parameterized.length === 0) {
    return null;
  }

  function runAll() {
    const ids = scenarios.map((sc) => sc.id);
    if (ids.length === 0) return;
    dispatch({ type: "ux/toggleSettings" });
    const byId = new Map(scenarios.map((sc) => [sc.id, sc]));
    dispatch({
      type: "runs/startRequested",
      scenarioIds: ids,
      pds2: ids.some((id) => byId.get(id)?.needsPds2),
      runner: s.ux.runner,
    });
  }

  return (
    <section
      ref={panelRef}
      id="run-setup"
      class="run-setup-panel"
      aria-labelledby={titleId}
    >
      <header class="run-setup-header">
        <div>
          <p class="run-setup-kicker">Prepare run</p>
          <h2 id={titleId} class="run-setup-title">
            Scenario parameters
          </h2>
          <p class="run-setup-desc">
            Applies to the next Run All on {s.topology.selected} ({s.ux.runner}{" "}
            runner). Topology and runner stay visible in the toolbar scope strip.
          </p>
        </div>
        <button
          type="button"
          class="btn btn-secondary btn-sm"
          onClick={() => dispatch({ type: "ux/toggleSettings" })}
        >
          Close
        </button>
      </header>

      <div class="run-setup-body">
        {parameterized.map((sc) => (
          <fieldset key={sc.id} class="run-setup-group">
            <legend class="run-setup-group-title">
              {sc.id} {sc.name}
            </legend>
            {Object.entries(sc.parameters!).map(([key, meta]) => {
              const inputId = fieldId(sc.id, key);
              const descId = `${inputId}-desc`;
              const value = params[key] ?? meta.default;

              return (
                <div key={key} class="setting-row">
                  <div class="setting-info">
                    <label class="setting-label" for={inputId}>
                      {key}
                    </label>
                    {meta.description && (
                      <p id={descId} class="setting-desc">
                        {meta.description}
                      </p>
                    )}
                  </div>
                  <div class="setting-input-wrapper">
                    {meta.type === "number"
                      ? (
                        <input
                          id={inputId}
                          type="number"
                          class="form-input"
                          aria-describedby={meta.description ? descId : undefined}
                          value={value as number}
                          onInput={(e) =>
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
                          id={inputId}
                          type="checkbox"
                          aria-describedby={meta.description ? descId : undefined}
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
                          id={inputId}
                          type="text"
                          class="form-input"
                          aria-describedby={meta.description ? descId : undefined}
                          value={value as string}
                          onInput={(e) =>
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
          </fieldset>
        ))}
      </div>

      <footer class="run-setup-footer">
        <button
          type="button"
          class="btn btn-primary"
          onClick={runAll}
          disabled={busy}
        >
          Run All with these settings
        </button>
      </footer>
    </section>
  );
}
