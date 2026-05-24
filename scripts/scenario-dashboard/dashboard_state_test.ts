/**
 * Unit tests for the sans-IO dashboard state machine.
 *
 * These tests exercise the pure update() function without any I/O.
 * All effects are verified as Cmd values — no fetch, no timers.
 */

import { assert, assertEquals } from "@std/assert";
import {
  bootCmds,
  type Cmd,
  createInitialState,
  type DashboardState,
  type Msg,
  update,
} from "./dashboard_state.ts";
import type { Run, ScenarioResultView, ServiceStatus } from "./services/types.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function initState(overrides?: Partial<DashboardState>): DashboardState {
  return createInitialState(overrides);
}

function step(state: DashboardState, msg: Msg): [DashboardState, Cmd[]] {
  return update(state, msg);
}

/** Apply a sequence of messages and return the final state + all cmds */
function _reduce(state: DashboardState, msgs: Msg[]): [DashboardState, Cmd[]] {
  let s = state;
  let allCmds: Cmd[] = [];
  for (const msg of msgs) {
    const [next, cmds] = update(s, msg);
    s = next;
    allCmds = allCmds.concat(cmds);
  }
  return [s, allCmds];
}

function _findCmd(cmds: Cmd[], type: string): Cmd | undefined {
  return cmds.find((c) => c.type === type);
}

function fetchCmds(cmds: Cmd[]): Extract<Cmd, { type: "fetch" }>[] {
  return cmds.filter((c): c is Extract<Cmd, { type: "fetch" }> => c.type === "fetch");
}

function scheduleCmds(cmds: Cmd[]): Cmd[] {
  return cmds.filter((c) => c.type === "schedule");
}

// ---------------------------------------------------------------------------
// Initial state
// ---------------------------------------------------------------------------

Deno.test("createInitialState: returns valid default state", () => {
  const state = initState();
  assertEquals(state.network.services, []);
  assertEquals(state.runs.active, null);
  assertEquals(state.scenarios.all, []);
  assertEquals(state.topology.selected, "garazyk-default");
  assertEquals(state.ux.busy, false);
  assertEquals(state.ux.settingsOpen, false);
  assertEquals(state.ux.agentLaunch, false);
  assertEquals(state.ux.agentMode, false);
  assertEquals(state.ux.collapsedCategories, new Set(["edge"]));
});

// ---------------------------------------------------------------------------
// Network health
// ---------------------------------------------------------------------------

Deno.test("network/healthReceived: updates services and schedules next check", () => {
  const state = initState();
  const services: ServiceStatus[] = [
    {
      name: "pds",
      label: "PDS",
      url: "http://localhost:2583",
      port: 2583,
      status: "running",
      healthy: true,
    },
  ];
  const [next, cmds] = step(state, { type: "network/healthReceived", services });
  assertEquals(next.network.services, services);
  assertEquals(next.network.healthCheckInFlight, false);
  assertEquals(scheduleCmds(cmds).length, 1);
});

Deno.test("network/healthFailed: backs off delay", () => {
  const state = initState();
  const [next, cmds] = step(state, { type: "network/healthFailed", error: "timeout" });
  assertEquals(next.network.healthCheckInFlight, false);
  assertEquals(next.network.healthCheckDelayMs, 10000); // 5000 * 2
  assertEquals(scheduleCmds(cmds).length, 1);
});

Deno.test("network/healthTimeout: dispatches fetch when not in-flight", () => {
  const state = initState();
  const [next, cmds] = step(state, { type: "network/healthTimeout" });
  assertEquals(next.network.healthCheckInFlight, true);
  assertEquals(fetchCmds(cmds).length, 1);
  assertEquals(fetchCmds(cmds)[0].url, "/api/network/health");
});

Deno.test("network/healthTimeout: deduplicates when already in-flight", () => {
  const state = initState();
  const [inFlight] = step(state, { type: "network/healthTimeout" });
  const [next, cmds] = step(inFlight, { type: "network/healthTimeout" });
  assertEquals(next.network.healthCheckInFlight, true);
  assertEquals(cmds.length, 0); // no duplicate fetch
});

// ---------------------------------------------------------------------------
// Network control
// ---------------------------------------------------------------------------

Deno.test("network/startRequested: sets busy and dispatches POST", () => {
  const state = initState();
  const [next, cmds] = step(state, { type: "network/startRequested", pds2: false });
  assertEquals(next.ux.busy, true);
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals(cmd.url, "/api/network/start");
  assertEquals(cmd.method, "POST");
});

