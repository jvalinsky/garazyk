/**
 * Unit tests for agent CLI classification, triage, list JSON shape,
 * and NDJSON output.
 *
 * @module agent_test
 */

import { assertEquals, assertStringIncludes } from "@std/assert";
import { join } from "@std/path";
import { classifyBoundary, toSummary, triageReports } from "./cli/agent.ts";
import type { AgentScenarioSummary, AgentTriageResult } from "./cli/agent.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import { MultiSink, NdjsonSink } from "./events.ts";
import type { ScenarioRunEvent } from "./events.ts";

// ── toSummary — list JSON shape ────────────────────────────────────────

Deno.test("toSummary: produces valid AgentScenarioSummary shape", () => {
  const scenario: ScenarioInfo = {
    id: "01",
    name: "Account Lifecycle",
    path: "/tmp/scenarios/01_account.ts",
    requires: [
      { role: "plc" as const, capability: "didResolution" as const },
    ],
    optional: [],
    needsPds2: false,
    browserFlows: ["smoke" as const],
    timeout: 120,
    parameters: {},
  };

  const summary = toSummary(scenario);

  // All fields present
  assertEquals(summary.id, "01");
  assertEquals(summary.name, "Account Lifecycle");
  assertEquals(summary.path, "/tmp/scenarios/01_account.ts");
  assertEquals(summary.requires, ["plc:didResolution"]);
  assertEquals(summary.optional, []);
  assertEquals(summary.needsPds2, false);
  assertEquals(summary.browserFlows.length, 1);

  // Optional fields
  assertEquals(summary.timeout, undefined); // no manifest entry for "01"
  assertEquals(summary.parameters, {});
});

Deno.test("toSummary: picks up timeout and parameters from SCENARIO_MANIFESTS", () => {
  // Scenario 59 has timeout: undefined in manifest but 26 has timeout: 300
  const scenario: ScenarioInfo = {
    id: "59",
    name: "Thread Scale",
    path: "/tmp/scenarios/59_thread.ts",
    requires: [],
    optional: [],
    needsPds2: false,
    browserFlows: ["smoke" as const, "login" as const, "deep" as const],
    timeout: undefined,
    parameters: {},
  };

  const summary = toSummary(scenario);

  // From SCENARIO_MANIFESTS["59"]
  assertEquals(summary.browserFlows.length, 3);
  assertEquals(summary.parameters.scale, 1);
  assertEquals(summary.parameters.depth, 2);
});

Deno.test("toSummary: optional requirements are mapped correctly", () => {
  const scenario: ScenarioInfo = {
    id: "99",
    name: "Custom Scenario",
    path: "/tmp/scenarios/99_custom.ts",
    requires: [
      { role: "pds" as const, capability: "createRecord" as const },
    ],
    optional: [
      { role: "relay" as const, capability: "subscribeRepos" as const },
    ],
    needsPds2: true,
    browserFlows: [],
    timeout: undefined,
    parameters: {},
  };

  const summary = toSummary(scenario);

  assertEquals(summary.needsPds2, true);
  assertEquals(summary.requires, ["pds:createRecord"]);
  assertEquals(summary.optional, ["relay:subscribeRepos"]);
});

// ── classifyBoundary ───────────────────────────────────────────────────

Deno.test("classifyBoundary: timeout → startup", () => {
  assertEquals(classifyBoundary("any step", "operation timed out"), "startup");
});

Deno.test("classifyBoundary: auth step → auth", () => {
  assertEquals(classifyBoundary("authenticate", "bad password"), "auth");
});

Deno.test("classifyBoundary: login step → auth", () => {
  assertEquals(classifyBoundary("login with oauth", "invalid token"), "auth");
});

Deno.test("classifyBoundary: validate step → validation", () => {
  assertEquals(
    classifyBoundary("validate response", "schema mismatch"),
    "validation",
  );
});

Deno.test("classifyBoundary: assert step → validation", () => {
  assertEquals(
    classifyBoundary("assert did format", "expected abc got xyz"),
    "validation",
  );
});

Deno.test("classifyBoundary: xrpc error → route", () => {
  assertEquals(
    classifyBoundary("createRecord", "xrpc method not allowed"),
    "route",
  );
});

Deno.test("classifyBoundary: 404 error → route", () => {
  assertEquals(classifyBoundary("getRecord", "not found 404"), "route");
});

Deno.test("classifyBoundary: rate limit → rate_limit", () => {
  assertEquals(
    classifyBoundary("post", "rate limit exceeded 429"),
    "rate_limit",
  );
});

Deno.test("classifyBoundary: did step → identity", () => {
  assertEquals(classifyBoundary("resolve did", "timeout"), "startup");
  // startup takes priority when both patterns match
});

Deno.test("classifyBoundary: handle step → identity", () => {
  assertEquals(classifyBoundary("update handle", "conflict"), "identity");
});

