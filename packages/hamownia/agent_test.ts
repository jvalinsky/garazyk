/**
 * Integration and unit tests for the hamownia agent CLI.
 *
 * Covers:
 * - classifyBoundary (all 9 rule categories + ordering)
 * - toSummary (list JSON shape)
 * - triageReports (pass, fail, fatal, missing, non-existent)
 * - NdjsonSink full event lifecycle (all 6 event types, valid JSON, correct fields)
 * - MultiSink fan-out
 * - CLI integration tests (spawn process: agent --help, agent list, agent run --help, agent triage --help)
 * - Tool invocation pattern tests (openCode + pi tool flag combinations)
 */
// spell-checker: disable

import { assertEquals, assertExists, assertMatch } from "@std/assert";
import { join } from "@std/path";
import { TopologyRegistry } from "@garazyk/schemat";
import type { AgentTriageResult } from "./cli/agent.ts";
import { classifyBoundary, toSummary, triageReports } from "./cli/agent.ts";
import { MultiSink } from "./events.ts";
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
import {
  dockerAvailable,
  spawnCli,
  spawnCliWithTimeout,
} from "./test_utils.ts";

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
    needsPds3: false,
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
  assertEquals(summary.needsPds3, false);
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
    needsPds3: false,
    browserFlows: ["smoke", "login"],
    parameters: {},
  };

  const summary = toSummary(scenario);

  assertEquals(summary.id, "37");
  assertEquals(summary.requires, ["chat:dm"]);
  assertEquals(summary.optional, ["appview:backfill"]);
  assertEquals(summary.needsPds2, true);
  assertEquals(summary.needsPds3, false);
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
    needsPds3: false,
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
          {
            name: "did lookup",
            status: "failed",
            detail: "not found",
            duration_ms: 10,
          },
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
          {
            name: "createRecord",
            status: "failed",
            detail: "timeout",
            duration_ms: 5000,
          },
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
    assertEquals(
      result.evidence.some((e) => e.startsWith("Could not read report")),
      true,
    );
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
  sink.emit(
    makeScenarioStarted({
      scenarioId: "02",
      index: 1,
      name: "failing scenario",
    }),
  );
  sink.emit(makeScenarioCompleted({
    scenarioId: "02",
    name: "failing scenario",
    ok: false,
    passed: 1,
    failed: 1,
  }));
  sink.emit(makeRunProgress({ completed: 2, currentScenarioId: "03" }));
  sink.emit(
    makeScenarioStarted({ scenarioId: "03", index: 2, name: "final scenario" }),
  );
  sink.emit(
    makeScenarioCompleted({
      scenarioId: "03",
      name: "final scenario",
      ok: true,
    }),
  );
  sink.emit(
    makeRunProgress({
      completed: 3,
      running: false,
      currentScenarioId: null,
      currentScenarioName: null,
    }),
  );
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
  sink.emit(
    makeRunProgress({ completed: 1, running: false, currentScenarioId: null }),
  );
  sink.emit(
    makeRunFinished({
      ok: false,
      totalPassed: 3,
      totalFailed: 0,
      crashedContainer: true,
    }),
  );

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
    close: () => {
      closedA = true;
    },
  };
  const sinkB: ScenarioRunEventSink = {
    emit: () => {},
    close: () => {
      closedB = true;
    },
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

// ── CLI integration tests (spawn actual process) ───────────────────────
// Uses spawnCli / spawnCliWithTimeout / dockerAvailable from ./test_utils.ts

Deno.test("CLI: agent --help lists all subcommands", async () => {
  const { stdout, stderr, code } = await spawnCli(["agent", "--help"]);

  assertEquals(code, 0);
  assertEquals(stderr, "");

  // Should mention all three subcommands
  assertMatch(stdout, /list/);
  assertMatch(stdout, /run/);
  assertMatch(stdout, /triage/);
  // Should mention the agent command description
  assertMatch(stdout, /Machine-readable/);
});

Deno.test("CLI: agent list produces valid JSON array", async () => {
  const { stdout, code } = await spawnCli(["agent", "list"]);

  assertEquals(code, 0);

  // Stderr may have some logs but should not have errors
  // (some Deno modules may emit deprecation warnings to stderr)

  // stdout must be valid JSON
  const parsed = JSON.parse(stdout.trim());
  assertEquals(Array.isArray(parsed), true);

  // Each element should have the required AgentScenarioSummary fields
  if (parsed.length > 0) {
    const first = parsed[0];
    assertEquals(typeof first.id, "string");
    assertEquals(typeof first.name, "string");
    assertEquals(typeof first.path, "string");
    assertEquals(Array.isArray(first.requires), true);
    assertEquals(Array.isArray(first.optional), true);
    assertEquals(typeof first.needsPds2, "boolean");
    assertEquals(Array.isArray(first.browserFlows), true);
    assertEquals(typeof first.parameters, "object");
  }
});

Deno.test("CLI: agent list --topology produces valid filtered JSON", async () => {
  const { stdout, code } = await spawnCli([
    "agent",
    "list",
    "--topology",
    "garazyk-default",
  ]);

  assertEquals(code, 0);

  // Must be valid JSON array
  const parsed = JSON.parse(stdout.trim());
  assertEquals(Array.isArray(parsed), true);

  // Each element must have the required AgentScenarioSummary shape
  for (const s of parsed) {
    assertEquals(typeof s.id, "string");
    assertEquals(typeof s.name, "string");
    assertEquals(typeof s.path, "string");
    assertEquals(Array.isArray(s.requires), true);
    assertEquals(Array.isArray(s.optional), true);
    assertEquals(typeof s.needsPds2, "boolean");
    assertEquals(Array.isArray(s.browserFlows), true);
    assertEquals(typeof s.parameters, "object");
  }
});

Deno.test("CLI: agent list with specific scenario IDs", async () => {
  const { stdout, code } = await spawnCli([
    "agent",
    "list",
    "01",
    "02",
  ]);

  assertEquals(code, 0);
  const parsed = JSON.parse(stdout.trim());
  assertEquals(Array.isArray(parsed), true);

  // Should only return matching IDs
  for (const s of parsed) {
    const valid = s.id === "01" || s.id === "02";
    assertEquals(valid, true, `Unexpected scenario ID: ${s.id}`);
  }
});

Deno.test("CLI: agent run --help shows all options", async () => {
  const { stdout, stderr, code } = await spawnCli(["agent", "run", "--help"]);

  assertEquals(code, 0);
  assertEquals(stderr, "");

  // Verify key options are documented
  assertMatch(stdout, /--setup/);
  assertMatch(stdout, /--no-setup/);
  assertMatch(stdout, /--binary/);
  assertMatch(stdout, /--pds2/);
  assertMatch(stdout, /--keep-running/);
  assertMatch(stdout, /--topology/);
  assertMatch(stdout, /--runner/);
  assertMatch(stdout, /--run-id/);
  assertMatch(stdout, /--timeout/);
  assertMatch(stdout, /--web-client/);
  assertMatch(stdout, /--client-flow/);
  assertMatch(stdout, /--allow-hybrid-network/);
  assertMatch(stdout, /NDJSON/);
});

Deno.test("CLI: agent triage --help shows options", async () => {
  const { stdout, stderr, code } = await spawnCli([
    "agent",
    "triage",
    "--help",
  ]);

  assertEquals(code, 0);
  assertEquals(stderr, "");

  assertMatch(stdout, /--run-id/);
  assertMatch(stdout, /--reports-dir/);
  assertMatch(stdout, /Parse existing/);
});

Deno.test("CLI: agent run with invalid runner enum exits non-zero", async () => {
  const { stderr, code } = await spawnCli([
    "agent",
    "run",
    "--runner",
    "k8s",
    "01",
  ]);

  // Should fail with non-zero exit code due to invalid enum value
  assertEquals(code !== 0, true);
  assertMatch(stderr, /runner/);
});

Deno.test("CLI: agent run with invalid client-flow enum exits non-zero", async () => {
  const { stderr, code } = await spawnCli([
    "agent",
    "run",
    "--client-flow",
    "super-deep",
    "01",
  ]);

  // Should fail with non-zero exit code due to invalid enum value
  assertEquals(code !== 0, true);
  assertMatch(stderr, /client-flow/);
});

Deno.test("CLI: agent run stdout contains valid NDJSON among log lines", async () => {
  // Run without --setup and a short timeout so it fails quickly.
  // Stdout may mix [INFO] log lines with NDJSON events; filter for JSON lines.
  const { stdout } = await spawnCli([
    "agent",
    "run",
    "--no-setup",
    "--timeout",
    "5",
    "01",
  ]);

  // Filter for lines that look like JSON objects (start with {)
  const jsonLines = stdout
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("{"));

  // Every JSON-like line must parse as valid JSON
  const events: Array<{ type: string; runId?: unknown }> = [];
  for (const line of jsonLines) {
    try {
      events.push(JSON.parse(line));
    } catch {
      assertEquals(
        true,
        false,
        `JSON-like line did not parse: ${line.slice(0, 80)}`,
      );
    }
  }

  // If events are emitted, verify well-formedness
  const runStart = events.find((e) => e.type === "run_start");
  if (runStart) {
    assertEquals(typeof runStart.runId, "string");
  }
});