Deno.test("network/startSucceeded: clears busy and re-fetches health", () => {
  const state = initState({
    ux: {
      busy: true,
      settingsOpen: false,
      mobileNavPanel: null,
      scenarioParams: {},
      collapsedCategories: new Set(),
      searchTerm: "",
      runner: "host",
      agentLaunch: false,
      agentMode: false,
    },
    lastTickMs: 0,
  });
  const [next, cmds] = step(state, { type: "network/startSucceeded" });
  assertEquals(next.ux.busy, false);
  assertEquals(fetchCmds(cmds).length, 1);
  assertEquals(fetchCmds(cmds)[0].url, "/api/network/health");
});

Deno.test("network/startFailed: clears busy", () => {
  const state = initState({
    ux: {
      busy: true,
      settingsOpen: false,
      mobileNavPanel: null,
      scenarioParams: {},
      collapsedCategories: new Set(),
      searchTerm: "",
      runner: "host",
      agentLaunch: false,
      agentMode: false,
    },
    lastTickMs: 0,
  });
  const [next] = step(state, { type: "network/startFailed", error: "fail" });
  assertEquals(next.ux.busy, false);
});

// ---------------------------------------------------------------------------
// Active run
// ---------------------------------------------------------------------------

Deno.test("runs/activeReceived: stores run and schedules next poll", () => {
  const state = initState();
  const run: Run = {
    id: "run-1",
    startedAt: Date.now() / 1000,
    status: "running",
    totalScenarios: 5,
    passed: 0,
    failed: 0,
    skipped: 0,
  };
  const [next, cmds] = step(state, { type: "runs/activeReceived", run });
  assertEquals(next.runs.active, run);
  assertEquals(scheduleCmds(cmds).length, 4);
});

Deno.test("runs/activeReceived: uses longer delay when idle", () => {
  const state = initState();
  const run: Run = {
    id: "run-1",
    startedAt: Date.now() / 1000,
    status: "completed",
    totalScenarios: 5,
    passed: 5,
    failed: 0,
    skipped: 0,
  };
  const [_next3, cmds] = step(state, { type: "runs/activeReceived", run });
  const sched = scheduleCmds(cmds)[0];
  assert(sched && sched.type === "schedule");
  assertEquals(sched.delayMs, 10000); // 5x base when idle
});

Deno.test("runs/activeTimeout: deduplicates when in-flight", () => {
  const state = initState();
  const [inFlight] = step(state, { type: "runs/activeTimeout" });
  const [_next2, cmds] = step(inFlight, { type: "runs/activeTimeout" });
  assertEquals(cmds.length, 0);
});

Deno.test("runs polling: active and progress in-flight flags are independent", () => {
  const run: Run = {
    id: "run-1",
    startedAt: Date.now(),
    status: "running",
    totalScenarios: 2,
    passed: 0,
    failed: 0,
    skipped: 0,
  };
  const state = initState({ runs: { ...initState().runs, active: run, viewedRunId: run.id } });
  const [activePolling] = step(state, { type: "runs/activeTimeout" });
  assertEquals(activePolling.runs.activeInFlight, true);
  assertEquals(activePolling.runs.progressInFlight, false);

  const [progressPolling, cmds] = step(activePolling, {
    type: "runs/progressTimeout",
    runId: run.id,
  });
  assertEquals(progressPolling.runs.activeInFlight, true);
  assertEquals(progressPolling.runs.progressInFlight, true);
  assertEquals(fetchCmds(cmds)[0].url, "/api/runs/run-1/progress");
});

Deno.test("runs/activeReceived: run switch invalidates stale in-flight polls", () => {
  // Set up: run-A is active with progress and logs in flight
  const runA: Run = {
    id: "run-A",
    startedAt: Date.now(),
    status: "running",
    totalScenarios: 2,
    passed: 0,
    failed: 0,
    skipped: 0,
  };
  const state = initState({ runs: { ...initState().runs, active: runA, viewedRunId: runA.id } });

  // Start progress polling for run-A
  const [progressStarted] = step(state, { type: "runs/progressTimeout", runId: runA.id });
  assertEquals(progressStarted.runs.progressInFlight, true);
  assertEquals(progressStarted.runs.progressInFlightRunId, "run-A");

  // Start logs polling for run-A
  const [logsStarted] = step(progressStarted, { type: "logs/timeout", runId: runA.id });
  assertEquals(logsStarted.logs.fetchInFlight, true);
  assertEquals(logsStarted.logs.inFlightRunId, "run-A");

  // Now run-B becomes active (run switch)
  const runB: Run = {
    id: "run-B",
    startedAt: Date.now(),
    status: "running",
    totalScenarios: 3,
    passed: 0,
    failed: 0,
    skipped: 0,
  };
  const [next, cmds] = step(logsStarted, { type: "runs/activeReceived", run: runB });

  // Stale in-flight flags should be cleared
  assertEquals(next.runs.progressInFlight, false);
  assertEquals(next.runs.progressInFlightRunId, null);
  assertEquals(next.logs.fetchInFlight, false);
  assertEquals(next.logs.inFlightRunId, null);

  // New polls for run-B should be scheduled
  const schedCmdTypes = scheduleCmds(cmds).map((c) => {
    if (c.type === "schedule" && c.msg && "type" in c.msg) return c.msg.type;
    return "";
  });
  assert(schedCmdTypes.includes("runs/progressTimeout"), "should schedule progress for run-B");
  assert(schedCmdTypes.includes("logs/timeout"), "should schedule logs for run-B");
  assert(schedCmdTypes.includes("metrics/timeout"), "should schedule metrics for run-B");
});

