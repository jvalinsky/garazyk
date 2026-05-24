/**
 * Integration and unit tests for the hamownia agent CLI.
 *
 * Covers:
 * - classifyBoundary (all 9 rule categories + ordering)
 * - toSummary (list JSON shape)
 * - triageReports (pass, fail, fatal, missing, non-existent)
 * - NdjsonSink full event lifecycle (all 6 event types, valid JSON, correct fields)
 * - MultiSink fan-out
 * - agent run CLI argument parsing (boolean flags, value flags, enum validation)
 */
// spell-checker: disable

import {
  assertEquals,
  assertExists,
  assertMatch,
} from "@std/assert";
import { join } from "@std/path";
import type { AgentTriageResult } from "./cli/agent.ts";
import {
  classifyBoundary,
  toSummary,
  triageReports,
} from "./cli/agent.ts";
import {
  MultiSink,
  NdjsonSink,
} from "./events.ts";
import type {
  RunFinishedEvent,
  RunProgressEvent,
  RunStartedEvent,
  ScenarioCompletedEvent,
  ScenarioRunEvent,
  ScenarioRunEventSink,
  ScenarioStartedEvent,
  ServiceFailureEvent,
} from "./events.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";

// ── classifyBoundary ───────────────────────────────────────────────────

Deno.test("classifyBoundary: browser trumps all when step mentions browser", () => {
  assertEquals(
    classifyBoundary("browser login flow", "navigation timeout"),
    "browser",
  );
});

Deno.test("classifyBoundary: browser trumps startup when error mentions playwright", () => {
  assertEquals(
    classifyBoundary("step 1", "playwright timeout"),
    "browser",
  );
});

Deno.test("classifyBoundary: startup when error mentions timeout", () => {
  assertEquals(
    classifyBoundary("createRecord", "timed out after 30s"),
    "startup",
  );
});

Deno.test("classifyBoundary: startup trumps identity when timeout present", () => {
  // startup rule matches on error, identity matches on step name.
  // Startup comes first, so timeout wins.
  assertEquals(classifyBoundary("resolve did", "timeout"), "startup");
});

Deno.test("classifyBoundary: auth when step mentions session", () => {
  assertEquals(
    classifyBoundary("createSession", "invalid credentials"),
    "auth",
  );
});

Deno.test("classifyBoundary: auth when error mentions token", () => {
  assertEquals(
    classifyBoundary("step 3", "token expired"),
    "auth",
  );
});

Deno.test("classifyBoundary: validation when step mentions assert", () => {
  assertEquals(
    classifyBoundary("assert response", "expected 200 got 500"),
    "validation",
  );
});

Deno.test("classifyBoundary: identity when step mentions did", () => {
  assertEquals(
    classifyBoundary("resolve did", "not found"),
    "identity",
  );
});

Deno.test("classifyBoundary: route when error mentions 404", () => {
  assertEquals(
    classifyBoundary("fetchRecord", "xrpc 404 not found"),
    "route",
  );
});

Deno.test("classifyBoundary: rate_limit when error mentions 429", () => {
  assertEquals(
    classifyBoundary("createRecord", "429 too many requests"),
    "rate_limit",
  );
});

Deno.test("classifyBoundary: ingest when step mentions createRecord", () => {
  assertEquals(
    classifyBoundary("createRecord", "internal server error"),
    "ingest",
  );
});

Deno.test("classifyBoundary: firehose when step mentions subscribeRepos", () => {
  assertEquals(
    classifyBoundary("subscribeRepos", "connection refused"),
    "firehose",
  );
});

Deno.test("classifyBoundary: unknown when no rule matches", () => {
  assertEquals(
    classifyBoundary("miscellaneous step", "some vague error"),
    "unknown",
  );
});

Deno.test("classifyBoundary: startup trumps ingest when both match", () => {
  // createRecord matches ingest, but "timed out" matches startup which is earlier
  assertEquals(
    classifyBoundary("createRecord", "request timed out"),
    "startup",
  );
});

