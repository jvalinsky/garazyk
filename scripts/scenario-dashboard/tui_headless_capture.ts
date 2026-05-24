/**
 * Headless TUI Capture — runs the dashboard TUI inside VirtualTuiHarness,
 * captures asciicast v2 output, and exports standalone HTML replay.
 *
 * Usage:
 *   deno run -A tui_headless_capture.ts [outputDir]
 *
 * @module tui_headless_capture
 */

import { VirtualTuiHarness, CastRecorder, replayScript } from "@garazyk/tui/testing";
import type { ReplayStep } from "@garazyk/tui/testing";
import { ScreenBuffer } from "@garazyk/tui";
import { dashboardLayoutTree, solveLayout, FocusRing, PANEL_IDS } from "@garazyk/tui";
import type { PanelId } from "@garazyk/tui";
import { isCtrl, isKey, isQuit, Keys } from "@garazyk/tui";
import type { Key } from "@garazyk/tui";
import { renderView } from "./tui/view.ts";
import { createInitialState } from "./dashboard_state.ts";
import type { DashboardState } from "./dashboard_state.ts";
import type { Run } from "./services/types.ts";
import { createPanelStates, clampPanelState, moveCursorUp, moveCursorDown } from "./tui/panel_state.ts";
import type { PanelStates } from "./tui/panel_state.ts";
import { getScenariosItemAt, getScenariosItemCount } from "./tui/panels/scenarios.ts";
import { buildExportHtml } from "./lib/export_html.ts";
import { join } from "$std/path/mod.ts";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface HeadlessCaptureResult {
  castPath: string;
  htmlPath: string;
}

export interface HeadlessCaptureOptions {
  outputDir: string;
  width?: number;
  height?: number;
  state?: DashboardState;
  steps: ReplayStep[];
  title?: string;
  /** Playback speed multiplier. 1 = real-time, 5 = 5x faster. Default 2. */
  speed?: number;
}

// ---------------------------------------------------------------------------
// Headless capture orchestrator
// ---------------------------------------------------------------------------

export async function captureHeadlessReplay(
  options: HeadlessCaptureOptions,
): Promise<HeadlessCaptureResult> {
  const width = options.width ?? 120;
  const height = options.height ?? 30;
  const outputDir = options.outputDir;

  // 1. Solve layout
  const tree = dashboardLayoutTree(width, height);
  if (!tree) throw new Error("Cannot solve layout tree at " + width + "x" + height);
  const layout = solveLayout(tree, { x: 0, y: 0, width, height });

  // 2. Seed state
  const state = options.state ?? seedDefaultState();

  // 3. Navigation structures
  const focus = new FocusRing();
  const panelStates = createPanelStates();
  syncAllPanelCounts(panelStates, state);

  // 4. Mutable context captured by closures
  let showHelp = false;

  const render = (buf: ScreenBuffer) => {
    renderView(buf, state, layout, focus, panelStates, state.runs.recentRuns, showHelp);
  };

  // 5. Harness
  const harness = new VirtualTuiHarness(width, height, render);

  // 6. Recorder (in-memory — CastRecorder's file-open is async fire-and-forget,
  //    so we avoid the path option and write the cast manually after close)
  await Deno.mkdir(outputDir, { recursive: true });
  const recorder = new CastRecorder(harness, {
    title: options.title ?? "Garazyk Dashboard — Headless Capture",
    minFrameInterval: 30,
  });

  // 7. Wire key handler (emitKey already calls render() after the callback)
  harness.onKey((key: Key) => {
    const completeRun = () => {
      if (!state.runs.active) return;
      const now = Date.now();
      state.runs.active.status = "completed";
      state.runs.active.passed = 1;
      state.runs.active.finishedAt = now;
      const progress = state.runs.progressByRunId[state.runs.active.id];
      if (progress) {
        progress.completed = 1;
        progress.elapsedMs = now - state.runs.active.startedAt;
        progress.running = false;
        progress.updatedAt = now;
        progress.now = now;
      }
      syncAllPanelCounts(panelStates, state);
    };

    handleHeadlessKey(key, focus, panelStates, state, showHelp, () => {
      const panelId = focus.current;
      return panelStates[panelId].itemCount;
    }, {
      onHelpToggle: () => { showHelp = !showHelp; },
      onCompleteRun: completeRun,
      onEnter: (panelId, cursor) => {
        if (panelId === "scenarios") {
          const flatItem = getScenariosItemAt(
            state.scenarios.all,
            state.ux.collapsedCategories,
            state.ux.searchTerm,
            cursor,
          );
          if (!flatItem || flatItem.type !== "scenario") return;
          const startedAt = Date.now();
          state.runs.active = {
            id: "run-" + startedAt,
            startedAt,
            status: "running",
            totalScenarios: 1,
            passed: 0,
            failed: 0,
            skipped: 0,
          };
          state.runs.progressByRunId[state.runs.active.id] = {
            exists: true,
            runId: state.runs.active.id,
            total: 1,
            completed: 0,
            currentScenario: flatItem.label,
            currentScenarioId: flatItem.key,
            elapsedMs: 0,
            updatedAt: startedAt,
            now: startedAt,
            running: true,
          };
          state.ux.busy = false;
          syncAllPanelCounts(panelStates, state);
        }
      },
    });
  });

  // 8. Replay steps (recorder constructor already captured the initial frame)
  await replayScript(harness, options.steps, { speed: options.speed ?? 2 });

  // 9. Close recorder and write cast from in-memory data
  await recorder.close();
  const castContent = recorder.exportAsciicast();
  const castPath = join(outputDir, "dashboard.cast");
  await Deno.writeTextFile(castPath, castContent);

  // 10. Export HTML
  const html = buildExportHtml({
    runId: "headless-capture",
    castContent,
    events: [],
    startedAt: Date.now(),
  });

  const htmlPath = join(outputDir, "index.html");
  await Deno.writeTextFile(htmlPath, html);

  return { castPath, htmlPath };
}