Deno.test("runs/progressReceived: ignores stale token response", () => {
  const run: Run = {
    id: "run-1",
    startedAt: Date.now(),
    status: "running",
    totalScenarios: 2,
    passed: 0,
    failed: 0,
    skipped: 0,
  };
  const [polling] = step(initState({ runs: { ...initState().runs, active: run } }), {
    type: "runs/progressTimeout",
    runId: run.id,
  });
  const stale = {
    exists: true,
    runId: run.id,
    total: 2,
    completed: 1,
    currentScenario: "old",
    currentScenarioId: "01",
    elapsedMs: 1,
    updatedAt: 1,
    now: 1,
    running: true,
  };
  const [next, cmds] = step(polling, {
    type: "runs/progressReceived",
    runId: run.id,
    token: 999,
    progress: stale,
  });
  assertEquals(next.runs.progressByRunId[run.id], undefined);
  assertEquals(next.runs.progressInFlight, true);
  assertEquals(cmds.length, 0);
});

// ---------------------------------------------------------------------------
// Run control
// ---------------------------------------------------------------------------

Deno.test("runs/startRequested: dispatches POST with correct body", () => {
  const state = initState();
  const [next, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["01", "05"],
    pds2: true,
  });
  assertEquals(next.ux.busy, true);
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals(cmd.url, "/api/runs/start");
  assertEquals(cmd.method, "POST");
});

Deno.test("runs/startRequested: guarded while active run exists", () => {
  const run: Run = {
    id: "run-1",
    startedAt: 0,
    status: "running",
    totalScenarios: 1,
    passed: 0,
    failed: 0,
    skipped: 0,
  };
  const state = initState({ runs: { ...initState().runs, active: run } });
  const [next, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["02"],
    pds2: false,
  });
  assertEquals(next.ux.busy, false);
  assertEquals(cmds.length, 0);
});

Deno.test("runs/startSucceeded: navigates to run page", () => {
  const state = initState({
    ux: {
      busy: true,
      settingsOpen: false,
      mobileNavPanel: null,
      scenarioParams: {},
      collapsedCategories: new Set(),
      searchTerm: "",
      runner: "host",
      agentLaunch: false,
      agentMode: false,
    },
    lastTickMs: 0,
  });
  const [next, cmds] = step(state, { type: "runs/startSucceeded", runId: "run-42" });
  assertEquals(next.ux.busy, false);
  const nav = cmds.find((c) => c.type === "navigate");
  assert(nav && nav.type === "navigate");
  assertEquals(nav.url, "/run/run-42");
});

Deno.test("runs/stopRequested: dispatches POST to stop endpoint", () => {
  const run: Run = {
    id: "run-1",
    startedAt: 0,
    status: "running",
    totalScenarios: 1,
    passed: 0,
    failed: 0,
    skipped: 0,
  };
  const base = initState();
  const state = initState({ runs: { ...base.runs, active: run }, lastTickMs: 0 });
  const [next, cmds] = step(state, { type: "runs/stopRequested" });
  assertEquals(next.ux.busy, true);
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals(cmd.url, "/api/runs/run-1/stop");
});

Deno.test("network/stopRequested: guarded while run is active", () => {
  const run: Run = {
    id: "run-1",
    startedAt: 0,
    status: "running",
    totalScenarios: 1,
    passed: 0,
    failed: 0,
    skipped: 0,
  };
  const state = initState({ runs: { ...initState().runs, active: run } });
  const [next, cmds] = step(state, { type: "network/stopRequested" });
  assertEquals(next.ux.busy, false);
  assertEquals(cmds.length, 0);
});

// ---------------------------------------------------------------------------
// Topology
// ---------------------------------------------------------------------------

