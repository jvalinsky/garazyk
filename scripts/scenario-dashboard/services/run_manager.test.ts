import { assertEquals, assertExists } from "$std/assert/mod.ts";
import { TextLineStream } from "@std/streams";
import { mapAgentEventLine, runManager } from "./run_manager.ts";
import { db } from "../db/index.ts";
import type { RunEvent } from "./types.ts";

Deno.test({
  name: "RunManager - basic lifecycle",
  async fn() {
    // Start a dummy run
    const result = await runManager.startRun({
      topology: "garazyk-default",
      runner: "host",
      scenarioIds: ["01"],
      pds2: false,
      binaryMode: false,
    });

    if ("conflict" in result) {
      throw new Error(`Conflict: ${result.conflict}`);
    }

    const runId = result.runId;
    assertExists(runId);

    const active = runManager.getActiveRun();
    assertExists(active);
    assertEquals(active.id, runId);
    assertEquals(active.status, "running");

    // Check DB entry
    const row = db.prepare("SELECT * FROM runs WHERE id = ?").get(runId) as any;
    assertExists(row);
    assertEquals(row.status, "running");

    // Stop the run
    await runManager.stopRun(runId, false);

    const activeAfterStop = runManager.getActiveRun();
    assertEquals(activeAfterStop, undefined);

    const rowAfterStop = db.prepare("SELECT * FROM runs WHERE id = ?").get(runId) as any;
    assertEquals(rowAfterStop.status, "error");
    assertEquals(rowAfterStop.stop_reason, "manual_stop");
  },
  // Ensure we don't leak resources
  sanitizeResources: false,
  sanitizeOps: false,
});

Deno.test({
  name: "RunManager - concurrent run prevention",
  async fn() {
    const r1 = await runManager.startRun({
      topology: "garazyk-default",
      runner: "host",
      scenarioIds: ["01"],
      pds2: false,
      binaryMode: false,
    });

    const r2 = await runManager.startRun({
      topology: "garazyk-default",
      runner: "host",
      scenarioIds: ["02"],
      pds2: false,
      binaryMode: false,
    });

    if (!("conflict" in r2)) {
      throw new Error("Should have failed with conflict");
    }

    assertExists(r2.conflict);

    // Cleanup
    if (!("conflict" in r1)) {
      await runManager.stopRun(r1.runId, false);
    }
  },
  sanitizeResources: false,
  sanitizeOps: false,
});

// ── mapAgentEventLine: NDJSON → RunEvent integration tests ────────────

function makeNdjsonRunStart(overrides?: Record<string, unknown>): string {
  return JSON.stringify({
    type: "run_start",
    runId: "test-001",
    scenarioIds: ["01", "02"],
    total: 2,
    timestamp: 1700000000000,
    ...overrides,
  });
}

function makeNdjsonScenarioStart(overrides?: Record<string, unknown>): string {
  return JSON.stringify({
    type: "scenario_start",
    scenarioId: "01",
    name: "account lifecycle",
    index: 0,
    total: 2,
    timestamp: 1700000001000,
    ...overrides,
  });
}

function makeNdjsonScenarioComplete(overrides?: Record<string, unknown>): string {
  return JSON.stringify({
    type: "scenario_complete",
    scenarioId: "01",
    name: "account lifecycle",
    ok: true,
    passed: 3,
    failed: 0,
    skipped: 0,
    durationS: 2.5,
    summaryText: "✅ 01 - account lifecycle",
    reportPath: "/tmp/01.json",
    timestamp: 1700000003500,
    ...overrides,
  });
}

function makeNdjsonServiceFailure(overrides?: Record<string, unknown>): string {
  return JSON.stringify({
    type: "service_failure",
    message: "PDS health check failed",
    source: "health_check",
    timestamp: 1700000004000,
    ...overrides,
  });
}