// ---------------------------------------------------------------------------
// Key handling
// ---------------------------------------------------------------------------

export interface KeyHandlerCallbacks {
  onHelpToggle: () => void;
  /** Called when Enter is pressed in a panel. Receives panel ID and cursor index. */
  onEnter?: (panelId: PanelId, cursor: number) => void;
  /** Called when 'c' is pressed — completes the active run with "passed" status. */
  onCompleteRun?: () => void;
  /** Open the run detail overlay for a given run. */
  onViewDetail?: (runId: string, run: Run) => void;
  /** Close the run detail overlay. */
  onCloseDetail?: () => void;
}

export function handleHeadlessKey(
  key: Key,
  focus: FocusRing,
  panelStates: PanelStates,
  state: DashboardState,
  showHelp: boolean,
  getVisibleCount: () => number,
  callbacks: KeyHandlerCallbacks,
): void {
  // Help overlay dismisses on any key
  if (showHelp) {
    callbacks.onHelpToggle();
    return;
  }

  // Run detail overlay — intercept all keys when active
  if (state.runs.detailRunId) {
    if (isKey(key, Keys.ESCAPE) || isKey(key, "q")) {
      callbacks.onCloseDetail?.();
    }
    // All other keys consumed by overlay
    return;
  }

  // Quit
  if (isQuit(key) || isKey(key, Keys.ESCAPE)) return;

  // Tab navigation
  if (isKey(key, Keys.TAB) && !key.shift) { focus.next(); return; }
  if (isKey(key, Keys.TAB) && key.shift) { focus.prev(); return; }

  // Panel jumps (1-4)
  if (!key.ctrl && !key.alt && !key.shift) {
    const num = parseInt(key.key);
    if (num >= 1 && num <= 4) { focus.jump(num - 1); return; }
  }

  // Help toggle
  if (isKey(key, "?")) { callbacks.onHelpToggle(); return; }

  // Complete active run (headless capture only)
  if (isKey(key, "c") && !key.ctrl && !key.alt && !key.shift) {
    callbacks.onCompleteRun?.();
    return;
  }

  // v — view log for selected history entry
  if (isKey(key, "v") && !key.ctrl && !key.alt && !key.shift) {
    const panelId = focus.current;
    if (panelId === "history") {
      const run = state.runs.active ?? state.runs.recentRuns[panelStates.history.cursor];
      if (run) callbacks.onViewDetail?.(run.id, run);
    }
    return;
  }

  // Enter — panel-specific actions
  if (isKey(key, Keys.ENTER)) {
    const panelId = focus.current;
    if (panelId === "history") {
      const run = state.runs.recentRuns[panelStates.history.cursor];
      if (run) callbacks.onViewDetail?.(run.id, run);
    } else {
      callbacks.onEnter?.(panelId, panelStates[panelId].cursor);
    }
    return;
  }

  // Arrow keys for cursor navigation
  const panelId = focus.current;
  if (isKey(key, Keys.UP)) {
    panelStates[panelId] = moveCursorUp(panelStates[panelId], getVisibleCount());
    return;
  }
  if (isKey(key, Keys.DOWN)) {
    panelStates[panelId] = moveCursorDown(panelStates[panelId], getVisibleCount());
    return;
  }
}