Deno.test("topology/selected: updates selection and fetches preview", () => {
  const state = initState();
  const [next, cmds] = step(state, { type: "topology/selected", name: "minimal" });
  assertEquals(next.topology.selected, "minimal");
  assertEquals(next.topology.previewInFlight, true);
  assertEquals(fetchCmds(cmds).length, 1);
  assertEquals(fetchCmds(cmds)[0].url, "/api/topologies/minimal");
});

Deno.test("topology/selected: no-op when same topology", () => {
  const state = initState();
  const [next, cmds] = step(state, { type: "topology/selected", name: "garazyk-default" });
  assertEquals(cmds.length, 0);
  assertEquals(next.topology.previewInFlight, false);
});

Deno.test("topology/selected: guarded while active run exists", () => {
  const run: Run = {
    id: "run-1",
    startedAt: 0,
    status: "running",
    totalScenarios: 1,
    passed: 0,
    failed: 0,
    skipped: 0,
  };
  const state = initState({ runs: { ...initState().runs, active: run } });
  const [next, cmds] = step(state, { type: "topology/selected", name: "minimal" });
  assertEquals(next.topology.selected, "garazyk-default");
  assertEquals(cmds.length, 0);
});

Deno.test("logs/failed: stores error by run id", () => {
  const state = initState({
    logs: {
      textByRunId: {},
      lastErrorByRunId: {},
      fetchInFlight: true,
      inFlightRunId: "run-A",
      token: 1,
      delayMs: 5000,
      lastUpdateMs: 0,
    },
  });
  const [next] = step(state, {
    type: "logs/failed",
    error: "Run logs are not available.",
    runId: "run-A",
    token: 1,
  });
  assertEquals(
    next.logs.lastErrorByRunId["run-A"],
    "Run logs are not available.",
  );
  assertEquals(next.logs.fetchInFlight, false);
});

Deno.test("logs: stores text by viewed run id", () => {
  const [polling] = step(initState({ runs: { ...initState().runs, viewedRunId: "old-run" } }), {
    type: "logs/timeout",
  });
  const [next] = step(polling, {
    type: "logs/received",
    runId: "old-run",
    token: polling.logs.token,
    text: "old logs",
  });
  assertEquals(next.logs.textByRunId["old-run"], "old logs");
  assertEquals(next.logs.textByRunId["other-run"], undefined);
});

// ---------------------------------------------------------------------------
// UX
// ---------------------------------------------------------------------------

Deno.test("ux/toggleMobileNav: opens and closes drawer panel", () => {
  const state = initState();
  const [open] = step(state, { type: "ux/toggleMobileNav", panel: "scenarios" });
  assertEquals(open.ux.mobileNavPanel, "scenarios");
  const [closed] = step(open, { type: "ux/toggleMobileNav", panel: "scenarios" });
  assertEquals(closed.ux.mobileNavPanel, null);
  const [network] = step(closed, { type: "ux/toggleMobileNav", panel: "network" });
  assertEquals(network.ux.mobileNavPanel, "network");
  const [close] = step(network, { type: "ux/closeMobileNav" });
  assertEquals(close.ux.mobileNavPanel, null);
});

Deno.test("ux/toggleSettings: toggles settings modal", () => {
  const state = initState();
  const [next1] = step(state, { type: "ux/toggleSettings" });
  assertEquals(next1.ux.settingsOpen, true);
  const [next2] = step(next1, { type: "ux/toggleSettings" });
  assertEquals(next2.ux.settingsOpen, false);
});

Deno.test("ux/setScenarioParam: updates parameter", () => {
  const state = initState();
  const [next] = step(state, { type: "ux/setScenarioParam", key: "accountCount", value: 5 });
  assertEquals(next.ux.scenarioParams.accountCount, 5);
});

Deno.test("ux/toggleCategory: toggles collapsed state", () => {
  const state = initState();
  // "edge" starts collapsed
  const [next1] = step(state, { type: "ux/toggleCategory", category: "edge" });
  assertEquals(next1.ux.collapsedCategories.has("edge"), false);
  const [next2] = step(next1, { type: "ux/toggleCategory", category: "edge" });
  assertEquals(next2.ux.collapsedCategories.has("edge"), true);
});

Deno.test("ux/setSearchTerm: updates search term", () => {
  const state = initState();
  const [next] = step(state, { type: "ux/setSearchTerm", term: "account" });
  assertEquals(next.ux.searchTerm, "account");
});

// ---------------------------------------------------------------------------
// Tick
// ---------------------------------------------------------------------------

Deno.test("tick: updates elapsed time counters", () => {
  const state = initState();
  const [next1] = step(state, { type: "tick", nowMs: 1000 });
  assertEquals(next1.lastTickMs, 1000);
  assertEquals(next1.network.lastHealthCheckMs, 1000);
  const [next2] = step(next1, { type: "tick", nowMs: 3000 });
  assertEquals(next2.lastTickMs, 3000);
  assertEquals(next2.network.lastHealthCheckMs, 3000); // 1000 + 2000 delta
});

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