function makeNdjsonRunProgress(overrides?: Record<string, unknown>): string {
  return JSON.stringify({
    type: "run_progress",
    completed: 1,
    total: 2,
    currentScenarioId: "02",
    currentScenarioName: "OAuth login",
    running: true,
    timestamp: 1700000005000,
    ...overrides,
  });
}

function makeNdjsonRunFinished(overrides?: Record<string, unknown>): string {
  return JSON.stringify({
    type: "run_finished",
    runId: "test-001",
    ok: true,
    totalPassed: 6,
    totalFailed: 0,
    totalSkipped: 0,
    reportsDir: "/tmp/reports",
    crashedContainer: false,
    timestamp: 1700000010000,
    ...overrides,
  });
}

Deno.test("mapAgentEventLine: run_start → run_started", () => {
  const line = makeNdjsonRunStart();
  const event = mapAgentEventLine(line, "dashboard-run-1") as Extract<RunEvent, { type: "run_started" }>;

  assertExists(event);
  assertEquals(event.type, "run_started");
  assertEquals(event.runId, "test-001");
  assertEquals(event.totalScenarios, 2);
  assertEquals(event.startedAt, 1700000000000);
});

Deno.test("mapAgentEventLine: scenario_start → scenario_started", () => {
  const line = makeNdjsonScenarioStart();
  const event = mapAgentEventLine(line, "dashboard-run-1") as Extract<RunEvent, { type: "scenario_started" }>;

  assertExists(event);
  assertEquals(event.type, "scenario_started");
  assertEquals(event.runId, "dashboard-run-1");
  assertEquals(event.scenarioId, "01");
  assertEquals(event.scenarioName, "account lifecycle");
});

Deno.test("mapAgentEventLine: scenario_complete (passed) → scenario_finished", () => {
  const line = makeNdjsonScenarioComplete({ ok: true, passed: 3, failed: 0, skipped: 0, durationS: 2.5 });
  const event = mapAgentEventLine(line, "dashboard-run-1") as Extract<RunEvent, { type: "scenario_finished" }>;

  assertExists(event);
  assertEquals(event.type, "scenario_finished");
  assertEquals(event.scenarioId, "01");
  assertEquals(event.status, "passed");
  assertEquals(event.passed, 3);
  assertEquals(event.failed, 0);
  assertEquals(event.skipped, 0);
  assertEquals(event.durationMs, 2500);
});

Deno.test("mapAgentEventLine: scenario_complete (failed) → scenario_finished", () => {
  const line = makeNdjsonScenarioComplete({ ok: false, passed: 1, failed: 2, skipped: 1 });
  const event = mapAgentEventLine(line, "dashboard-run-1") as Extract<RunEvent, { type: "scenario_finished" }>;

  assertExists(event);
  assertEquals(event.type, "scenario_finished");
  assertEquals(event.status, "failed");
  assertEquals(event.passed, 1);
  assertEquals(event.failed, 2);
  assertEquals(event.skipped, 1);
});

Deno.test("mapAgentEventLine: service_failure → log_line", () => {
  const line = makeNdjsonServiceFailure({ message: "Container pds crashed", source: "container_crash" });
  const event = mapAgentEventLine(line, "dashboard-run-1") as Extract<RunEvent, { type: "log_line" }>;

  assertExists(event);
  assertEquals(event.type, "log_line");
  assertEquals(event.runId, "dashboard-run-1");
  assertEquals(event.line, "[service_failure] Container pds crashed");
});

Deno.test("mapAgentEventLine: run_progress → null (suppressed)", () => {
  const line = makeNdjsonRunProgress({ completed: 1, running: true });
  const event = mapAgentEventLine(line, "dashboard-run-1");

  assertEquals(event, null);
});

Deno.test("mapAgentEventLine: run_finished (ok) → run_completed", () => {
  const line = makeNdjsonRunFinished({ ok: true, totalPassed: 6, totalFailed: 0, totalSkipped: 0 });
  const event = mapAgentEventLine(line, "dashboard-run-1") as Extract<RunEvent, { type: "run_completed" }>;

  assertExists(event);
  assertEquals(event.type, "run_completed");
  assertEquals(event.exitCode, 0);
  assertEquals(event.passed, 6);
  assertEquals(event.failed, 0);
  assertEquals(event.skipped, 0);
});