// ---------------------------------------------------------------------------
// Panel state helpers
// ---------------------------------------------------------------------------

export function syncAllPanelCounts(
  panelStates: PanelStates,
  state: DashboardState,
): void {
  for (const id of PANEL_IDS) {
    let count = 0;
    switch (id) {
      case "network":
        count = state.network.services.length;
        break;
      case "scenarios":
        count = getScenariosItemCount(state.scenarios.all, state.ux.collapsedCategories, state.ux.searchTerm);
        break;
      case "run":
        count = state.runs.active ? 1 : 0;
        break;
      case "history":
        count = state.runs.recentRuns.length;
        break;
    }
    panelStates[id] = clampPanelState(panelStates[id], count, 10);
  }
}

// ---------------------------------------------------------------------------
// Default seed state
// ---------------------------------------------------------------------------

export function seedDefaultState(): DashboardState {
  const state = createInitialState();

  state.network.services = [
    { name: "pds", label: "PDS", url: "http://localhost:2583", port: 2583, status: "running", healthy: true },
    { name: "relay", label: "Relay", url: "http://localhost:2489", port: 2489, status: "starting", healthy: undefined },
    { name: "plc", label: "PLC", url: "http://localhost:2582", port: 2582, status: "stopped", healthy: undefined },
    { name: "appview", label: "AppView", url: "http://localhost:2584", port: 2584, status: "running", healthy: true },
  ];

  state.scenarios.all = [
    { id: "01_account_lifecycle", name: "01_account_lifecycle", description: "Creates accounts and registers handles", category: "identity", needsPds2: false, lastStatus: "passed" },
    { id: "02_social_graph", name: "02_social_graph", description: "Creates follow records between accounts", category: "social", needsPds2: true, lastStatus: "failed" },
    { id: "03_content_creation", name: "03_content_creation", description: "Creates posts, reposts, and likes", category: "content", needsPds2: false, lastStatus: "passed" },
    { id: "04_federation", name: "04_federation", description: "Verifies cross-PDS record propagation", category: "federation", needsPds2: true, lastStatus: "skipped" },
  ];

  state.runs.active = null;

  state.runs.recentRuns = [
    { id: "run-20260524-001", startedAt: Date.now() - 120000, finishedAt: Date.now() - 60000, status: "completed", totalScenarios: 12, passed: 11, failed: 1, skipped: 0 },
    { id: "run-20260524-002", startedAt: Date.now() - 60000, finishedAt: Date.now() - 10000, status: "completed", totalScenarios: 8, passed: 8, failed: 0, skipped: 0 },
  ];

  return state;
}

// ---------------------------------------------------------------------------
// Scenario scripts
// ---------------------------------------------------------------------------

/** Build steps to select and run a scenario by its flat-list index. */
export function runScenarioScript(
  flatIndex: number,
  scenarioName: string,
): ReplayStep[] {
  const steps: ReplayStep[] = [
    { t: 0.5, kind: "marker", label: "Dashboard loaded" },
    { t: 1.2, kind: "key", key: "tab" },
    { t: 1.5, kind: "marker", label: "Focused: Scenarios panel" },
  ];

  for (let i = 0; i < flatIndex; i++) {
    steps.push({ t: 1.8 + i * 0.35, kind: "key", key: "down" });
  }

  const base = 1.8 + flatIndex * 0.35;
  steps.push(
    { t: base, kind: "marker", label: `${scenarioName} selected` },
    { t: base + 0.5, kind: "key", key: "enter" },
    { t: base + 1.0, kind: "marker", label: "Run started — running" },
    { t: base + 3.0, kind: "key", key: "c" },
    { t: base + 3.5, kind: "marker", label: "Run completed — passed" },
    { t: base + 4.0, kind: "key", key: "tab" },
    { t: base + 4.5, kind: "marker", label: "Active Run panel (completed)" },
    { t: base + 5.0, kind: "key", key: "tab" },
    { t: base + 5.5, kind: "marker", label: "Run History" },
    { t: base + 6.0, kind: "key", key: "1" },
    { t: base + 6.5, kind: "marker", label: "Back to Network" },
  );

  return steps;
}

