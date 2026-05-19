/**
 * Garazyk Scenario Dashboard — Terminal UI
 *
 * Full-screen terminal dashboard using the TEA state machine
 * with a custom immediate-mode renderer and widget dashboard layout.
 *
 * Press q or Ctrl+C to exit. Press ? for help.
 *
 * @module tui
 */

import {
  ScreenBuffer,
  enterTerminalMode,
  exitTerminalMode,
  writeToTerminal,
  isTerminal,
  getTerminalSize,
  CLEAR_SCREEN,
  CURSOR_HOME,
  RESET,
} from "@garazyk/tui";
import { readKeys, isKey, isCtrl, isQuit, Keys } from "@garazyk/tui";
import type { Key } from "@garazyk/tui";
import { computeLayout, PANEL_IDS, type PanelId } from "@garazyk/tui";
import { panelContentArea } from "@garazyk/tui";
import { FocusRing } from "@garazyk/tui";
import {
  createPanelStates,
  moveCursorUp,
  moveCursorDown,
  clampPanelState,
  type PanelStates,
  type PanelState,
} from "./tui/panel_state.ts";
import { createTuiRuntime, type TuiRuntimeHandle } from "./tui/runtime.ts";
import { renderView } from "./tui/view.ts";
import type { DashboardState } from "./dashboard_state.ts";
import type { Msg } from "./dashboard_state.ts";
import { fetchRuns } from "./db/queries.ts";
import { db } from "./db/index.ts";
import { getScenariosItemCount, getScenariosItemAt } from "./tui/panels/scenarios.ts";

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