Deno.test("classifyBoundary: createRecord → ingest", () => {
  assertEquals(
    classifyBoundary("createRecord AppBskyFeedPost", "bad request"),
    "ingest",
  );
});

Deno.test("classifyBoundary: subscribeRepos → firehose", () => {
  assertEquals(
    classifyBoundary("subscribeRepos", "connection reset"),
    "firehose",
  );
});

Deno.test("classifyBoundary: browser step → browser", () => {
  assertEquals(
    classifyBoundary("browser login flow", "navigation timeout"),
    "browser",
  );
});

Deno.test("classifyBoundary: playwright in error → browser", () => {
  assertEquals(
    classifyBoundary("any step", "playwright browser closed unexpectedly"),
    "browser",
  );
});

Deno.test("classifyBoundary: unmatched → unknown", () => {
  assertEquals(
    classifyBoundary("mystery step", "something strange happened"),
    "unknown",
  );
});

Deno.test("classifyBoundary: startup trumps identity when timeout present", () => {
  // "resolve did" matches identity, but "timed out" matches startup first
  assertEquals(
    classifyBoundary("resolve did", "request timed out after 30s"),
    "startup",
  );
});

// ── triageReports — pass case ──────────────────────────────────────────

Deno.test("triageReports: pass — all scenarios ok", async () => {
  const tmp = await Deno.makeTempDir({ prefix: "hamownia-triage-test-" });
  try {
    // Write an overall-summary.json with ok: true
    await Deno.writeTextFile(
      join(tmp, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-run-001",
        ok: true,
        report_paths: [join(tmp, "01_ok.json")],
      }),
    );

    // Write a passing scenario report
    await Deno.writeTextFile(
      join(tmp, "01_ok.json"),
      JSON.stringify({
        scenario: "01_account_lifecycle",
        ok: true,
        started_at: 1_700_000_000,
        finished_at: 1_700_000_003,
        duration_s: 3,
        steps: [
          {
            name: "create account",
            status: "passed",
            detail: "alice",
            duration_ms: 150,
          },
        ],
        summary: { passed: 1, failed: 0, skipped: 0, total: 1 },
        artifacts: {},
        metadata: { scenario_id: "01" },
      }),
    );

    const result = await triageReports(tmp);

    assertEquals(result.runId, "test-run-001");
    assertEquals(result.ok, true);
    assertEquals(result.firstFailure, undefined);
    assertEquals(result.boundary, "unknown");
    assertEquals(result.evidence.length, 0);
    assertEquals(result.reportPaths.length, 1);
  } finally {
    await Deno.remove(tmp, { recursive: true });
  }
});

// ── triageReports — failure case ───────────────────────────────────────

Deno.test("triageReports: failure — first failing step found", async () => {
  const tmp = await Deno.makeTempDir({ prefix: "hamownia-triage-test-" });
  try {
    await Deno.writeTextFile(
      join(tmp, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-run-002",
        ok: false,
        report_paths: [
          join(tmp, "01_pass.json"),
          join(tmp, "02_fail.json"),
          join(tmp, "03_also_fail.json"),
        ],
      }),
    );

    // First scenario passes
    await Deno.writeTextFile(
      join(tmp, "01_pass.json"),
      JSON.stringify({
        scenario: "01_pass",
        ok: true,
        started_at: 1_700_000_000,
        finished_at: 1_700_000_001,
        duration_s: 1,
        steps: [
          { name: "step", status: "passed", detail: "", duration_ms: 100 },
        ],
        summary: { passed: 1, failed: 0, skipped: 0, total: 1 },
        artifacts: {},
        metadata: {},
      }),
    );

    // Second scenario fails — this is the firstFailure
    await Deno.writeTextFile(
      join(tmp, "02_fail.json"),
      JSON.stringify({
        scenario: "02_auth_flow",
        ok: false,
        started_at: 1_700_000_001,
        finished_at: 1_700_000_003,
        duration_s: 2,
        steps: [
          {
            name: "resolve did",
            status: "passed",
            detail: "",
            duration_ms: 50,
          },
          {
            name: "authenticate",
            status: "failed",
            detail: "invalid credentials",
            duration_ms: 80,
          },
        ],
        summary: { passed: 1, failed: 1, skipped: 0, total: 2 },
        artifacts: {},
        metadata: { scenario_id: "02" },
      }),
    );

    // Third scenario also fails, but should be ignored (firstFailure wins)
    await Deno.writeTextFile(
      join(tmp, "03_also_fail.json"),
      JSON.stringify({
        scenario: "03_createRecord_fail",
        ok: false,
        started_at: 1_700_000_003,
        finished_at: 1_700_000_005,
        duration_s: 2,
        steps: [
          {
            name: "createRecord",
            status: "failed",
            detail: "bad request",
            duration_ms: 100,
          },
        ],
        summary: { passed: 0, failed: 1, skipped: 0, total: 1 },
        artifacts: {},
        metadata: {},
      }),
    );

    const result = await triageReports(tmp);

    assertEquals(result.runId, "test-run-002");
    assertEquals(result.ok, false);
    assertEquals(result.firstFailure?.scenarioId, "02");
    assertEquals(result.firstFailure?.scenarioName, "02_auth_flow");
    assertEquals(result.firstFailure?.step, "authenticate");
    assertEquals(result.firstFailure?.error, "invalid credentials");
    assertEquals(result.boundary, "auth");
    assertEquals(result.evidence.length, 2);
    assertStringIncludes(result.evidence[0], "authenticate");
    assertStringIncludes(result.evidence[1], "invalid credentials");
    assertEquals(result.reportPaths.length, 3);
  } finally {
    await Deno.remove(tmp, { recursive: true });
  }
});

