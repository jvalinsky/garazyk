import { ScreenBuffer, FocusRing } from "@garazyk/tui";
import { dashboardLayoutTree, solveLayout, findPanel, panelContentArea } from "@garazyk/tui";
import type { ResolvedNode } from "@garazyk/tui";
import { VirtualTuiHarness } from "@garazyk/tui/testing";
import type { CastRecorder } from "@garazyk/tui/testing";
import { createPanelStates, clampPanelState } from "../scenario-dashboard/tui/panel_state.ts";
import type { PanelStates } from "../scenario-dashboard/tui/panel_state.ts";
import { renderView } from "../scenario-dashboard/tui/view.ts";
import { seedDefaultState, handleHeadlessKey, syncAllPanelCounts } from "../scenario-dashboard/tui_headless_capture.ts";
import type { DashboardState } from "../scenario-dashboard/dashboard_state.ts";
import { getScenariosItemAt } from "../scenario-dashboard/tui/panels/scenarios.ts";
import { buildSnapshot } from "./snapshot.ts";
import { RefManager } from "./refs.ts";
import { startRecording, stopRecording } from "./recording.ts";
import type { RecordingHandle } from "./recording.ts";
import type { ElementMeta } from "../scenario-dashboard/tui_types.ts";

const WIDTH = 120;
const HEIGHT = 30;

export interface TuiSession {
  harness: VirtualTuiHarness;
  buf: ScreenBuffer;
  state: DashboardState;
  panelStates: PanelStates;
  focus: FocusRing;
  showHelp: boolean;
  layout: ResolvedNode;
  refs: RefManager;
  recording: RecordingHandle | null;
  lastMeta: Map<string, ElementMeta>;
}

export function createSession(): TuiSession {
  const buf = new ScreenBuffer(WIDTH, HEIGHT, { noColor: true });
  const tree = dashboardLayoutTree(WIDTH, HEIGHT);
  if (!tree) throw new Error("Cannot solve layout at " + WIDTH + "x" + HEIGHT);

  const layout = solveLayout(tree, { x: 0, y: 0, width: WIDTH, height: HEIGHT });
  const state = seedDefaultState();
  const focus = new FocusRing();
  const panelStates = createPanelStates();
  syncAllPanelCounts(panelStates, state);

  let showHelp = false;

  let lastMeta = new Map<string, ElementMeta>();

  const render = (b: ScreenBuffer) => {
    const { meta } = renderView(b, state, layout, focus, panelStates, state.runs.recentRuns, showHelp);
    lastMeta = meta;
  };

  const harness = new VirtualTuiHarness(WIDTH, HEIGHT, render, { noColor: true });

  harness.onKey((key) => {
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
      onViewDetail: (runId, run) => {
        state.runs.detailRunId = runId;
        state.runs.detailRun = run;
        state.runs.detailResults = [
          { scenarioId: "01_account_lifecycle", scenarioName: "01_account_lifecycle", status: "passed", passed: 5, failed: 0, skipped: 0, durationMs: 500, steps: [], artifacts: null },
          { scenarioId: "02_social_graph", scenarioName: "02_social_graph", status: run.failed > 0 ? "failed" : "passed", passed: 4, failed: run.failed > 0 ? 1 : 0, skipped: 0, durationMs: 400, steps: [], artifacts: null }
        ];
        state.runs.detailCursor = 0;
        state.runs.detailScrollOffset = 0;
      },
      onCloseDetail: () => {
        state.runs.detailRunId = null;
        state.runs.detailRun = null;
        state.runs.detailResults = [];
        state.runs.detailCursor = 0;
        state.runs.detailScrollOffset = 0;
      },
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

  return {
    harness,
    buf,
    state,
    panelStates,
    focus,
    showHelp,
    layout,
    refs: new RefManager(),
    recording: null,
    get lastMeta() { return lastMeta; }
  };
}

export function sessionSnapshot(
  session: TuiSession,
  options: { boxes?: boolean; panel?: string } = {},
): string {
  return buildSnapshot(
    session,
    session.lastMeta,
    options,
  );
}

export async function sessionPressKey(
  session: TuiSession,
  keyName: string,
): Promise<string> {
  await session.harness.emitKey(keyName);
  return sessionSnapshot(session);
}

export async function sessionType(
  session: TuiSession,
  text: string,
): Promise<string> {
  for (const ch of text) {
    await session.harness.emitKey(ch);
  }
  return sessionSnapshot(session);
}

export async function sessionStartRecording(
  session: TuiSession,
  title: string | undefined,
  outputDir: string | undefined,
  baseDir: string,
): Promise<void> {
  if (session.recording) {
    throw new Error("Already recording — ignoring duplicate start");
  }
  session.recording = startRecording(session.harness, title, outputDir, baseDir);
}

export async function sessionStopRecording(
  session: TuiSession,
): Promise<{ castPath: string; htmlPath: string }> {
  if (!session.recording) {
    throw new Error("No active recording — call tui_rec_start first");
  }
  const result = await stopRecording(session.recording, session.harness);
  session.recording = null;
  return result;
}