Deno.test("bootCmds: returns initial fetch commands", () => {
  const cmds = bootCmds();
  assertEquals(cmds.length, 6);
  const urls = fetchCmds(cmds).map((c) => c.url);
  assertEquals(urls.includes("/api/network/health"), true);
  assertEquals(urls.includes("/api/runs/active"), true);
  assertEquals(urls.includes("/api/scenarios"), true);
  assertEquals(urls.includes("/api/topologies"), true);
  assertEquals(urls.includes("/api/config"), true);
  assertEquals(urls.includes("/api/runs/recent?limit=6"), true);
});

// ---------------------------------------------------------------------------
// Recent runs polling
// ---------------------------------------------------------------------------

Deno.test("runs/recentTimeout: dispatches fetch when not in-flight", () => {
  const state = initState();
  const [next, cmds] = step(state, { type: "runs/recentTimeout" });
  assertEquals(next.runs.recentInFlight, true);
  assertEquals(fetchCmds(cmds).length, 1);
  assertEquals(fetchCmds(cmds)[0].url, "/api/runs/recent?limit=6");
});

Deno.test("runs/recentTimeout: deduplicates when already in-flight", () => {
  const state = initState();
  const [inFlight] = step(state, { type: "runs/recentTimeout" });
  const [next, cmds] = step(inFlight, { type: "runs/recentTimeout" });
  assertEquals(next.runs.recentInFlight, true);
  assertEquals(cmds.length, 0);
});

Deno.test("runs/recentReceived: stores runs and schedules next poll", () => {
  const state = initState();
  const [polling] = step(state, { type: "runs/recentTimeout" });
  const runs: Run[] = [
    {
      id: "run-1",
      startedAt: Date.now() / 1000,
      status: "completed",
      totalScenarios: 5,
      passed: 5,
      failed: 0,
      skipped: 0,
    },
  ];
  const [next, cmds] = step(polling, {
    type: "runs/recentReceived",
    runs,
    token: polling.runs.recentToken,
  });
  assertEquals(next.runs.recentRuns, runs);
  assertEquals(next.runs.recentInFlight, false);
  assertEquals(scheduleCmds(cmds).length, 1);
});

Deno.test("runs/recentFailed: backs off delay", () => {
  const state = initState();
  const [polling] = step(state, { type: "runs/recentTimeout" });
  const [next, cmds] = step(polling, {
    type: "runs/recentFailed",
    error: "timeout",
    token: polling.runs.recentToken,
  });
  assertEquals(next.runs.recentInFlight, false);
  assertEquals(next.runs.recentDelayMs, 10000); // 5000 * 2
  assertEquals(scheduleCmds(cmds).length, 1);
});

// ---------------------------------------------------------------------------
// Backoff
// ---------------------------------------------------------------------------

Deno.test("backoff: doubles on consecutive failures, caps at max", () => {
  const state = initState();
  // First failure: 5000 * 2 = 10000
  const [s1] = step(state, { type: "network/healthFailed", error: "e1" });
  assertEquals(s1.network.healthCheckDelayMs, 10000);
  // Second failure: 10000 * 2 = 20000
  const [s2] = step(s1, { type: "network/healthFailed", error: "e2" });
  assertEquals(s2.network.healthCheckDelayMs, 20000);
  // Third failure: 20000 * 2 = 30000 (capped)
  const [s3] = step(s2, { type: "network/healthFailed", error: "e3" });
  assertEquals(s3.network.healthCheckDelayMs, 30000);
  // Fourth failure: still 30000
  const [s4] = step(s3, { type: "network/healthFailed", error: "e4" });
  assertEquals(s4.network.healthCheckDelayMs, 30000);
});

Deno.test("backoff: resets on success", () => {
  const state = initState();
  const [s1] = step(state, { type: "network/healthFailed", error: "e1" });
  assertEquals(s1.network.healthCheckDelayMs, 10000);
  // Success resets
  const [s2] = step(s1, { type: "network/healthReceived", services: [] });
  assertEquals(s2.network.healthCheckDelayMs, 5000);
});

// ---------------------------------------------------------------------------
// Run detail overlay — regression tests
// ---------------------------------------------------------------------------