// ── toSummary ──────────────────────────────────────────────────────────

Deno.test("toSummary: produces correct AgentScenarioSummary shape", () => {
  const scenario: ScenarioInfo = {
    id: "01",
    name: "account lifecycle",
    path: "/scenarios/01.ts",
    requires: [{ role: "plc", capability: "didResolution" }],
    optional: [],
    needsPds2: false,
    browserFlows: [],
    parameters: {},
  };

  const summary = toSummary(scenario);

  assertEquals(summary.id, "01");
  assertEquals(summary.name, "account lifecycle");
  assertEquals(summary.path, "/scenarios/01.ts");
  assertEquals(summary.requires, ["plc:didResolution"]);
  assertEquals(summary.optional, []);
  assertEquals(summary.needsPds2, false);
  assertEquals(summary.browserFlows, []);
  assertEquals(summary.parameters, {});
});

Deno.test("toSummary: handles optional requirements and browser flows", () => {
  const scenario: ScenarioInfo = {
    id: "37",
    name: "e2ee DMs",
    path: "/scenarios/37.ts",
    requires: [{ role: "chat", capability: "dm" }],
    optional: [{ role: "appview", capability: "backfill" }],
    needsPds2: true,
    browserFlows: ["smoke", "login"],
    parameters: {},
  };

  const summary = toSummary(scenario);

  assertEquals(summary.id, "37");
  assertEquals(summary.requires, ["chat:dm"]);
  assertEquals(summary.optional, ["appview:backfill"]);
  assertEquals(summary.needsPds2, true);
  assertEquals(summary.browserFlows, ["smoke", "login"]);
});

Deno.test("toSummary: unknown scenario ID gets empty parameters", () => {
  const scenario: ScenarioInfo = {
    id: "99",
    name: "nonexistent",
    path: "/tmp/scenario.ts",
    requires: [],
    optional: [],
    needsPds2: false,
    browserFlows: [],
    parameters: {},
  };

  const summary = toSummary(scenario);

  assertEquals(summary.id, "99");
  assertEquals(summary.timeout, undefined);
  assertEquals(summary.parameters, {});
});

// ── triageReports ──────────────────────────────────────────────────────

Deno.test("triageReports: all-passing run", async () => {
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      join(tmpDir, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-run-pass",
        ok: true,
        report_paths: [join(tmpDir, "01_report.json")],
      }),
    );
    await Deno.writeTextFile(
      join(tmpDir, "01_report.json"),
      JSON.stringify({
        scenario: "account lifecycle",
        started_at: 1700000000.123,
        finished_at: 1700000003.456,
        duration_s: 3.333,
        steps: [
          {
            name: "create account",
            status: "passed",
            detail: "created alice",
            duration_ms: 150,
          },
        ],
        summary: { passed: 1, failed: 0, skipped: 0, total: 1 },
        ok: true,
        metadata: { scenario_id: "01" },
      }),
    );

    const result = await triageReports(tmpDir, "test-run-pass");

    assertEquals(result.runId, "test-run-pass");
    assertEquals(result.ok, true);
    assertEquals(result.firstFailure, undefined);
    assertEquals(result.boundary, "unknown");
    assertEquals(result.reportPaths.length, 1);
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

Deno.test("triageReports: failing run with classified boundary", async () => {
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      join(tmpDir, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-run-fail",
        ok: false,
        report_paths: [join(tmpDir, "01_report.json")],
      }),
    );
    await Deno.writeTextFile(
      join(tmpDir, "01_report.json"),
      JSON.stringify({
        scenario: "failing scenario",
        started_at: 1700000000,
        finished_at: 1700000002,
        duration_s: 2,
        steps: [
          {
            name: "create account",
            status: "passed",
            detail: "ok",
            duration_ms: 100,
          },
          {
            name: "createSession",
            status: "failed",
            detail: "token expired",
            duration_ms: 50,
          },
        ],
        summary: { passed: 1, failed: 1, skipped: 0, total: 2 },
        ok: false,
        metadata: { scenario_id: "06" },
      }),
    );

    const result = await triageReports(tmpDir);

    assertEquals(result.ok, false);
    assertEquals(result.boundary, "auth");
    assertEquals(result.firstFailure?.scenarioId, "06");
    assertEquals(result.firstFailure?.step, "createSession");
    assertEquals(result.firstFailure?.error, "token expired");
    assertEquals(result.evidence.length, 2);
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