Deno.test("mapAgentEventLine: run_finished (not ok) → run_failed", () => {
  const line = makeNdjsonRunFinished({ ok: false, totalPassed: 3, totalFailed: 3 });
  const event = mapAgentEventLine(line, "dashboard-run-1") as Extract<RunEvent, { type: "run_failed" }>;

  assertExists(event);
  assertEquals(event.type, "run_failed");
  assertEquals(event.exitCode, 1);
  assertEquals(event.reason, "agent_run_failed");
});

Deno.test("mapAgentEventLine: non-JSON line → log_line", () => {
  const line = "[agent] Starting scenario 01...";
  const event = mapAgentEventLine(line, "dashboard-run-1") as Extract<RunEvent, { type: "log_line" }>;

  assertExists(event);
  assertEquals(event.type, "log_line");
  assertEquals(event.runId, "dashboard-run-1");
  assertEquals(event.line, "[agent] Starting scenario 01...");
});

Deno.test("mapAgentEventLine: unknown event type → log_line", () => {
  const line = JSON.stringify({ type: "custom_metric", value: 42 });
  const event = mapAgentEventLine(line, "dashboard-run-1") as Extract<RunEvent, { type: "log_line" }>;

  assertExists(event);
  assertEquals(event.type, "log_line");
  assertEquals(event.line, `[agent:custom_metric] ${line}`);
});

Deno.test("mapAgentEventLine: empty line → null", () => {
  const event = mapAgentEventLine("", "dashboard-run-1");
  assertEquals(event, null);
});

Deno.test("mapAgentEventLine: scenario_complete missing ok field defaults to failed", () => {
  const line = JSON.stringify({ type: "scenario_complete", scenarioId: "05", name: "bad", passed: 0, failed: 1, skipped: 0, durationS: 1 });
  const event = mapAgentEventLine(line, "dr-1") as Extract<RunEvent, { type: "scenario_finished" }>;

  assertExists(event);
  assertEquals(event.status, "failed");
});

Deno.test("mapAgentEventLine: JSON without type field falls to default", () => {
  const line = JSON.stringify({ foo: "bar" });
  const event = mapAgentEventLine(line, "dr-1") as Extract<RunEvent, { type: "log_line" }>;

  assertExists(event);
  assertEquals(event.type, "log_line");
  assertEquals(event.line, `[agent:undefined] ${line}`);
});

Deno.test("mapAgentEventLine: full lifecycle sequence", () => {
  const events: (RunEvent | null)[] = [];
  const runId = "dashboard-run-full";

  events.push(mapAgentEventLine(makeNdjsonRunStart({ runId: "agent-001", scenarioIds: ["01", "02"], total: 2 }), runId));
  events.push(mapAgentEventLine(makeNdjsonScenarioStart({ scenarioId: "01" }), runId));
  events.push(mapAgentEventLine(makeNdjsonScenarioComplete({ scenarioId: "01", ok: true, passed: 2 }), runId));
  events.push(mapAgentEventLine(makeNdjsonRunProgress({ completed: 1 }), runId));
  events.push(mapAgentEventLine(makeNdjsonScenarioStart({ scenarioId: "02", name: "failing scenario" }), runId));
  events.push(mapAgentEventLine(makeNdjsonScenarioComplete({ scenarioId: "02", name: "failing scenario", ok: false, passed: 1, failed: 1 }), runId));
  events.push(mapAgentEventLine(makeNdjsonRunFinished({ ok: false, totalPassed: 3, totalFailed: 1 }), runId));

  const nonNull = events.filter((e): e is RunEvent => e !== null);
  assertEquals(nonNull.length, 6); // 7 lines minus 1 suppressed run_progress

  assertEquals(nonNull[0].type, "run_started");
  assertEquals(nonNull[1].type, "scenario_started");
  assertEquals(nonNull[2].type, "scenario_finished");
  assertEquals((nonNull[2] as Extract<RunEvent, { type: "scenario_finished" }>).status, "passed");
  assertEquals(nonNull[3].type, "scenario_started");
  assertEquals(nonNull[4].type, "scenario_finished");
  assertEquals((nonNull[4] as Extract<RunEvent, { type: "scenario_finished" }>).status, "failed");
  assertEquals(nonNull[5].type, "run_failed");
});