Deno.test("run detail: viewDetail opens overlay and stores run", () => {
  const state = initState();
  const run: Run = {
    id: "r-detail-1",
    status: "completed",
    startedAt: 1000,
    totalScenarios: 3,
    passed: 2,
    failed: 1,
    skipped: 0,
  };
  const [next, cmds] = step(state, { type: "runs/viewDetail", runId: "r-detail-1", run });
  assertEquals(next.runs.detailRunId, "r-detail-1");
  assertEquals(next.runs.detailRun, run);
  assertEquals(next.runs.detailResults, []);
  assertEquals(next.runs.detailCursor, 0);
  assertEquals(next.runs.detailScrollOffset, 0);
  // Should issue a fetch Cmd for the results
  const fetches = fetchCmds(cmds);
  assertEquals(fetches.length, 1);
  assertEquals(fetches[0]!.url, "/api/runs/r-detail-1/results");
  assertEquals(fetches[0]!.onSuccess, "runs/detailResults");
  assertEquals(fetches[0]!.onError, "runs/closeDetail");
});

Deno.test("run detail: closeDetail clears all detail state", () => {
  const run: Run = {
    id: "r-detail-2",
    status: "completed",
    startedAt: 1000,
    totalScenarios: 1,
    passed: 0,
    failed: 1,
    skipped: 0,
  };
  const state = initState({
    runs: {
      ...initState().runs,
      detailRunId: "r-detail-2",
      detailRun: run,
      detailResults: [{
        scenarioId: "01",
        scenarioName: "test",
        status: "failed",
        passed: 0,
        failed: 1,
        skipped: 0,
        durationMs: 500,
        steps: [{ name: "step1", status: "failed", detail: "error msg", duration_ms: 500 }],
        artifacts: null,
      }],
      detailCursor: 0,
      detailScrollOffset: 0,
    },
  });
  const [next, cmds] = step(state, { type: "runs/closeDetail" });
  assertEquals(next.runs.detailRunId, null);
  assertEquals(next.runs.detailRun, null);
  assertEquals(next.runs.detailResults, []);
  assertEquals(next.runs.detailCursor, 0);
  assertEquals(next.runs.detailScrollOffset, 0);
  assertEquals(cmds.length, 0);
});

Deno.test("run detail: detailResults stores results and clamps cursor", () => {
  const state = initState({
    runs: {
      ...initState().runs,
      detailRunId: "r-1",
      detailRun: { id: "r-1", status: "completed", startedAt: 1000, totalScenarios: 3, passed: 1, failed: 2, skipped: 0 },
      detailCursor: 5, // cursor beyond results length
      detailResults: [],
    },
  });
  const results: ScenarioResultView[] = [
    { scenarioId: "01", scenarioName: "a", status: "passed", passed: 1, failed: 0, skipped: 0, durationMs: 100, steps: [], artifacts: null },
    { scenarioId: "02", scenarioName: "b", status: "failed", passed: 0, failed: 1, skipped: 0, durationMs: 200, steps: [{ name: "s1", status: "failed", detail: "err", duration_ms: 200 }], artifacts: null },
  ];
  const [next] = step(state, { type: "runs/detailResults", results });
  assertEquals(next.runs.detailResults, results);
  assertEquals(next.runs.detailCursor, 1); // clamped to last index
});

Deno.test("run detail: detailCursorUp moves cursor up", () => {
  const state = initState({
    runs: {
      ...initState().runs,
      detailRunId: "r-1",
      detailRun: { id: "r-1", status: "completed", startedAt: 1000, totalScenarios: 2, passed: 1, failed: 1, skipped: 0 },
      detailCursor: 2,
      detailResults: [
        { scenarioId: "01", scenarioName: "a", status: "passed", passed: 1, failed: 0, skipped: 0, durationMs: 0, steps: [], artifacts: null },
        { scenarioId: "02", scenarioName: "b", status: "failed", passed: 0, failed: 1, skipped: 0, durationMs: 0, steps: [], artifacts: null },
        { scenarioId: "03", scenarioName: "c", status: "passed", passed: 1, failed: 0, skipped: 0, durationMs: 0, steps: [], artifacts: null },
      ],
    },
  });
  const [next] = step(state, { type: "runs/detailCursorUp" });
  assertEquals(next.runs.detailCursor, 1);
});

Deno.test("run detail: detailCursorDown moves cursor down", () => {
  const state = initState({
    runs: {
      ...initState().runs,
      detailRunId: "r-1",
      detailRun: { id: "r-1", status: "completed", startedAt: 1000, totalScenarios: 2, passed: 1, failed: 1, skipped: 0 },
      detailCursor: 0,
      detailResults: [
        { scenarioId: "01", scenarioName: "a", status: "passed", passed: 1, failed: 0, skipped: 0, durationMs: 0, steps: [], artifacts: null },
        { scenarioId: "02", scenarioName: "b", status: "failed", passed: 0, failed: 1, skipped: 0, durationMs: 0, steps: [], artifacts: null },
      ],
    },
  });
  const [next] = step(state, { type: "runs/detailCursorDown" });
  assertEquals(next.runs.detailCursor, 1);
});