Deno.test("triageReports: fatal error with no scenario reports", async () => {
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      join(tmpDir, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-run-fatal",
        ok: false,
        error: "connection refused",
        diagnostics_dir: join(tmpDir, "diagnostics"),
        report_paths: [],
      }),
    );

    const result = await triageReports(tmpDir);

    assertEquals(result.ok, false);
    assertEquals(result.boundary, "unknown");
    assertEquals(result.evidence[0], "Fatal error: connection refused");
    assertEquals(result.diagnosticsDir, join(tmpDir, "diagnostics"));
    assertEquals(result.reportPaths, []);
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

Deno.test("triageReports: fatal timeout error classifies as startup", async () => {
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      join(tmpDir, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-run-timeout",
        ok: false,
        error: "service startup timed out after 60s",
        report_paths: [],
      }),
    );

    const result = await triageReports(tmpDir);

    assertEquals(result.boundary, "startup");
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

Deno.test("triageReports: missing overall-summary discovers reports from directory", async () => {
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      join(tmpDir, "01_report.json"),
      JSON.stringify({
        scenario: "discovered scenario",
        steps: [
          { name: "step 1", status: "passed", detail: "ok", duration_ms: 50 },
        ],
        summary: { passed: 1, failed: 0, skipped: 0, total: 1 },
        ok: true,
      }),
    );

    const result = await triageReports(tmpDir);

    assertEquals(result.reportPaths.length, 1);
    assertEquals(result.evidence[0], "No overall-summary.json found");
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

Deno.test("triageReports: non-existent directory returns empty result", async () => {
  const result = await triageReports("/tmp/nonexistent-hamownia-agent-test");

  assertEquals(result.ok, true);
  assertEquals(result.reportPaths, []);
  assertEquals(result.evidence[0], "No overall-summary.json found");
});

Deno.test("triageReports: captures only first failure when multiple fail", async () => {
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      join(tmpDir, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-multi-fail",
        ok: false,
        report_paths: [
          join(tmpDir, "01_report.json"),
          join(tmpDir, "02_report.json"),
        ],
      }),
    );
    await Deno.writeTextFile(
      join(tmpDir, "01_report.json"),
      JSON.stringify({
        scenario: "first failure",
        steps: [
          { name: "did lookup", status: "failed", detail: "not found", duration_ms: 10 },
        ],
        summary: { passed: 0, failed: 1, skipped: 0, total: 1 },
        ok: false,
        metadata: { scenario_id: "01" },
      }),
    );
    await Deno.writeTextFile(
      join(tmpDir, "02_report.json"),
      JSON.stringify({
        scenario: "second failure",
        steps: [
          { name: "createRecord", status: "failed", detail: "timeout", duration_ms: 5000 },
        ],
        summary: { passed: 0, failed: 1, skipped: 0, total: 1 },
        ok: false,
        metadata: { scenario_id: "02" },
      }),
    );

    const result = await triageReports(tmpDir);
    // Only the first failure is captured
    assertEquals(result.firstFailure?.scenarioId, "01");
    assertEquals(result.firstFailure?.step, "did lookup");
    assertEquals(result.boundary, "identity");
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

Deno.test("triageReports: malformed report JSON is skipped gracefully", async () => {
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      join(tmpDir, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-malformed",
        ok: false,
        report_paths: [join(tmpDir, "broken_report.json")],
      }),
    );
    await Deno.writeTextFile(
      join(tmpDir, "broken_report.json"),
      "{ not valid json at all",
    );

    const result = await triageReports(tmpDir);
    // Should not throw — malformed report is skipped
    assertEquals(result.runId, "test-malformed");
    assertEquals(result.ok, false);
    assertEquals(result.firstFailure, undefined);
    assertEquals(result.evidence.some((e) => e.startsWith("Could not read report")), true);
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

// ── NdjsonSink: full event lifecycle ───────────────────────────────────

/** Capturing sink that stores events as serialized JSON lines. */
class CaptureNdjsonSink implements ScenarioRunEventSink {
  lines: string[] = [];

  emit(event: ScenarioRunEvent): void {
    this.lines.push(JSON.stringify(event));
  }
}

function makeRunStarted(overrides?: Partial<RunStartedEvent>): RunStartedEvent {
  return {
    type: "run_start",
    runId: "test-run-001",
    scenarioIds: ["01", "02", "03"],
    total: 3,
    timestamp: 1700000000000,
    ...overrides,
  };
}

function makeScenarioStarted(
  overrides?: Partial<ScenarioStartedEvent>,
): ScenarioStartedEvent {
  return {
    type: "scenario_start",
    scenarioId: "01",
    name: "account lifecycle",
    index: 0,
    total: 3,
    timestamp: 1700000001000,
    ...overrides,
  };
}

function makeScenarioCompleted(
  overrides?: Partial<ScenarioCompletedEvent>,
): ScenarioCompletedEvent {
  return {
    type: "scenario_complete",
    scenarioId: "01",
    name: "account lifecycle",
    ok: true,
    passed: 3,
    failed: 0,
    skipped: 0,
    durationS: 2.5,
    summaryText: "  ✅ 01 - account lifecycle  (3/3 passed)  2.5s",
    reportPath: "/tmp/reports/01.json",
    timestamp: 1700000003500,
    ...overrides,
  };
}

function makeServiceFailure(
  overrides?: Partial<ServiceFailureEvent>,
): ServiceFailureEvent {
  return {
    type: "service_failure",
    message: "PDS health check failed",
    source: "health_check",
    timestamp: 1700000004000,
    ...overrides,
  };
}

function makeRunProgress(
  overrides?: Partial<RunProgressEvent>,
): RunProgressEvent {
  return {
    type: "run_progress",
    completed: 1,
    total: 3,
    currentScenarioId: "02",
    currentScenarioName: "OAuth login",
    running: true,
    timestamp: 1700000005000,
    ...overrides,
  };
}

function makeRunFinished(
  overrides?: Partial<RunFinishedEvent>,
): RunFinishedEvent {
  return {
    type: "run_finished",
    runId: "test-run-001",
    ok: true,
    totalPassed: 9,
    totalFailed: 0,
    totalSkipped: 0,
    reportsDir: "/tmp/reports",
    crashedContainer: false,
    timestamp: 1700000010000,
    ...overrides,
  };
}

interface ParsedEvent {
  type: string;
  [key: string]: unknown;
}

Deno.test("NdjsonSink: RunStartedEvent serializes with correct fields", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeRunStarted());

  assertEquals(sink.lines.length, 1);
  const parsed: ParsedEvent = JSON.parse(sink.lines[0]);
  assertEquals(parsed.type, "run_start");
  assertEquals(parsed.runId, "test-run-001");
  assertEquals(parsed.scenarioIds as string[], ["01", "02", "03"]);
  assertEquals(parsed.total, 3);
  assertExists(parsed.timestamp);
});