// ── triageReports — fatal error case ───────────────────────────────────

Deno.test("triageReports: fatal — overall-summary has error field", async () => {
  const tmp = await Deno.makeTempDir({ prefix: "hamownia-triage-test-" });
  try {
    await Deno.writeTextFile(
      join(tmp, "overall-summary.json"),
      JSON.stringify({
        run_id: "test-run-003",
        ok: false,
        error:
          "xrpc method not allowed: POST /xrpc/com.atproto.server.createSession",
        diagnostics_dir: join(tmp, "diagnostics"),
      }),
    );

    const result = await triageReports(tmp);

    assertEquals(result.runId, "test-run-003");
    assertEquals(result.ok, false);
    assertEquals(result.boundary, "route");
    assertEquals(result.evidence.length, 1);
    assertStringIncludes(result.evidence[0], "Fatal error");
    assertEquals(result.diagnosticsDir, join(tmp, "diagnostics"));
    assertEquals(result.reportPaths.length, 0);
  } finally {
    await Deno.remove(tmp, { recursive: true });
  }
});

// ── triageReports — missing overall-summary ────────────────────────────

Deno.test("triageReports: missing — falls back to directory scan", async () => {
  const tmp = await Deno.makeTempDir({ prefix: "hamownia-triage-test-" });
  try {
    // No overall-summary.json — triage should discover reports by scanning
    await Deno.writeTextFile(
      join(tmp, "01_scenario.json"),
      JSON.stringify({
        scenario: "01_whatever",
        ok: true,
        started_at: 1_700_000_000,
        finished_at: 1_700_000_001,
        duration_s: 1,
        steps: [
          { name: "step1", status: "passed", detail: "", duration_ms: 100 },
        ],
        summary: { passed: 1, failed: 0, skipped: 0, total: 1 },
        artifacts: {},
        metadata: {},
      }),
    );

    const result = await triageReports(tmp, "custom-run-004");

    assertEquals(result.runId, "custom-run-004");
    assertEquals(result.ok, true);
    assertEquals(result.evidence.length, 1);
    assertStringIncludes(result.evidence[0], "No overall-summary.json");
    assertEquals(result.reportPaths.length, 1);
    assertStringIncludes(result.reportPaths[0], "01_scenario.json");
  } finally {
    await Deno.remove(tmp, { recursive: true });
  }
});

// ── triageReports — non-existent directory ─────────────────────────────

Deno.test("triageReports: missing dir — returns ok with evidence of absence", async () => {
  const tmp = await Deno.makeTempDir({ prefix: "hamownia-triage-" });
  try {
    const nonExistent = join(tmp, "nonexistent");

    const result = await triageReports(nonExistent, "run-005");

    assertEquals(result.runId, "run-005");
    assertEquals(result.ok, true);
    assertEquals(result.evidence.length, 1);
    assertStringIncludes(result.evidence[0], "No overall-summary.json");
    assertEquals(result.reportPaths.length, 0);
  } finally {
    await Deno.remove(tmp, { recursive: true });
  }
});

// ── NdjsonSink — emits valid JSON lines ────────────────────────────────