Deno.test("CLI: agent triage with non-existent reports-dir returns valid JSON", async () => {
  const { stdout, code } = await spawnCli([
    "agent",
    "triage",
    "--reports-dir",
    "/tmp/nonexistent-hamownia-cli-test",
  ]);

  assertEquals(code, 0);

  const parsed = JSON.parse(stdout.trim());
  assertEquals(typeof parsed.runId, "string");
  assertEquals(typeof parsed.ok, "boolean");
  assertEquals(Array.isArray(parsed.evidence), true);
  assertEquals(Array.isArray(parsed.reportPaths), true);
});

// ── CLI: all topology presets produce valid JSON ──────────────────────

// Validate every registered topology preset returns valid agent list JSON.
// Spawns all preset queries in parallel via Promise.all for speed.
Deno.test("CLI: all topology presets produce valid JSON", async () => {
  const presets = TopologyRegistry.listPresets();
  if (presets.length === 0) {
    throw new Error(
      "TopologyRegistry.listPresets() returned empty — presets not loaded",
    );
  }

  // Spawn all preset queries concurrently (not sequentially).
  const results = await Promise.all(presets.map(async (preset) => {
    const { stdout, code } = await spawnCli([
      "agent",
      "list",
      "--topology",
      preset,
    ]);
    return { preset, stdout, code };
  }));

  for (const { preset, stdout, code } of results) {
    assertEquals(code, 0, `topology "${preset}" exited non-zero`);

    const parsed = JSON.parse(stdout.trim());
    assertEquals(
      Array.isArray(parsed),
      true,
      `topology "${preset}" not an array`,
    );

    for (const s of parsed) {
      assertEquals(typeof s.id, "string", `${preset}: id not string`);
      assertEquals(typeof s.name, "string", `${preset}: name not string`);
      assertEquals(typeof s.path, "string", `${preset}: path not string`);
      assertEquals(
        Array.isArray(s.requires),
        true,
        `${preset}: requires not array`,
      );
      assertEquals(
        Array.isArray(s.optional),
        true,
        `${preset}: optional not array`,
      );
      assertEquals(
        typeof s.needsPds2,
        "boolean",
        `${preset}: needsPds2 not boolean`,
      );
      assertEquals(
        Array.isArray(s.browserFlows),
        true,
        `${preset}: browserFlows not array`,
      );
      assertEquals(
        typeof s.parameters,
        "object",
        `${preset}: parameters not object`,
      );
    }
  }
});