Deno.test("run detail: detailCursorUp clamps at 0", () => {
  const state = initState({
    runs: {
      ...initState().runs,
      detailRunId: "r-1",
      detailRun: { id: "r-1", status: "completed", startedAt: 1000, totalScenarios: 1, passed: 1, failed: 0, skipped: 0 },
      detailCursor: 0,
      detailResults: [
        { scenarioId: "01", scenarioName: "a", status: "passed", passed: 1, failed: 0, skipped: 0, durationMs: 0, steps: [], artifacts: null },
      ],
    },
  });
  const [next] = step(state, { type: "runs/detailCursorUp" });
  assertEquals(next.runs.detailCursor, 0);
});

Deno.test("run detail: detailCursorDown clamps at last index", () => {
  const state = initState({
    runs: {
      ...initState().runs,
      detailRunId: "r-1",
      detailRun: { id: "r-1", status: "completed", startedAt: 1000, totalScenarios: 1, passed: 1, failed: 0, skipped: 0 },
      detailCursor: 0,
      detailResults: [
        { scenarioId: "01", scenarioName: "a", status: "passed", passed: 1, failed: 0, skipped: 0, durationMs: 0, steps: [], artifacts: null },
      ],
    },
  });
  const [next] = step(state, { type: "runs/detailCursorDown" });
  assertEquals(next.runs.detailCursor, 0);
});

Deno.test("run detail: closeDetail on fetch failure (onError path)", () => {
  const run: Run = {
    id: "r-fail",
    status: "completed",
    startedAt: 1000,
    totalScenarios: 1,
    passed: 0,
    failed: 1,
    skipped: 0,
  };
  const state = initState({
    runs: {
      ...initState().runs,
      detailRunId: "r-fail",
      detailRun: run,
      detailResults: [],
      detailCursor: 0,
    },
  });
  // Simulate the error path: constructMsg maps to runs/closeDetail
  const [next] = step(state, { type: "runs/closeDetail" });
  assertEquals(next.runs.detailRunId, null);
  assertEquals(next.runs.detailRun, null);
});

Deno.test("run detail: initial state has null detailRunId and detailRun", () => {
  const state = initState();
  assertEquals(state.runs.detailRunId, null);
  assertEquals(state.runs.detailRun, null);
  assertEquals(state.runs.detailResults, []);
  assertEquals(state.runs.detailCursor, 0);
  assertEquals(state.runs.detailScrollOffset, 0);
});

// ---------------------------------------------------------------------------
// Agent mode + runner e2e flow
// ---------------------------------------------------------------------------