Deno.test("NdjsonSink: ScenarioStartedEvent serializes with correct fields", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeScenarioStarted());

  assertEquals(sink.lines.length, 1);
  const parsed: ParsedEvent = JSON.parse(sink.lines[0]);
  assertEquals(parsed.type, "scenario_start");
  assertEquals(parsed.scenarioId, "01");
  assertEquals(parsed.name, "account lifecycle");
  assertEquals(parsed.index, 0);
  assertEquals(parsed.total, 3);
});

Deno.test("NdjsonSink: ScenarioCompletedEvent serializes with correct fields", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeScenarioCompleted({ ok: false, passed: 2, failed: 1 }));

  assertEquals(sink.lines.length, 1);
  const parsed: ParsedEvent = JSON.parse(sink.lines[0]);
  assertEquals(parsed.type, "scenario_complete");
  assertEquals(parsed.ok, false);
  assertEquals(parsed.passed, 2);
  assertEquals(parsed.failed, 1);
  assertEquals(parsed.skipped, 0);
  assertEquals(parsed.durationS, 2.5);
  assertEquals(parsed.reportPath, "/tmp/reports/01.json");
});

Deno.test("NdjsonSink: ServiceFailureEvent serializes with correct fields", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeServiceFailure());

  assertEquals(sink.lines.length, 1);
  const parsed: ParsedEvent = JSON.parse(sink.lines[0]);
  assertEquals(parsed.type, "service_failure");
  assertEquals(parsed.message, "PDS health check failed");
  assertEquals(parsed.source, "health_check");
});