// ── Stream-based e2e: simulate parseAgentNdjson pipeline ──────────────

Deno.test("mapAgentEventLine: run_start malformed fields fall back safely", () => {
  // total is a string, timestamp is a string — both should default
  const line = makeNdjsonRunStart({ total: "not-a-number", timestamp: "bad" });
  const event = mapAgentEventLine(line, "dr-1") as Extract<RunEvent, { type: "run_started" }>;

  assertExists(event);
  assertEquals(event.type, "run_started");
  assertEquals(event.totalScenarios, 0);
  // timestamp defaults to Date.now() — just verify it's a reasonable number
  assertEquals(typeof event.startedAt, "number");
  assertExists(event.startedAt > 0);
});

Deno.test("mapAgentEventLine: scenario_start malformed fields fall back safely", () => {
  // scenarioId is null, name is a number — both should default
  const line = makeNdjsonScenarioStart({ scenarioId: null, name: 123 });
  const event = mapAgentEventLine(line, "dr-1") as Extract<RunEvent, { type: "scenario_started" }>;

  assertExists(event);
  assertEquals(event.type, "scenario_started");
  assertEquals(event.scenarioId, "??");
  assertEquals(event.scenarioName, "unknown");
});

Deno.test("mapAgentEventLine: scenario_complete malformed fields fall back safely", () => {
  // passed/failed/skipped/durationS are all strings — should default to 0
  const line = makeNdjsonScenarioComplete({
    ok: true,
    passed: "three",
    failed: null,
    skipped: true,
    durationS: "two-seconds",
  });
  const event = mapAgentEventLine(line, "dr-1") as Extract<RunEvent, { type: "scenario_finished" }>;

  assertExists(event);
  assertEquals(event.type, "scenario_finished");
  assertEquals(event.status, "passed");
  assertEquals(event.passed, 0);
  assertEquals(event.failed, 0);
  assertEquals(event.skipped, 0);
  assertEquals(event.durationMs, 0);
});

Deno.test("mapAgentEventLine: service_failure missing message defaults", () => {
  const line = makeNdjsonServiceFailure({ message: undefined });
  const event = mapAgentEventLine(line, "dr-1") as Extract<RunEvent, { type: "log_line" }>;

  assertExists(event);
  assertEquals(event.type, "log_line");
  assertEquals(event.line, "[service_failure] unknown failure");
});

Deno.test("mapAgentEventLine: run_finished malformed totals fall back safely", () => {
  // totalPassed/totalFailed/totalSkipped/timestamp are all strings
  const line = makeNdjsonRunFinished({
    ok: true,
    totalPassed: "six",
    totalFailed: null,
    totalSkipped: false,
    timestamp: "not-a-ts",
  });
  const event = mapAgentEventLine(line, "dr-1") as Extract<RunEvent, { type: "run_completed" }>;

  assertExists(event);
  assertEquals(event.type, "run_completed");
  assertEquals(event.passed, 0);
  assertEquals(event.failed, 0);
  assertEquals(event.skipped, 0);
  assertEquals(typeof event.finishedAt, "number");
  assertExists(event.finishedAt > 0);
});

