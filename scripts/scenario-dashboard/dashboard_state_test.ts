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
import type { Run, ServiceStatus } from "./services/types.ts";

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
      scenarioParams: {},
      collapsedCategories: new Set(),
      searchTerm: "",
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
      scenarioParams: {},
      collapsedCategories: new Set(),
      searchTerm: "",
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
      scenarioParams: {},
      collapsedCategories: new Set(),
      searchTerm: "",
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
  assertEquals(cmds.length, 5);
  const urls = fetchCmds(cmds).map((c) => c.url);
  assertEquals(urls.includes("/api/network/health"), true);
  assertEquals(urls.includes("/api/runs/active"), true);
  assertEquals(urls.includes("/api/scenarios"), true);
  assertEquals(urls.includes("/api/topologies"), true);
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