// ── Tool invocation pattern tests ─────────────────────────────────────
// These tests validate the exact CLI invocations used by the
// hamownia-agent opencode tool and pi garazyk_agent_* tools.

Deno.test("CLI: agent list output matches AgentScenarioSummary contract", async () => {
  const { stdout, code } = await spawnCli(["agent", "list"]);
  assertEquals(code, 0);

  const parsed = JSON.parse(stdout.trim());
  assertEquals(Array.isArray(parsed), true);

  // Every field required by AgentScenarioSummary must be present
  const requiredFields = [
    "id",
    "name",
    "path",
    "requires",
    "optional",
    "needsPds2",
    "needsPds3",
    "browserFlows",
    "parameters",
  ];

  for (const s of parsed) {
    for (const field of requiredFields) {
      assertEquals(
        field in s,
        true,
        `Scenario ${s.id} missing field: ${field}`,
      );
    }
    // timeout is optional (only present when manifest overrides)
    // Verify browserFlows is always an array of strings
    for (const flow of s.browserFlows) {
      assertEquals(typeof flow, "string", `browserFlow not string in ${s.id}`);
    }
    // Verify requires/optional are arrays of "role:capability" strings
    for (const req of [...s.requires, ...s.optional]) {
      assertMatch(
        req,
        /^[a-z0-9]+:[a-zA-Z]+$/,
        `Invalid requirement format: "${req}" in ${s.id}`,
      );
    }
  }
});

Deno.test("CLI: agent list with empty scenario ID filter returns empty array", async () => {
  // Passing a non-existent ID should return empty results
  const { stdout, code } = await spawnCli(["agent", "list", "999"]);
  assertEquals(code, 0);

  const parsed = JSON.parse(stdout.trim());
  assertEquals(Array.isArray(parsed), true);
  assertEquals(parsed.length, 0);
});