// ---------------------------------------------------------------------------
// Demo scripts
// ---------------------------------------------------------------------------

/** Navigate through panels, show help overlay. */
export function demoScript(): ReplayStep[] {
  return [
    { t: 0.5, kind: "marker", label: "Dashboard loaded" },
    { t: 1.0, kind: "key", key: "tab" },
    { t: 1.2, kind: "marker", label: "Focused: Scenarios" },
    { t: 1.5, kind: "key", key: "down" },
    { t: 1.8, kind: "key", key: "down" },
    { t: 2.0, kind: "marker", label: "Scenarios list scrolled" },
    { t: 2.5, kind: "key", key: "tab" },
    { t: 2.8, kind: "marker", label: "Focused: Active Run" },
    { t: 3.3, kind: "key", key: "tab" },
    { t: 3.6, kind: "marker", label: "Focused: Run History" },
    { t: 3.9, kind: "key", key: "down" },
    { t: 4.2, kind: "key", key: "down" },
    { t: 4.7, kind: "key", key: "1" },
    { t: 5.0, kind: "marker", label: "Back to Network" },
    { t: 5.5, kind: "key", key: "?" },
    { t: 6.0, kind: "marker", label: "Help overlay" },
    { t: 6.5, kind: "key", key: "?" },
    { t: 7.0, kind: "marker", label: "Capture complete" },
  ];
}

/**
 * Focus on running the first e2e test: tab to Scenarios, scroll to
 * the first scenario item, press Enter to start the run, wait for
 * completion (press 'c'), then navigate through the panels.
 */
export function e2eTestScript(): ReplayStep[] {
  return [
    { t: 0.5, kind: "marker", label: "Dashboard loaded" },
    { t: 1.2, kind: "key", key: "tab" },
    { t: 1.5, kind: "marker", label: "Focused: Scenarios panel" },
    { t: 2.0, kind: "key", key: "down" },
    { t: 2.5, kind: "marker", label: "First scenario selected" },
    { t: 3.0, kind: "key", key: "enter" },
    { t: 3.5, kind: "marker", label: "Run started — running" },
    { t: 5.0, kind: "key", key: "c" },
    { t: 5.5, kind: "marker", label: "Run completed — passed" },
    { t: 6.0, kind: "key", key: "tab" },
    { t: 6.5, kind: "marker", label: "Focused: Active Run panel (completed)" },
    { t: 7.0, kind: "key", key: "tab" },
    { t: 7.5, kind: "marker", label: "Focused: Run History" },
    { t: 8.0, kind: "key", key: "1" },
    { t: 8.5, kind: "marker", label: "Back to Network" },
  ];
}

// ---------------------------------------------------------------------------
// Main entry
// ---------------------------------------------------------------------------

if (import.meta.main) {
  const args = Deno.args;
  const outputDir = args.find((a) => !a.startsWith("--")) ?? "scripts/scenarios/reports/headless-capture";
  const speedArg = args.find((a) => a.startsWith("--speed="));
  const speed = speedArg ? parseFloat(speedArg.split("=")[1]!) : undefined;
  const scenarioArg = args.find((a) => a.startsWith("--scenario="));
  const scenarioIdx = scenarioArg ? parseInt(scenarioArg.split("=")[1]!, 10) : NaN;
  const scenarioNameArg = args.find((a) => a.startsWith("--scenario-name="));
  const scenarioName = scenarioNameArg ? scenarioNameArg.split("=")[1]! : `Scenario ${scenarioIdx}`;

  let steps: ReplayStep[];
  let title: string;

  if (!isNaN(scenarioIdx)) {
    steps = runScenarioScript(scenarioIdx, scenarioName);
    title = `Garazyk Dashboard — Running ${scenarioName}`;
  } else if (args.includes("--e2e")) {
    steps = e2eTestScript();
    title = "Garazyk Dashboard — Running first E2E test";
  } else {
    steps = demoScript();
    title = "Garazyk Dashboard — Headless Demo";
  }

  const result = await captureHeadlessReplay({
    outputDir,
    steps,
    title,
    speed,
  });
  console.log(`[capture] Cast: ${result.castPath}`);
  console.log(`[capture] HTML: ${result.htmlPath}`);
}