Deno.test("runs/startRequested: reads agentMode: true from ux state", () => {
  const state = initState({ ux: { ...initState().ux, agentMode: true } });
  const [, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["01"],
    pds2: false,
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals(cmd.url, "/api/runs/start");
  assertEquals((cmd.body as Record<string, unknown>).agentMode, true);
});

Deno.test("runs/startRequested: defaults agentMode to false from ux state", () => {
  const state = initState();
  const [, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["01"],
    pds2: false,
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals((cmd.body as Record<string, unknown>).agentMode, false);
});

Deno.test("runs/startRequested: includes runner: host by default", () => {
  const state = initState();
  const [, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["01"],
    pds2: false,
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals((cmd.body as Record<string, unknown>).runner, "host");
});

Deno.test("runs/startRequested: passes runner: docker when requested", () => {
  const state = initState();
  const [, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["01"],
    pds2: false,
    runner: "docker",
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals((cmd.body as Record<string, unknown>).runner, "docker");
});

Deno.test("runs/startRequested: full agent + runner + pds2 + topology body", () => {
  const state = initState({
    topology: { ...initState().topology, selected: "minimal" },
    ux: { ...initState().ux, agentMode: true },
  });
  const [, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["01", "05"],
    pds2: true,
    runner: "docker",
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  const body = cmd.body as Record<string, unknown>;
  assertEquals(body.topology, "minimal");
  assertEquals(body.runner, "docker");
  assertEquals(body.agentMode, true);
  assertEquals(body.pds2, true);
  assertEquals(body.scenarioIds, ["01", "05"]);
  assertEquals(body.binaryMode, false);
});

// ---------------------------------------------------------------------------
// binaryMode derivation from runner
// ---------------------------------------------------------------------------

Deno.test("runs/startRequested: binaryMode=true when runner is host", () => {
  const state = initState();
  const [, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["01"],
    pds2: false,
    runner: "host",
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals((cmd.body as Record<string, unknown>).binaryMode, true);
});

Deno.test("runs/startRequested: binaryMode=false when runner is docker", () => {
  const state = initState();
  const [, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["01"],
    pds2: false,
    runner: "docker",
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals((cmd.body as Record<string, unknown>).binaryMode, false);
});

Deno.test("runs/startRequested: binaryMode=true when runner defaults to host", () => {
  const state = initState();
  const [, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["01"],
    pds2: false,
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals((cmd.body as Record<string, unknown>).binaryMode, true);
});

// ---------------------------------------------------------------------------
// network/startRequested and network/stopRequested runner passthrough
// ---------------------------------------------------------------------------

Deno.test("network/startRequested: passes runner to POST body", () => {
  const state = initState();
  const [, cmds] = step(state, {
    type: "network/startRequested",
    pds2: false,
    runner: "host",
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals(cmd.url, "/api/network/start");
  assertEquals((cmd.body as Record<string, unknown>).runner, "host");
});

Deno.test("network/startRequested: omits runner from body when not provided", () => {
  const state = initState();
  const [, cmds] = step(state, {
    type: "network/startRequested",
    pds2: true,
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals((cmd.body as Record<string, unknown>).runner, undefined);
  assertEquals((cmd.body as Record<string, unknown>).pds2, true);
});

Deno.test("network/stopRequested: passes runner to POST body", () => {
  const state = initState();
  const [, cmds] = step(state, {
    type: "network/stopRequested",
    runner: "docker",
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals(cmd.url, "/api/network/stop");
  assertEquals((cmd.body as Record<string, unknown>).runner, "docker");
});

Deno.test("network/stopRequested: omits runner from body when not provided", () => {
  const state = initState();
  const [, cmds] = step(state, {
    type: "network/stopRequested",
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals((cmd.body as Record<string, unknown>).runner, undefined);
});

// ---------------------------------------------------------------------------
// ux/setRunner
// ---------------------------------------------------------------------------

Deno.test("ux/setRunner: updates runner field", () => {
  const state = initState();
  assertEquals(state.ux.runner, "host");
  const [next] = step(state, { type: "ux/setRunner", runner: "docker" });
  assertEquals(next.ux.runner, "docker");
  const [next2] = step(next, { type: "ux/setRunner", runner: "host" });
  assertEquals(next2.ux.runner, "host");
});

Deno.test("createInitialState: defaults runner to host", () => {
  const state = initState();
  assertEquals(state.ux.runner, "host");
});

// ---------------------------------------------------------------------------
// ux/setAgentMode
// ---------------------------------------------------------------------------

Deno.test("config/received: enables agent mode only for agent launch", () => {
  const state = initState();
  const [next] = step(state, { type: "config/received", agentLaunch: true });
  assertEquals(next.ux.agentLaunch, true);
  assertEquals(next.ux.agentMode, true);
});

Deno.test("config/received: does not enable agent mode for human launch", () => {
  const state = initState();
  const [next] = step(state, { type: "config/received", agentLaunch: false });
  assertEquals(next.ux.agentLaunch, false);
  assertEquals(next.ux.agentMode, false);
});

Deno.test("ux/setAgentMode: ignores enable when not agent launch", () => {
  const state = initState();
  const [next] = step(state, { type: "ux/setAgentMode", agentMode: true });
  assertEquals(next.ux.agentMode, false);
});

Deno.test("ux/setAgentMode: updates agentMode field when agent launch", () => {
  const state = initState({
    ux: { ...initState().ux, agentLaunch: true, agentMode: true },
  });
  const [next] = step(state, { type: "ux/setAgentMode", agentMode: false });
  assertEquals(next.ux.agentMode, false);
  const [next2] = step(next, { type: "ux/setAgentMode", agentMode: true });
  assertEquals(next2.ux.agentMode, true);
});

Deno.test("createInitialState: defaults agentMode to false", () => {
  const state = initState();
  assertEquals(state.ux.agentMode, false);
});

Deno.test("runs/startRequested: handler reads agentMode from state.ux.agentMode, not Msg", () => {
  // The runs/startRequested Msg no longer has an agentMode field.
  // The handler reads it from state.ux.agentMode.
  // Toolbar dispatches ux/setAgentMode separately to toggle it.
  const state = initState({ ux: { ...initState().ux, agentMode: true } });
  const [, cmds] = step(state, {
    type: "runs/startRequested",
    scenarioIds: ["01"],
    pds2: false,
  });
  const cmd = fetchCmds(cmds)[0];
  assert(cmd);
  assertEquals((cmd.body as Record<string, unknown>).agentMode, true);
});