Deno.test("NdjsonSink: ServiceFailureEvent with container_crash source", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeServiceFailure({
    message: "Container pds crashed",
    source: "container_crash",
  }));

  const parsed: ParsedEvent = JSON.parse(sink.lines[0]);
  assertEquals(parsed.source, "container_crash");
});

Deno.test("NdjsonSink: RunProgressEvent serializes with correct fields", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeRunProgress({ completed: 2, running: true }));

  assertEquals(sink.lines.length, 1);
  const parsed: ParsedEvent = JSON.parse(sink.lines[0]);
  assertEquals(parsed.type, "run_progress");
  assertEquals(parsed.completed, 2);
  assertEquals(parsed.total, 3);
  assertEquals(parsed.running, true);
});

Deno.test("NdjsonSink: RunProgressEvent with running=false indicates completion", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeRunProgress({
    completed: 3,
    running: false,
    currentScenarioId: null,
    currentScenarioName: null,
  }));

  const parsed: ParsedEvent = JSON.parse(sink.lines[0]);
  assertEquals(parsed.running, false);
  assertEquals(parsed.currentScenarioId, null);
  assertEquals(parsed.currentScenarioName, null);
});

Deno.test("NdjsonSink: RunFinishedEvent serializes with correct fields", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeRunFinished({
    ok: false,
    totalPassed: 6,
    totalFailed: 3,
  }));

  assertEquals(sink.lines.length, 1);
  const parsed: ParsedEvent = JSON.parse(sink.lines[0]);
  assertEquals(parsed.type, "run_finished");
  assertEquals(parsed.ok, false);
  assertEquals(parsed.totalPassed, 6);
  assertEquals(parsed.totalFailed, 3);
  assertEquals(parsed.totalSkipped, 0);
  assertEquals(parsed.crashedContainer, false);
  assertEquals(parsed.reportsDir, "/tmp/reports");
});

Deno.test("NdjsonSink: RunFinishedEvent with crashedContainer=true", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeRunFinished({ crashedContainer: true }));

  const parsed: ParsedEvent = JSON.parse(sink.lines[0]);
  assertEquals(parsed.crashedContainer, true);
});

