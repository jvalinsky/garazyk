/**
 * Unit tests for the pure TEA run loop state machine.
 *
 * @module run_loop_state_test
 */

import { assertEquals } from "@std/assert";
import {
  createInitialRunLoopState,
  recordScenarioResult,
  setAbortedForCrash,
  setCrashedContainer,
  totalFailed,
  totalPassed,
  totalSkipped,
} from "./run_loop_state.ts";
import type { CrashedContainer } from "./run_loop_state.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import { ScenarioResult } from "./runner.ts";

function makeScenario(id: string, name: string): ScenarioInfo {
  return {
    id,
    name,
    path: `/scenarios/${id}.ts`,
    requires: [],
    optional: [],
    needsPds2: false,
    needsPds3: false,
    browserFlows: [],
    parameters: {},
  };
}

function makeResult(name: string, passed: number, failed: number, skipped: number): ScenarioResult {
  const r = new ScenarioResult(name);
  r.start();
  for (let i = 0; i < passed; i++) r.stepPassed(`step-${i}`);
  for (let i = 0; i < failed; i++) r.stepFailed(`fail-${i}`, "error");
  for (let i = 0; i < skipped; i++) r.stepSkipped(`skip-${i}`);
  r.finish();
  return r;
}

// ── createInitialRunLoopState ─────────────────────────────────────────

Deno.test("createInitialRunLoopState: all accumulators are empty", () => {
  const state = createInitialRunLoopState();
  assertEquals(state.results, []);
  assertEquals(state.reportPaths, []);
  assertEquals(state.crashedContainer, null);
  assertEquals(state.abortedForCrash, false);
});

// ── recordScenarioResult ───────────────────────────────────────────────

Deno.test("recordScenarioResult: appends result and report path", () => {
  const state = createInitialRunLoopState();
  const scenario = makeScenario("01", "login");
  const result = makeResult("login", 3, 0, 0);

  const next = recordScenarioResult(state, scenario, result, "/tmp/01_login.json");

  assertEquals(next.results.length, 1);
  assertEquals(next.results[0].scenario.id, "01");
  assertEquals(next.results[0].result.passed, 3);
  assertEquals(next.reportPaths, ["/tmp/01_login.json"]);
  // Original is unchanged
  assertEquals(state.results.length, 0);
});

Deno.test("recordScenarioResult: multiple results accumulate in order", () => {
  let state = createInitialRunLoopState();
  const s1 = makeScenario("01", "first");
  const s2 = makeScenario("02", "second");
  const r1 = makeResult("first", 1, 0, 0);
  const r2 = makeResult("second", 0, 1, 0);

  state = recordScenarioResult(state, s1, r1, "/tmp/01.json");
  state = recordScenarioResult(state, s2, r2, "/tmp/02.json");

  assertEquals(state.results.length, 2);
  assertEquals(state.results[0].scenario.id, "01");
  assertEquals(state.results[1].scenario.id, "02");
  assertEquals(state.reportPaths, ["/tmp/01.json", "/tmp/02.json"]);
});

Deno.test("recordScenarioResult: no report path is fine", () => {
  const state = createInitialRunLoopState();
  const scenario = makeScenario("01", "no-report");
  const result = makeResult("no-report", 1, 0, 0);

  const next = recordScenarioResult(state, scenario, result);

  assertEquals(next.results.length, 1);
  assertEquals(next.reportPaths, []);
});

// ── setCrashedContainer ────────────────────────────────────────────────

Deno.test("setCrashedContainer: records first crash only", () => {
  const state = createInitialRunLoopState();
  const crash1: CrashedContainer = {
    serviceName: "plc",
    exitCode: 137,
    oomKilled: true,
  };
  const crash2: CrashedContainer = {
    serviceName: "pds",
    exitCode: 1,
    oomKilled: false,
  };

  let next = setCrashedContainer(state, crash1);
  assertEquals(next.crashedContainer?.serviceName, "plc");
  assertEquals(next.crashedContainer?.oomKilled, true);

  // Second crash should be ignored
  next = setCrashedContainer(next, crash2);
  assertEquals(next.crashedContainer?.serviceName, "plc"); // still the first
});

// ── setAbortedForCrash ─────────────────────────────────────────────────

Deno.test("setAbortedForCrash: marks aborted", () => {
  const state = createInitialRunLoopState();
  assertEquals(state.abortedForCrash, false);

  const next = setAbortedForCrash(state);
  assertEquals(next.abortedForCrash, true);
  assertEquals(state.abortedForCrash, false); // immutable
});

// ── Derived queries ────────────────────────────────────────────────────

Deno.test("totalPassed: sums across scenarios", () => {
  let state = createInitialRunLoopState();
  state = recordScenarioResult(state, makeScenario("01", "a"), makeResult("a", 3, 1, 0));
  state = recordScenarioResult(state, makeScenario("02", "b"), makeResult("b", 2, 0, 1));

  assertEquals(totalPassed(state), 5);
});

Deno.test("totalFailed: sums across scenarios", () => {
  let state = createInitialRunLoopState();
  state = recordScenarioResult(state, makeScenario("01", "a"), makeResult("a", 3, 1, 0));
  state = recordScenarioResult(state, makeScenario("02", "b"), makeResult("b", 0, 2, 0));

  assertEquals(totalFailed(state), 3);
});

Deno.test("totalSkipped: sums across scenarios", () => {
  let state = createInitialRunLoopState();
  state = recordScenarioResult(state, makeScenario("01", "a"), makeResult("a", 1, 0, 2));
  state = recordScenarioResult(state, makeScenario("02", "b"), makeResult("b", 0, 0, 3));

  assertEquals(totalSkipped(state), 5);
});

Deno.test("derived queries: empty state returns zeros", () => {
  const state = createInitialRunLoopState();
  assertEquals(totalPassed(state), 0);
  assertEquals(totalFailed(state), 0);
  assertEquals(totalSkipped(state), 0);
});

// ── Immutability ───────────────────────────────────────────────────────

Deno.test("state is immutable across reducer calls", () => {
  const state = createInitialRunLoopState();
  const next = recordScenarioResult(
    state,
    makeScenario("01", "immutable"),
    makeResult("immutable", 1, 0, 0),
  );

  assertEquals(state.results.length, 0);
  assertEquals(next.results.length, 1);
});