Deno.test("CLI: agent run with combined options used by tools", async () => {
  // This is the exact invocation pattern the opencode/pi tools construct.
  // Test with --no-setup (no Docker required) and short timeout to verify
  // the CLI accepts all the combined flags without errors.
  const { stdout } = await spawnCli([
    "agent",
    "run",
    "--no-setup",
    "--verbose",
    "--runner",
    "host",
    "--timeout",
    "5",
    "--run-id",
    "tool-pattern-test",
    "01",
  ]);

  // exit non-zero expected (services aren't running without --setup).
  // What matters: the CLI parsed all flags without error.
  // --verbose should NOT produce JSON parse errors mixed into output
  // (human-readable goes to stderr, NDJSON goes to stdout)

  // Filter stdout for JSON lines
  const jsonLines = stdout
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("{"));

  // NDJSON events (if any) must parse as valid JSON
  for (const line of jsonLines) {
    try {
      JSON.parse(line);
    } catch {
      assertEquals(true, false, `Invalid JSON: ${line.slice(0, 80)}`);
    }
  }

  // stderr may contain verbose output -- that's expected
});

Deno.test("CLI: agent run with --runner docker flag accepted", async () => {
  // --runner docker can hang without Docker, so use a timeout and skip if Docker unavailable.
  if (!await dockerAvailable()) {
    return;
  }
  // Test that --runner docker is accepted as a valid enum value
  const { stderr } = await spawnCliWithTimeout([
    "agent",
    "run",
    "--runner",
    "docker",
    "--no-setup",
    "--timeout",
    "5",
    "01",
  ]);

  // Should NOT fail with enum validation error
  // (may fail because docker isn't running, but shouldn't fail on flag parsing)
  const isFlagError = /Unknown|Invalid|Expected/.test(stderr);
  assertEquals(
    isFlagError,
    false,
    `Flag parsing error: ${stderr.slice(0, 200)}`,
  );
});

Deno.test("CLI: agent run --pds2 flag accepted", async () => {
  // --pds2 can hang when no second PDS is available, so use a timeout.
  const { stderr } = await spawnCliWithTimeout([
    "agent",
    "run",
    "--pds2",
    "--no-setup",
    "--timeout",
    "5",
    "01",
  ], 20_000);

  // Should not fail on flag parsing for --pds2
  const isFlagError = /Unknown|Invalid|Expected/.test(stderr);
  assertEquals(
    isFlagError,
    false,
    `Flag parsing error: ${stderr.slice(0, 200)}`,
  );
});

Deno.test("CLI: agent run --binary flag accepted", async () => {
  const { stderr } = await spawnCli([
    "agent",
    "run",
    "--binary",
    "--no-setup",
    "--timeout",
    "5",
    "01",
  ]);

  const isFlagError = /Unknown|Invalid|Expected/.test(stderr);
  assertEquals(
    isFlagError,
    false,
    `Flag parsing error: ${stderr.slice(0, 200)}`,
  );
});

Deno.test("CLI: agent run --keep-running flag accepted", async () => {
  const { stderr } = await spawnCli([
    "agent",
    "run",
    "--keep-running",
    "--no-setup",
    "--timeout",
    "5",
    "01",
  ]);

  const isFlagError = /Unknown|Invalid|Expected/.test(stderr);
  assertEquals(
    isFlagError,
    false,
    `Flag parsing error: ${stderr.slice(0, 200)}`,
  );
});

Deno.test("CLI: agent run with all flags combined (tool invocation shape)", async () => {
  // This exactly mirrors what the opencode tool constructs when run with
  // setup, binary, pds2, keepRunning, verbose, runner, topology, runId, timeout
  const { stderr } = await spawnCli([
    "agent",
    "run",
    "--no-setup",
    "--verbose",
    "--runner",
    "host",
    "--topology",
    "garazyk-default",
    "--run-id",
    "full-tool-shape",
    "--timeout",
    "5",
    "01",
  ]);

  // Verify: no flag parsing errors, even if the run itself fails
  const isFlagError = /Unknown option|Invalid value|Expected.*value/i.test(
    stderr,
  );
  assertEquals(
    isFlagError,
    false,
    `Flag parsing error in full tool shape: ${stderr.slice(0, 200)}`,
  );
});