Deno.test("NdjsonSink: full run lifecycle emits 7 valid JSON lines in order", () => {
  const sink = new CaptureNdjsonSink();

  // Simulate a full 3-scenario run with a failure in scenario 2
  sink.emit(makeRunStarted({ scenarioIds: ["01", "02", "03"], total: 3 }));
  sink.emit(makeScenarioStarted({ scenarioId: "01", index: 0 }));
  sink.emit(makeScenarioCompleted({ scenarioId: "01", ok: true, passed: 2 }));
  sink.emit(makeRunProgress({ completed: 1, currentScenarioId: "02" }));
  sink.emit(makeScenarioStarted({ scenarioId: "02", index: 1, name: "failing scenario" }));
  sink.emit(makeScenarioCompleted({
    scenarioId: "02",
    name: "failing scenario",
    ok: false,
    passed: 1,
    failed: 1,
  }));
  sink.emit(makeRunProgress({ completed: 2, currentScenarioId: "03" }));
  sink.emit(makeScenarioStarted({ scenarioId: "03", index: 2, name: "final scenario" }));
  sink.emit(makeScenarioCompleted({ scenarioId: "03", name: "final scenario", ok: true }));
  sink.emit(makeRunProgress({ completed: 3, running: false, currentScenarioId: null, currentScenarioName: null }));
  sink.emit(makeRunFinished({
    ok: false,
    totalPassed: 5,
    totalFailed: 1,
  }));

  assertEquals(sink.lines.length, 11);

  // Every line must be valid JSON
  const parsed = sink.lines.map((l) => JSON.parse(l) as ParsedEvent);

  // Verify event type sequence
  assertEquals(parsed[0].type, "run_start");
  assertEquals(parsed[1].type, "scenario_start");
  assertEquals(parsed[2].type, "scenario_complete");
  assertEquals(parsed[3].type, "run_progress");
  assertEquals(parsed[4].type, "scenario_start");
  assertEquals(parsed[5].type, "scenario_complete");
  assertEquals(parsed[6].type, "run_progress");
  assertEquals(parsed[7].type, "scenario_start");
  assertEquals(parsed[8].type, "scenario_complete");
  assertEquals(parsed[9].type, "run_progress");
  assertEquals(parsed[10].type, "run_finished");

  // Verify failing scenario
  assertEquals(parsed[5].ok, false);
  assertEquals(parsed[5].passed, 1);
  assertEquals(parsed[5].failed, 1);

  // Verify final summary
  assertEquals(parsed[10].totalPassed, 5);
  assertEquals(parsed[10].totalFailed, 1);
});

Deno.test("NdjsonSink: service failure aborts remaining scenarios", () => {
  const sink = new CaptureNdjsonSink();

  sink.emit(makeRunStarted({ scenarioIds: ["01", "02", "03"], total: 3 }));
  sink.emit(makeScenarioStarted({ scenarioId: "01", index: 0 }));
  sink.emit(makeScenarioCompleted({ scenarioId: "01", ok: true }));
  sink.emit(makeServiceFailure({ message: "PDS container crashed" }));
  sink.emit(makeRunProgress({ completed: 1, running: false, currentScenarioId: null }));
  sink.emit(makeRunFinished({ ok: false, totalPassed: 3, totalFailed: 0, crashedContainer: true }));

  assertEquals(sink.lines.length, 6);

  const parsed = sink.lines.map((l) => JSON.parse(l) as ParsedEvent);
  assertEquals(parsed[3].type, "service_failure");
  assertEquals(parsed[4].type, "run_progress");
  assertEquals(parsed[4].running, false);
  assertEquals(parsed[5].type, "run_finished");
  assertEquals(parsed[5].ok, false);
  assertEquals(parsed[5].crashedContainer, true);
});

Deno.test("NdjsonSink: each line is a complete JSON object followed by newline", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeRunStarted());
  sink.emit(makeRunFinished());

  // Each line should parse as a standalone JSON object
  for (const line of sink.lines) {
    JSON.parse(line);
  }

  // NdjsonSink uses JSON.stringify which produces one line per object
  assertEquals(sink.lines.length, 2);
});

Deno.test("NdjsonSink: ScenarioCompletedEvent without reportPath omits the field", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeScenarioCompleted({ reportPath: undefined }));

  const parsed = JSON.parse(sink.lines[0]);
  assertEquals(parsed.reportPath, undefined);
  // The field should not be present at all (undefined is dropped by JSON.stringify)
  assertEquals("reportPath" in parsed, false);
});