export interface DashboardTuiOptions {
  /** If true, performs a one-shot non-interactive render. */
  renderOnce?: boolean;
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

/** Open the live terminal dashboard. Press q or Ctrl-C to exit. */
export async function runDashboardTui(
  options: DashboardTuiOptions = {},
): Promise<void> {
  // One-shot mode — render a single frame and exit
  if (options.renderOnce) {
    await renderOnce(options);
    return;
  }

  // Interactive mode requires a terminal
  if (!isTerminal()) {
    await renderOnce(options);
    return;
  }

  await runInteractiveTui(options);
}

// ---------------------------------------------------------------------------
// One-shot mode (replaces old `status` command)
// ---------------------------------------------------------------------------

async function renderOnce(options: DashboardTuiOptions): Promise<void> {
  const runtime = createTuiRuntime();

  // Wait briefly for boot cmds to complete
  await new Promise((resolve) => setTimeout(resolve, 1500));

  const state = runtime.state;
  const size = getTerminalSize() ?? { cols: 80, rows: 24 };

  if (size) {
    const layout = computeLayout(size.cols, size.rows);
    if (layout) {
      const buf = new ScreenBuffer(size.cols, size.rows);
      const focus = new FocusRing();
      const panelStates = createPanelStates();
      const recentRuns = fetchRuns(db, 6);
      renderView(buf, state, layout, focus, panelStates, recentRuns);
      await writeToTerminal(buf.fullRedraw() + "\n");
      runtime.destroy();
      return;
    }
  }

  // Fallback: simple text output
  await writeToTerminal(renderTextSnapshot(state) + "\n");
  runtime.destroy();
}

// ---------------------------------------------------------------------------
// Interactive mode
// ---------------------------------------------------------------------------

async function runInteractiveTui(options: DashboardTuiOptions): Promise<void> {
  const size = getTerminalSize();
  if (!size) {
    console.error("Cannot determine terminal size.");
    return;
  }

  const runtime = createTuiRuntime();
  const focus = new FocusRing();
  const panelStates = createPanelStates();
  const buf = new ScreenBuffer(size.cols, size.rows);
  let layout = computeLayout(size.cols, size.rows);
  let needsRender = true;
  let quit = false;
  let helpOverlay = false;

  // Filter mode state
  let filterMode = false;

  // Set up terminal
  await enterTerminalMode();

  // Signal handlers
  const onResize = () => {
    const newSize = getTerminalSize();
    if (!newSize) return;
    buf.resize(newSize.cols, newSize.rows);
    layout = computeLayout(newSize.cols, newSize.rows);
    if (layout) {
      needsRender = true;
      // Full redraw after resize
      renderAndWrite(buf, runtime.state, layout!, focus, panelStates);
    }
  };

  const onSuspend = async () => {
    await exitTerminalMode();
    Deno.kill(Deno.pid, "SIGSTOP");
    // After resume:
    await enterTerminalMode();
    needsRender = true;
  };

  // Register signal handlers
  Deno.addSignalListener("SIGWINCH", onResize);
  try { Deno.addSignalListener("SIGTSTP", onSuspend); } catch { /* not supported on all platforms */ }

  // Subscribe to state changes
  const unsubscribe = runtime.onChange(() => {
    needsRender = true;
  });

  try {
    // Initial render
    if (layout) {
      renderAndWrite(buf, runtime.state, layout, focus, panelStates);
    }

    // Main event loop
    for await (const key of readKeys()) {
      if (quit) break;

      // Handle filter mode
      if (filterMode) {
        handleFilterKey(key, runtime, focus, () => { filterMode = false; });
        needsRender = true;
        continue;
      }

      // Handle help overlay
      if (helpOverlay) {
        helpOverlay = false;
        needsRender = true;
        continue;
      }

      // Handle key
      const handled = handleKey(
        key,
        runtime,
        focus,
        panelStates,
        layout,
        () => { quit = true; },
        () => { helpOverlay = true; },
        () => { filterMode = true; },
      );

      if (handled) needsRender = true;

      // Render if needed
      if (needsRender && layout) {
        renderAndWrite(buf, runtime.state, layout, focus, panelStates);
        needsRender = false;
      }
    }
  } finally {
    // Cleanup
    unsubscribe();
    Deno.removeSignalListener("SIGWINCH", onResize);
    try { Deno.removeSignalListener("SIGTSTP", onSuspend); } catch { /* ignore */ }
    runtime.destroy();
    await exitTerminalMode();
  }
}

// ---------------------------------------------------------------------------
// Key handling
// ---------------------------------------------------------------------------

function handleKey(
  key: Key,
  runtime: TuiRuntimeHandle,
  focus: FocusRing,
  panelStates: PanelStates,
  layout: ReturnType<typeof computeLayout>,
  onQuit: () => void,
  onHelp: () => void,
  onFilter: () => void,
): boolean {
  // Global keys — these always work regardless of focused panel
  if (isQuit(key)) { onQuit(); return true; }
  if (isKey(key, Keys.ESCAPE)) { onQuit(); return true; }
  if (isKey(key, Keys.TAB) && !key.shift) { focus.next(); return true; }
  if (isKey(key, Keys.TAB) && key.shift) { focus.prev(); return true; }
  if (isKey(key, "?")) { onHelp(); return true; }
  if (isKey(key, "r") && !key.ctrl) {
    // Force refresh — re-dispatch boot cmds
    runtime.dispatch({ type: "network/healthTimeout" });
    runtime.dispatch({ type: "runs/activeTimeout" });
    return true;
  }

  // Panel jump keys (1-4)
  if (!key.ctrl && !key.alt && !key.shift) {
    const num = parseInt(key.key);
    if (num >= 1 && num <= 4) {
      focus.jump(num - 1);
      return true;
    }
  }

  // Arrow keys — navigate within focused panel
  if (isKey(key, Keys.UP)) {
    return handleCursorUp(focus, panelStates, runtime, layout);
  }
  if (isKey(key, Keys.DOWN)) {
    return handleCursorDown(focus, panelStates, runtime, layout);
  }

  // Panel-specific keys
  const panel = focus.current;
  switch (panel) {
    case "network":
      return handleNetworkKey(key, runtime);
    case "scenarios":
      return handleScenariosKey(key, runtime, panelStates, onFilter);
    case "run":
      return handleRunKey(key, runtime);
    case "history":
      return handleHistoryKey(key, runtime);
  }
  return false;
}

/** Get the visible row count for a panel (content area height minus actions row). */
function getVisibleRows(panelId: PanelId, layout: NonNullable<ReturnType<typeof computeLayout>>): number {
  const panel = layout.panels.find((p) => p.id === panelId);
  if (!panel) return 0;
  const area = panelContentArea(panel);
  return Math.max(0, area.height - 1); // -1 for actions hint row
}

/** Update itemCount for a panel based on current state. */
function syncPanelItemCount(
  panelId: PanelId,
  panelStates: PanelStates,
  runtime: TuiRuntimeHandle,
  layout: NonNullable<ReturnType<typeof computeLayout>>,
): void {
  const state = runtime.state;
  const visibleRows = getVisibleRows(panelId, layout);

  switch (panelId) {
    case "network":
      panelStates[panelId] = clampPanelState(
        panelStates[panelId],
        state.network.services.length,
        visibleRows,
      );
      break;
    case "scenarios": {
      const count = getScenariosItemCount(
        state.scenarios.all,
        state.ux.collapsedCategories,
        state.ux.searchTerm,
      );
      panelStates[panelId] = clampPanelState(panelStates[panelId], count, visibleRows);
      break;
    }
    case "history": {
      const recentRuns = fetchRuns(db, 6);
      panelStates[panelId] = clampPanelState(panelStates[panelId], recentRuns.length, visibleRows);
      break;
    }
    case "run":
      // Run panel has no selectable items
      break;
  }
}

function handleCursorUp(
  focus: FocusRing,
  panelStates: PanelStates,
  runtime: TuiRuntimeHandle,
  layout: ReturnType<typeof computeLayout>,
): boolean {
  if (!layout) return false;
  const panelId = focus.current;
  syncPanelItemCount(panelId, panelStates, runtime, layout);
  const visibleRows = getVisibleRows(panelId, layout);
  panelStates[panelId] = moveCursorUp(panelStates[panelId], visibleRows);
  return true;
}

function handleCursorDown(
  focus: FocusRing,
  panelStates: PanelStates,
  runtime: TuiRuntimeHandle,
  layout: ReturnType<typeof computeLayout>,
): boolean {
  if (!layout) return false;
  const panelId = focus.current;
  syncPanelItemCount(panelId, panelStates, runtime, layout);
  const visibleRows = getVisibleRows(panelId, layout);
  panelStates[panelId] = moveCursorDown(panelStates[panelId], visibleRows);
  return true;
}

function handleNetworkKey(key: Key, runtime: TuiRuntimeHandle): boolean {
  if (isKey(key, "s")) {
    runtime.dispatch({ type: "network/startRequested", pds2: false });
    return true;
  }
  if (isKey(key, "p")) {
    runtime.dispatch({ type: "network/startRequested", pds2: true });
    return true;
  }
  if (isKey(key, "x")) {
    runtime.dispatch({ type: "network/stopRequested" });
    return true;
  }
  return false;
}

function handleScenariosKey(
  key: Key,
  runtime: TuiRuntimeHandle,
  panelStates: PanelStates,
  onFilter: () => void,
): boolean {
  if (isKey(key, "/")) {
    onFilter();
    return true;
  }
  if (isKey(key, " ")) {
    // Toggle the category at the cursor
    const item = getScenariosItemAt(
      runtime.state.scenarios.all,
      runtime.state.ux.collapsedCategories,
      runtime.state.ux.searchTerm,
      panelStates.scenarios.cursor,
    );
    if (item && item.type === "category") {
      runtime.dispatch({ type: "ux/toggleCategory", category: item.key });
    }
    return true;
  }
  if (isKey(key, Keys.ENTER)) {
    // Run the scenario at cursor, or all visible scenarios
    const item = getScenariosItemAt(
      runtime.state.scenarios.all,
      runtime.state.ux.collapsedCategories,
      runtime.state.ux.searchTerm,
      panelStates.scenarios.cursor,
    );
    if (item && item.type === "scenario") {
      const sc = runtime.state.scenarios.all.find((s) => s.id === item.key);
      if (sc) {
        runtime.dispatch({
          type: "runs/startRequested",
          scenarioIds: [sc.id],
          pds2: sc.needsPds2,
        });
      }
    } else if (item && item.type === "category") {
      // Run all scenarios in this category
      const scenarios = runtime.state.scenarios.all;
      const ids = scenarios.map((s) => s.id);
      if (ids.length > 0) {
        const byId = new Map(scenarios.map((s) => [s.id, s]));
        runtime.dispatch({
          type: "runs/startRequested",
          scenarioIds: ids,
          pds2: ids.some((id) => byId.get(id)?.needsPds2),
        });
      }
    }
    return true;
  }
  return false;
}

function handleRunKey(key: Key, runtime: TuiRuntimeHandle): boolean {
  if (isKey(key, "s") && !key.ctrl) {
    runtime.dispatch({ type: "runs/stopRequested" });
    return true;
  }
  if (isKey(key, "r") && !key.ctrl) {
    runtime.dispatch({ type: "runs/restartRequested" });
    return true;
  }
  return false;
}

function handleHistoryKey(key: Key, runtime: TuiRuntimeHandle): boolean {
  if (isKey(key, "r")) {
    runtime.dispatch({ type: "runs/restartRequested" });
    return true;
  }
  return false;
}

function handleFilterKey(
  key: Key,
  runtime: TuiRuntimeHandle,
  focus: FocusRing,
  onExitFilter: () => void,
): void {
  if (isKey(key, Keys.ESCAPE) || isCtrl(key, "c")) {
    runtime.dispatch({ type: "ux/setSearchTerm", term: "" });
    onExitFilter();
    return;
  }
  if (isKey(key, Keys.ENTER)) {
    onExitFilter();
    return;
  }
  if (isKey(key, Keys.BACKSPACE)) {
    runtime.dispatch({ type: "ux/setSearchTerm", term: runtime.state.ux.searchTerm.slice(0, -1) });
    return;
  }
  // Printable character
  if (key.key.length === 1 && !key.ctrl && !key.alt) {
    runtime.dispatch({ type: "ux/setSearchTerm", term: runtime.state.ux.searchTerm + key.key });
  }
}

// ---------------------------------------------------------------------------
// Render helpers
// ---------------------------------------------------------------------------

function renderAndWrite(
  buf: ScreenBuffer,
  state: DashboardState,
  layout: NonNullable<ReturnType<typeof computeLayout>>,
  focus: FocusRing,
  panelStates: PanelStates,
): void {
  const recentRuns = fetchRuns(db, 6);
  renderView(buf, state, layout, focus, panelStates, recentRuns);
  const output = buf.diff();
  if (output) {
    writeToTerminal(output);
  }
}

// ---------------------------------------------------------------------------
// Text fallback (for non-TTY or one-shot mode)
// ---------------------------------------------------------------------------

function renderTextSnapshot(state: DashboardState): string {
  const lines: string[] = [];
  const active = state.runs.active;
  const services = state.network.services;

  lines.push("Garazyk Scenario Dashboard");
  lines.push("");

  lines.push("Network");
  if (services.length === 0) {
    lines.push("  No services discovered");
  } else {
    for (const s of services) {
      const status = s.status === "running" && s.healthy !== false ? "[ok]" : s.status === "running" ? "[??]" : "[--]";
      lines.push(`  ${status} ${s.label || s.name} ${s.url || ""}`);
    }
  }

  lines.push("");
  lines.push("Active Run");
  lines.push(active ? `  [${active.status}] ${active.id}` : "  No active run");

  lines.push("");
  lines.push("Coverage");
  lines.push(`  Scenarios ${state.scenarios.all.length}   Topologies ${state.topology.available.length}`);

  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Re-export for backward compatibility
// ---------------------------------------------------------------------------

/** Data rendered by the terminal dashboard (kept for backward compatibility). */
export interface DashboardTuiSnapshot {
  rootDir: string;
  generatedAt: number;
  services: import("./services/types.ts").ServiceStatus[];
  activeRun: import("./services/types.ts").Run | null;
  recentRuns: import("./services/types.ts").Run[];
  scenarioCount: number;
  topologies: string[];
}

/** Collect one terminal-dashboard snapshot (kept for backward compatibility). */
export async function collectTuiSnapshot(
  options: DashboardTuiOptions = {},
): Promise<DashboardTuiSnapshot> {
  const [networkModule, runModule, dbModule, queryModule, scenarioModule, topologyModule] =
    await Promise.all([
      import("./services/network_manager.ts"),
      import("./services/run_manager.ts"),
      import("./db/index.ts"),
      import("./db/queries.ts"),
      import("./services/scenario_discovery.ts"),
      import("./services/topology_service.ts"),
    ]);

  const [serviceMap, scenarios, topologies] = await Promise.all([
    networkModule.networkManager.healthCheck().catch(() =>
      networkModule.networkManager.getStatus()
    ),
    scenarioModule.getScenarios().catch(() => []),
    topologyModule.listTopologies().catch(() => []),
  ]);

  return {
    rootDir: Deno.cwd(),
    generatedAt: Date.now(),
    services: Object.values(serviceMap),
    activeRun: runModule.runManager.getActiveRun() ?? null,
    recentRuns: queryModule.fetchRuns(dbModule.db, 6),
    scenarioCount: scenarios.length,
    topologies: topologies.map((t) => t.name),
  };
}

/** Render one terminal dashboard frame (kept for backward compatibility). */
export function renderTuiFrame(snapshot: DashboardTuiSnapshot): string {
  const active = snapshot.activeRun;
  const latest = snapshot.recentRuns[0] ?? null;
  const fallbackServices: import("./services/types.ts").ServiceStatus[] = [{
    name: "none",
    label: "No services discovered",
    url: "",
    port: 0,
    status: "stopped",
  }];
  const services = snapshot.services.length > 0
    ? snapshot.services
    : fallbackServices;

  const lines = [
    `Garazyk Scenario Dashboard`,
    snapshot.rootDir,
    "",
    "Network",
    ...services.map(renderService),
    "",
    "Active Run",
    active ? renderRun(active) : "No active run",
    "",
    "Coverage",
    `Scenarios ${snapshot.scenarioCount}   Topologies ${snapshot.topologies.length}`,
    snapshot.topologies.length > 0
      ? snapshot.topologies.slice(0, 6).join(", ")
      : "No topologies found",
    "",
    "Recent Runs",
    ...(snapshot.recentRuns.length > 0
      ? snapshot.recentRuns.map(renderRun)
      : ["No recorded runs"]),
    "",
    "q quits  r refreshes  web dashboard: deno task dashboard",
  ];

  return `${lines.join("\n")}\n`;
}

function renderService(service: import("./services/types.ts").ServiceStatus): string {
  const status = service.status === "running" && service.healthy !== false ? "[ok]" : service.status === "running" ? "[??]" : service.status === "starting" ? "[..]" : service.status === "error" ? "[!!]" : "[--]";
  const name = service.label || service.name;
  const endpoint = service.url || (service.port ? `localhost:${service.port}` : "");
  return `${status} ${name.padEnd(14)} ${endpoint}`;
}

function renderRun(run: import("./services/types.ts").Run): string {
  const completed = run.passed + run.failed + run.skipped;
  const total = run.totalScenarios;
  const width = 18;
  const filled = total > 0 ? Math.max(0, Math.min(width, Math.round((completed / total) * width))) : 0;
  const bar = `[${"#".repeat(filled)}${"-".repeat(width - filled)}] ${completed}/${total}`;
  const status = run.status === "completed" ? "[done]" : run.status === "running" ? "[run ]" : run.status === "error" ? "[fail]" : "[wait]";
  const failures = run.failed > 0 ? `${run.failed} failed` : `${run.passed} passed`;
  return `${status} ${run.id.padEnd(23)} ${bar} ${failures}`;
}