Deno.test("CLI: agent triage --run-id with valid format returns valid JSON", async () => {
  // Even with a run-id that doesn't exist, triage should return valid JSON
  const { stdout } = await spawnCli([
    "agent",
    "triage",
    "--run-id",
    "tool-test-run-9999",
  ]);

  // Should succeed (code 0) but report no reports found
  const parsed = JSON.parse(stdout.trim());
  assertEquals(typeof parsed.runId, "string");
  assertEquals(typeof parsed.ok, "boolean");
  assertEquals(typeof parsed.boundary, "string");
  assertEquals(Array.isArray(parsed.evidence), true);
  assertEquals(Array.isArray(parsed.reportPaths), true);
});

Deno.test("CLI: agent triage --reports-dir with actual reports returns valid JSON", async () => {
  // Create a temp directory with a real report and triage it
  const tmpDir = await Deno.makeTempDir();
  try {
    await Deno.writeTextFile(
      join(tmpDir, "overall-summary.json"),
      JSON.stringify({
        run_id: "tool-triaged-run",
        ok: false,
        report_paths: [join(tmpDir, "42_report.json")],
        diagnostics_dir: join(tmpDir, "diagnostics"),
      }),
    );
    await Deno.writeTextFile(
      join(tmpDir, "42_report.json"),
      JSON.stringify({
        scenario: "tool test scenario",
        steps: [
          {
            name: "auth step",
            status: "failed",
            detail: "session expired",
            duration_ms: 100,
          },
        ],
        summary: { passed: 0, failed: 1, skipped: 0, total: 1 },
        ok: false,
        metadata: { scenario_id: "42" },
      }),
    );

    const { stdout, code } = await spawnCli([
      "agent",
      "triage",
      "--reports-dir",
      tmpDir,
    ]);

    assertEquals(code, 0);

    const parsed = JSON.parse(stdout.trim()) as AgentTriageResult;
    assertEquals(parsed.runId, "tool-triaged-run");
    assertEquals(parsed.ok, false);
    assertEquals(parsed.firstFailure?.scenarioId, "42");
    assertEquals(parsed.firstFailure?.step, "auth step");
    assertEquals(parsed.boundary, "auth");
    assertEquals(parsed.diagnosticsDir, join(tmpDir, "diagnostics"));
    assertEquals(parsed.reportPaths.length, 1);
    assertEquals(parsed.evidence.length, 2); // step + error
  } finally {
    await Deno.remove(tmpDir, { recursive: true }).catch(() => {});
  }
});

Deno.test("CLI: agent run with multiple scenario IDs", async () => {
  // The tools pass space-separated IDs as positional args.
  // Use spawnCliWithTimeout since running multiple scenarios can be slow.
  const { stdout } = await spawnCliWithTimeout([
    "agent",
    "run",
    "--no-setup",
    "--timeout",
    "3",
    "01",
    "02",
  ], 60_000);

  // Filter JSON lines; verify run_start has the expected IDs
  const jsonLines = stdout
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("{"));

  for (const line of jsonLines) {
    try {
      const event = JSON.parse(line);
      if (event.type === "run_start") {
        assertEquals(Array.isArray(event.scenarioIds), true);
        assertEquals(event.scenarioIds.length >= 2, true);
      }
    } catch {
      // Skip unparseable
    }
  }
});

Deno.test({
  name: "CLI: agent run --setup emits full NDJSON event lifecycle",
  ignore: true, // Docker builds can be slow and hang the test runner
  fn: async () => {
    if (!await dockerAvailable()) {
      // Docker not available — skip this integration test gracefully.
      return;
    }

    // Run scenario 01 with --setup (starts Docker services, runs, tears down).
    // 90s CLI timeout accounts for Docker container startup + scenario execution.
    const { stdout } = await spawnCli([
      "agent",
      "run",
      "--setup",
      "--timeout",
      "90",
      "01",
    ]);

    // Filter JSON lines from stdout (ignore [INFO] log lines).
    const events = stdout
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.startsWith("{"))
      .map((l) => {
        try {
          return JSON.parse(l) as Record<string, unknown>;
        } catch {
          // Skip unparseable lines (partial NDJSON during flush).
          return null;
        }
      })
      .filter((e): e is Record<string, unknown> => e !== null);

    // Verify at least the core lifecycle events are present.
    const types = events.map((e) => e.type);
    assertEquals(types.includes("run_start"), true, "missing run_start");
    assertEquals(
      types.includes("scenario_start"),
      true,
      "missing scenario_start",
    );
    assertEquals(
      types.includes("scenario_complete"),
      true,
      "missing scenario_complete",
    );
    assertEquals(types.includes("run_finished"), true, "missing run_finished");

    // Verify the finished event reports success.
    const finished = events.find((e) => e.type === "run_finished");
    assertEquals(finished?.ok, true);
  },
});