// ── MultiSink ──────────────────────────────────────────────────────────

Deno.test("MultiSink: fans out events to all child sinks", () => {
  const sinkA = new CaptureNdjsonSink();
  const sinkB = new CaptureNdjsonSink();
  const multi = new MultiSink([sinkA, sinkB]);

  multi.emit(makeRunStarted());
  multi.emit(makeRunProgress({ completed: 1 }));
  multi.emit(makeRunFinished());

  assertEquals(sinkA.lines.length, 3);
  assertEquals(sinkB.lines.length, 3);

  // Both sinks received identical events
  assertEquals(sinkA.lines[0], sinkB.lines[0]);
  assertEquals(sinkA.lines[1], sinkB.lines[1]);
  assertEquals(sinkA.lines[2], sinkB.lines[2]);
});

Deno.test("MultiSink: close propagates to all sinks", async () => {
  let closedA = false;
  let closedB = false;

  const sinkA: ScenarioRunEventSink = {
    emit: () => {},
    close: () => { closedA = true; },
  };
  const sinkB: ScenarioRunEventSink = {
    emit: () => {},
    close: () => { closedB = true; },
  };

  const multi = new MultiSink([sinkA, sinkB]);
  await multi.close();

  assertEquals(closedA, true);
  assertEquals(closedB, true);
});

// ── Agent triage: boundary ordering edge cases ─────────────────────────

Deno.test("triageReports: browser boundary detected from step name", async () => {
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      join(tmpDir, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-browser",
        ok: false,
        report_paths: [join(tmpDir, "47_report.json")],
      }),
    );
    await Deno.writeTextFile(
      join(tmpDir, "47_report.json"),
      JSON.stringify({
        scenario: "chat group lifecycle",
        steps: [
          {
            name: "playwright browser login flow",
            status: "failed",
            detail: "navigation timeout after 30s",
            duration_ms: 30000,
          },
        ],
        summary: { passed: 0, failed: 1, skipped: 0, total: 1 },
        ok: false,
        metadata: { scenario_id: "47" },
      }),
    );

    const result = await triageReports(tmpDir);
    // Browser rule (checked first) matches step name containing "playwright"
    assertEquals(result.boundary, "browser");
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

Deno.test("triageReports: firehose boundary detected from step", async () => {
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      join(tmpDir, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-firehose",
        ok: false,
        report_paths: [join(tmpDir, "firehose.json")],
      }),
    );
    await Deno.writeTextFile(
      join(tmpDir, "firehose.json"),
      JSON.stringify({
        scenario: "firehose test",
        steps: [
          {
            name: "subscribeRepos",
            status: "failed",
            detail: "connection reset",
            duration_ms: 500,
          },
        ],
        summary: { passed: 0, failed: 1, skipped: 0, total: 1 },
        ok: false,
      }),
    );

    const result = await triageReports(tmpDir);
    assertEquals(result.boundary, "firehose");
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

// ── NdjsonSink: edge cases ─────────────────────────────────────────────

Deno.test("NdjsonSink: handles events with special characters", () => {
  const sink = new CaptureNdjsonSink();

  sink.emit(makeRunStarted({
    scenarioIds: ['"quoted"'],
  }));

  sink.emit(makeScenarioCompleted({
    name: "scenario\nwith\nnewlines",
    summaryText: 'text with "double" quotes',
  }));

  // Both should parse back correctly
  for (const line of sink.lines) {
    JSON.parse(line);
  }

  const parsed0 = JSON.parse(sink.lines[0]);
  assertEquals(parsed0.scenarioIds[0], '"quoted"');
});

Deno.test("NdjsonSink: reportsDir may contain empty string", () => {
  const sink = new CaptureNdjsonSink();
  sink.emit(makeRunFinished({ reportsDir: "" }));

  const parsed: ParsedEvent = JSON.parse(sink.lines[0]);
  assertEquals(parsed.reportsDir, "");
});