Deno.test("mapAgentEventLine: run_start missing runId falls back to arg", () => {
  const line = makeNdjsonRunStart({ runId: undefined });
  const event = mapAgentEventLine(line, "fallback-run-id") as Extract<RunEvent, { type: "run_started" }>;

  assertExists(event);
  assertEquals(event.type, "run_started");
  assertEquals(event.runId, "fallback-run-id");
});

Deno.test("mapAgentEventLine: agent NDJSON stream → mapAgentEventLine: full pipeline e2e", async () => {
  const runId = "e2e-stream-run";
  const captured: RunEvent[] = [];

  // Build NDJSON lines identical to what the agent runner emits on stdout
  const lines = [
    makeNdjsonRunStart({ runId: "agent-001", scenarioIds: ["01", "02"], total: 2 }),
    "", // empty line — should be skipped
    makeNdjsonScenarioStart({ scenarioId: "01", name: "account lifecycle" }),
    makeNdjsonScenarioComplete({ scenarioId: "01", ok: true, passed: 2, failed: 0, skipped: 0, durationS: 0.5 }),
    makeNdjsonRunProgress({ completed: 1, running: true }), // suppressed
    makeNdjsonScenarioStart({ scenarioId: "02", name: "OAuth login" }),
    "[agent] some unstructured stderr-like line", // non-JSON → log_line
    makeNdjsonScenarioComplete({ scenarioId: "02", ok: false, passed: 1, failed: 1, skipped: 0, durationS: 1.2 }),
    makeNdjsonRunFinished({ ok: true, totalPassed: 3, totalFailed: 1, totalSkipped: 0 }),
  ];

  // Replicate parseAgentNdjson's pipeline:
  //   stdout → TextDecoderStream → TextLineStream → mapAgentEventLine → emit
  const encoder = new TextEncoder();
  const stdoutStream = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const line of lines) {
        controller.enqueue(encoder.encode(line + "\n"));
      }
      controller.close();
    },
  });

  const lineReader: ReadableStream<string> = stdoutStream
    .pipeThrough(new TextDecoderStream() as ReadableWritablePair<string, Uint8Array>)
    .pipeThrough(new TextLineStream());

  for await (const line of lineReader) {
    if (line.length === 0) continue;
    const event = mapAgentEventLine(line, runId);
    if (event) captured.push(event);
  }

  // 9 lines: 1 run_start + 1 empty + 1 scenario_start + 1 scenario_complete +
  //          1 progress (suppressed) + 1 scenario_start + 1 non-JSON +
  //          1 scenario_complete + 1 run_finished
  // = 7 non-null events (empty + progress suppressed)
  assertEquals(captured.length, 7);

  assertEquals(captured[0].type, "run_started");
  assertEquals((captured[0] as Extract<RunEvent, { type: "run_started" }>).totalScenarios, 2);

  assertEquals(captured[1].type, "scenario_started");
  assertEquals((captured[1] as Extract<RunEvent, { type: "scenario_started" }>).scenarioId, "01");

  assertEquals(captured[2].type, "scenario_finished");
  assertEquals((captured[2] as Extract<RunEvent, { type: "scenario_finished" }>).status, "passed");
  assertEquals((captured[2] as Extract<RunEvent, { type: "scenario_finished" }>).durationMs, 500);

  assertEquals(captured[3].type, "scenario_started");
  assertEquals((captured[3] as Extract<RunEvent, { type: "scenario_started" }>).scenarioId, "02");

  assertEquals(captured[4].type, "log_line");
  assertEquals((captured[4] as Extract<RunEvent, { type: "log_line" }>).line, "[agent] some unstructured stderr-like line");

  assertEquals(captured[5].type, "scenario_finished");
  assertEquals((captured[5] as Extract<RunEvent, { type: "scenario_finished" }>).status, "failed");

  assertEquals(captured[6].type, "run_completed");
  assertEquals((captured[6] as Extract<RunEvent, { type: "run_completed" }>).passed, 3);
  assertEquals((captured[6] as Extract<RunEvent, { type: "run_completed" }>).failed, 1);
});
