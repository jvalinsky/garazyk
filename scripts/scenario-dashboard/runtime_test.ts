import { assertEquals, assertThrows } from "jsr:@std/assert";
import { constructErrorMsg, constructMsg } from "./runtime.ts";
import type { Run, ScenarioResultView, ServiceStatus } from "./services/types.ts";

// ---------------------------------------------------------------------------
// constructMsg — API response to Msg mapping
// ---------------------------------------------------------------------------

Deno.test("constructMsg: network/healthReceived maps services array", () => {
  const services: ServiceStatus[] = [{
    name: "pds",
    label: "PDS",
    url: "http://localhost:2583",
    port: 2583,
    status: "running",
    healthy: true,
  }];
  const data = { services };
  const msg = constructMsg("network/healthReceived", data);
  assertEquals(msg, { type: "network/healthReceived", services });
});

Deno.test("constructMsg: runs/activeReceived maps activeRun to run", () => {
  const run: Run = {
    id: "r-1",
    status: "running",
    startedAt: 1000,
    totalScenarios: 5,
    passed: 0,
    failed: 0,
    skipped: 0,
  };
  const data = { activeRun: run };
  const msg = constructMsg("runs/activeReceived", data);
  assertEquals(msg, { type: "runs/activeReceived", run });
});

Deno.test("constructMsg: runs/activeReceived defaults to null when activeRun is absent", () => {
  const msg = constructMsg("runs/activeReceived", {});
  assertEquals(msg, { type: "runs/activeReceived", run: null });
});

Deno.test("constructMsg: runs/activeReceived defaults to null when activeRun is null", () => {
  const data = { activeRun: null };
  const msg = constructMsg("runs/activeReceived", data);
  assertEquals(msg, { type: "runs/activeReceived", run: null });
});

Deno.test("constructMsg: runs/startSucceeded maps runId", () => {
  const msg = constructMsg("runs/startSucceeded", { runId: "run-42" });
  assertEquals(msg, { type: "runs/startSucceeded", runId: "run-42" });
});

Deno.test("constructMsg: runs/startSucceeded coerces runId to string", () => {
  const msg = constructMsg("runs/startSucceeded", { runId: 42 });
  assertEquals(msg, { type: "runs/startSucceeded", runId: "42" });
});

Deno.test("constructMsg: runs/progressReceived passes data through as progress", () => {
  const progress = {
    exists: true,
    runId: "r-1",
    total: 10,
    completed: 3,
    currentScenario: "test",
    currentScenarioId: "01",
    elapsedMs: 5000,
    updatedAt: 1000,
    now: 6000,
    running: true,
  };
  const msg = constructMsg("runs/progressReceived", progress);
  assertEquals(msg, { type: "runs/progressReceived", progress });
});

Deno.test("constructMsg: scenarios/received maps scenarios array", () => {
  const scenarios = [{ id: "01", name: "test", description: "A test scenario", category: "core", needsPds2: false }];
  const data = { scenarios };
  const msg = constructMsg("scenarios/received", data);
  assertEquals(msg, { type: "scenarios/received", scenarios });
});

Deno.test("constructMsg: topology/listReceived maps topologies array", () => {
  const topologies = [{ name: "default" }, { name: "minimal" }];
  const data = { topologies };
  const msg = constructMsg("topology/listReceived", data);
  assertEquals(msg, { type: "topology/listReceived", topologies });
});

Deno.test("constructMsg: topology/previewReceived passes data through as preview", () => {
  const preview = { name: "default", description: "test", roles: ["pds"], capabilities: ["basic"] };
  const msg = constructMsg("topology/previewReceived", preview);
  assertEquals(msg, { type: "topology/previewReceived", preview });
});

Deno.test("constructMsg: network/startSucceeded produces no-payload msg", () => {
  const msg = constructMsg("network/startSucceeded", {});
  assertEquals(msg, { type: "network/startSucceeded" });
});

Deno.test("constructMsg: network/stopSucceeded produces no-payload msg", () => {
  const msg = constructMsg("network/stopSucceeded", {});
  assertEquals(msg, { type: "network/stopSucceeded" });
});

Deno.test("constructMsg: runs/stopSucceeded produces no-payload msg", () => {
  const msg = constructMsg("runs/stopSucceeded", {});
  assertEquals(msg, { type: "runs/stopSucceeded" });
});