Deno.test("NdjsonSink: emits each event as a single JSON line", () => {
  // Use a helper class that captures instead of writing to real stdout
  class CaptureNdjsonSink extends NdjsonSink {
    captured: string[] = [];
    override emit(event: ScenarioRunEvent): void {
      this.captured.push(JSON.stringify(event));
    }
  }

  const captureSink = new CaptureNdjsonSink();

  captureSink.emit({
    type: "run_start",
    runId: "test-run",
    scenarioIds: ["01", "02"],
    total: 2,
    timestamp: 1_700_000_000_000,
  });

  captureSink.emit({
    type: "scenario_start",
    scenarioId: "01",
    name: "Account lifecycle",
    index: 0,
    total: 2,
    timestamp: 1_700_000_001_000,
  });

  captureSink.emit({
    type: "scenario_complete",
    scenarioId: "01",
    name: "Account lifecycle",
    ok: true,
    passed: 3,
    failed: 0,
    skipped: 1,
    durationS: 2.5,
    summaryText: "summary",
    reportPath: "/tmp/report.json",
    timestamp: 1_700_000_003_500,
  });

  assertEquals(captureSink.captured.length, 3);

  // Each captured string must be valid JSON
  for (const line of captureSink.captured) {
    const parsed = JSON.parse(line);
    assertEquals(typeof parsed.type, "string");
  }

  // First event is run_start
  const first = JSON.parse(captureSink.captured[0]);
  assertEquals(first.type, "run_start");
  assertEquals(first.runId, "test-run");

  // Second event is scenario_start
  const second = JSON.parse(captureSink.captured[1]);
  assertEquals(second.type, "scenario_start");
  assertEquals(second.scenarioId, "01");

  // Third event is scenario_complete
  const third = JSON.parse(captureSink.captured[2]);
  assertEquals(third.type, "scenario_complete");
  assertEquals(third.ok, true);
  assertEquals(third.passed, 3);
});

// ── NdjsonSink — all event types produce valid JSON ────────────────────

Deno.test("NdjsonSink: all event types produce parseable JSON", () => {
  class CaptureNdjsonSink extends NdjsonSink {
    readonly captured: string[] = [];
    override emit(event: ScenarioRunEvent): void {
      this.captured.push(JSON.stringify(event));
    }
  }

  const sink = new CaptureNdjsonSink();
  const now = 1_700_000_000_000;

  const events: ScenarioRunEvent[] = [
    {
      type: "run_start",
      runId: "r",
      scenarioIds: ["01"],
      total: 1,
      timestamp: now,
    },
    {
      type: "scenario_start",
      scenarioId: "01",
      name: "n",
      index: 0,
      total: 1,
      timestamp: now,
    },
    {
      type: "scenario_complete",
      scenarioId: "01",
      name: "n",
      ok: true,
      passed: 1,
      failed: 0,
      skipped: 0,
      durationS: 1,
      summaryText: "s",
      timestamp: now,
    },
    {
      type: "service_failure",
      message: "crash",
      source: "container_crash",
      timestamp: now,
    },
    {
      type: "run_progress",
      completed: 1,
      total: 1,
      currentScenarioId: "01",
      currentScenarioName: "n",
      running: true,
      timestamp: now,
    },
    {
      type: "run_finished",
      runId: "r",
      ok: true,
      totalPassed: 1,
      totalFailed: 0,
      totalSkipped: 0,
      reportsDir: "/tmp",
      crashedContainer: false,
      timestamp: now,
    },
  ];

  for (const event of events) {
    sink.emit(event);
  }

  assertEquals(sink.captured.length, 6);

  for (let i = 0; i < sink.captured.length; i++) {
    const parsed = JSON.parse(sink.captured[i]);
    assertEquals(parsed.type, events[i].type);
    assertEquals(parsed.timestamp, now);
  }
});

// ── MultiSink: fan-out works ───────────────────────────────────────────

Deno.test("MultiSink: forwards events to all child sinks", () => {
  const received: number[][] = [[], []];

  const sinkA = {
    emit(e: ScenarioRunEvent) {
      received[0].push(e.timestamp);
    },
  };
  const sinkB = {
    emit(e: ScenarioRunEvent) {
      received[1].push(e.timestamp);
    },
  };
  const multi = new MultiSink([sinkA, sinkB]);

  multi.emit({
    type: "run_start",
    runId: "r",
    scenarioIds: ["01"],
    total: 1,
    timestamp: 42,
  });

  assertEquals(received[0].length, 1);
  assertEquals(received[0][0], 42);
  assertEquals(received[1].length, 1);
  assertEquals(received[1][0], 42);
});

// ── AgentTriageResult exhaustive boundary values ────────────────────────

Deno.test("classifyBoundary: covers all 9 boundary rules", () => {
  // Each rule must classify at least one input:
  const cases: Array<[string, string, AgentTriageResult["boundary"]]> = [
    ["any step", "timed out after 5s", "startup"],
    ["createSession", "session expired", "auth"],
    ["validate schema", "assertion failed", "validation"],
    ["getRecord", "xrpc 405 Method Not Allowed", "route"],
    ["upload blob", "rate limited 429", "rate_limit"],
    ["resolve handle", "did not found", "identity"],
    ["createRecord with text", "encoding error", "ingest"],
    ["subscribeRepos firehose", "stream closed", "firehose"],
    ["browser oauth flow", "playwright crash", "browser"],
  ];

  for (const [step, err, expected] of cases) {
    assertEquals(
      classifyBoundary(step, err),
      expected,
      `classifyBoundary("${step}", "${err}") should be "${expected}"`,
    );
  }
});