Deno.test("constructMsg: runs/restartSucceeded maps newRunId", () => {
  const msg = constructMsg("runs/restartSucceeded", { newRunId: "run-43" });
  assertEquals(msg, { type: "runs/restartSucceeded", newRunId: "run-43" });
});

Deno.test("constructMsg: runs/restartSucceeded coerces newRunId to string", () => {
  const msg = constructMsg("runs/restartSucceeded", { newRunId: 43 });
  assertEquals(msg, { type: "runs/restartSucceeded", newRunId: "43" });
});

Deno.test("constructMsg: throws on unknown msg type", () => {
  assertThrows(
    () => constructMsg("nonexistent", {}),
    Error,
    "Unknown success msg type: nonexistent",
  );
});

// ---------------------------------------------------------------------------
// constructErrorMsg — error string to Msg mapping
// ---------------------------------------------------------------------------

const ERROR_MSG_TYPES = [
  "network/healthFailed",
  "runs/activeFailed",
  "runs/progressFailed",
  "runs/startFailed",
  "runs/stopFailed",
  "runs/restartFailed",
  "scenarios/failed",
  "topology/listFailed",
  "topology/previewFailed",
  "network/startFailed",
  "network/stopFailed",
] as const;

for (const type of ERROR_MSG_TYPES) {
  Deno.test(`constructErrorMsg: ${type} wraps error string`, () => {
    const msg = constructErrorMsg(type, "something went wrong");
    assertEquals(msg, { type, error: "something went wrong" });
  });
}

Deno.test("constructErrorMsg: preserves non-empty error strings", () => {
  const msg = constructErrorMsg("network/healthFailed", "ECONNREFUSED: connection refused");
  assertEquals(msg, { type: "network/healthFailed", error: "ECONNREFUSED: connection refused" });
});

Deno.test("constructErrorMsg: throws on unknown error type", () => {
  assertThrows(
    () => constructErrorMsg("nonexistent", "err"),
    Error,
    "Unknown error msg type: nonexistent",
  );
});

// ---------------------------------------------------------------------------
// Edge cases
// ---------------------------------------------------------------------------

Deno.test("constructMsg: malformed health response becomes typed failure", () => {
  const msg = constructMsg("network/healthReceived", {});
  assertEquals(msg, { type: "network/healthFailed", error: "Malformed health response" });
});

Deno.test("constructMsg: malformed progress response becomes typed failure", () => {
  const msg = constructMsg("runs/progressReceived", "just a string");
  assertEquals(msg, { type: "runs/progressFailed", error: "Malformed progress response" });
});

Deno.test("constructMsg: services as non-array becomes typed failure", () => {
  const msg = constructMsg("network/healthReceived", { services: "not-an-array" });
  assertEquals(msg, { type: "network/healthFailed", error: "Malformed health response" });
});

// ---------------------------------------------------------------------------
// Run detail overlay — regression tests for constructMsg/constructErrorMsg
// These prevent the "Unknown success msg type: runs/detailResults" crash
// ---------------------------------------------------------------------------

Deno.test("constructMsg: runs/detailResults maps results array", () => {
  const results: ScenarioResultView[] = [
    {
      scenarioId: "01",
      scenarioName: "account_lifecycle",
      status: "failed",
      passed: 0,
      failed: 1,
      skipped: 0,
      durationMs: 500,
      steps: [{ name: "create account", status: "failed", detail: "timeout", duration_ms: 500 }],
      artifacts: null,
    },
  ];
  const msg = constructMsg("runs/detailResults", { results });
  assertEquals(msg, { type: "runs/detailResults", results });
});

Deno.test("constructMsg: runs/detailResults with empty results array", () => {
  const msg = constructMsg("runs/detailResults", { results: [] });
  assertEquals(msg, { type: "runs/detailResults", results: [] });
});

Deno.test("constructMsg: runs/detailResults malformed data closes overlay", () => {
  // Missing results array → closeDetail (graceful fallback)
  const msg = constructMsg("runs/detailResults", {});
  assertEquals(msg, { type: "runs/closeDetail" });
});

Deno.test("constructMsg: runs/detailResults non-array results closes overlay", () => {
  const msg = constructMsg("runs/detailResults", { results: "not-an-array" });
  assertEquals(msg, { type: "runs/closeDetail" });
});

Deno.test("constructErrorMsg: runs/closeDetail produces closeDetail msg", () => {
  const msg = constructErrorMsg("runs/closeDetail", "fetch failed");
  assertEquals(msg, { type: "runs/closeDetail" });
});
