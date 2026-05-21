/**
 * Tests for writeOverallSummary — aggregation logic and JSON output.
 *
 * @module report_writer_test
 */

import { assertEquals } from "@std/assert";
import { ScenarioResult, StepStatus } from "./runner.ts";
import {
  writeOverallSummary,
  type OverallResultItem,
  type OverallSummaryContext,
} from "./report_writer.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeScenarioInfo(id: string): ScenarioInfo {
  return {
    id,
    name: `Scenario ${id}`,
    path: `/scenarios/${id}.ts`,
    requires: [],
    optional: [],
    needsPds2: false,
    browserFlows: [],
    parameters: {},
  };
}

function makeResult(passed: number, failed: number, skipped: number): ScenarioResult {
  const r = new ScenarioResult(`Scenario`);
  r.start();
  for (let i = 0; i < passed; i++) r.stepPassed(`pass-${i}`);
  for (let i = 0; i < failed; i++) r.stepFailed(`fail-${i}`);
  for (let i = 0; i < skipped; i++) {
    r.step(`skip-${i}`, StepStatus.SKIPPED);
  }
  r.finish();
  return r;
}

function makeResultItem(id: string, passed: number, failed: number, skipped = 0): OverallResultItem {
  return { scenario: makeScenarioInfo(id), result: makeResult(passed, failed, skipped) };
}

function makeArgs(overrides: Partial<RunnerArgs> = {}): RunnerArgs {
  return {
    scenarioIds: [],
    list: false,
    setupOnly: false,
    setup: false,
    teardown: false,
    teardownOnly: false,
    noSetup: false,
    binary: false,
    pds2: false,
    verbose: false,
    noJson: true, // default to noJson to avoid writing files
    keepRunning: false,
    collectDiagnostics: false,
    timeout: 120,
    clientFlow: "none",
    allowHybridNetwork: false,
    runner: "host",
    otel: false,
    ...overrides,
  };
}

function makeContext(runDir: string): OverallSummaryContext {
  return {
    runId: "test-run-001",
    runDir,
    diagnosticsDir: `${runDir}/diagnostics`,
  };
}

// ---------------------------------------------------------------------------
// Aggregation — pure return-value tests (noJson: true, no I/O)
// ---------------------------------------------------------------------------

Deno.test("writeOverallSummary: aggregates passed counts across results", async () => {
  const { totalPassed } = await writeOverallSummary({
    context: makeContext("/tmp/run"),
    results: [makeResultItem("01", 3, 0), makeResultItem("02", 5, 0)],
    selected: [],
    args: makeArgs(),
    reportPaths: [],
    reportsDir: "/tmp/reports",
    fatalError: null,
    withPds2: false,
  });
  assertEquals(totalPassed, 8);
});

Deno.test("writeOverallSummary: aggregates failed counts across results", async () => {
  const { totalFailed } = await writeOverallSummary({
    context: makeContext("/tmp/run"),
    results: [makeResultItem("01", 0, 2), makeResultItem("02", 0, 1)],
    selected: [],
    args: makeArgs(),
    reportPaths: [],
    reportsDir: "/tmp/reports",
    fatalError: null,
    withPds2: false,
  });
  assertEquals(totalFailed, 3);
});

Deno.test("writeOverallSummary: aggregates skipped counts across results", async () => {
  const { totalSkipped } = await writeOverallSummary({
    context: makeContext("/tmp/run"),
    results: [makeResultItem("01", 2, 0, 3), makeResultItem("02", 1, 0, 1)],
    selected: [],
    args: makeArgs(),
    reportPaths: [],
    reportsDir: "/tmp/reports",
    fatalError: null,
    withPds2: false,
  });
  assertEquals(totalSkipped, 4);
});

Deno.test("writeOverallSummary: empty results returns all zeros", async () => {
  const totals = await writeOverallSummary({
    context: makeContext("/tmp/run"),
    results: [],
    selected: [],
    args: makeArgs(),
    reportPaths: [],
    reportsDir: "/tmp/reports",
    fatalError: null,
    withPds2: false,
  });
  assertEquals(totals.totalPassed, 0);
  assertEquals(totals.totalFailed, 0);
  assertEquals(totals.totalSkipped, 0);
});

// ---------------------------------------------------------------------------
// JSON file output (noJson: false)
// ---------------------------------------------------------------------------

Deno.test("writeOverallSummary: writes overall-summary.json when noJson is false", async () => {
  const dir = await Deno.makeTempDir();
  try {
    await writeOverallSummary({
      context: makeContext(`${dir}/run`),
      results: [makeResultItem("01", 2, 0)],
      selected: [makeScenarioInfo("01")],
      args: makeArgs({ noJson: false }),
      reportPaths: [],
      reportsDir: dir,
      fatalError: null,
      withPds2: false,
    });
    const text = await Deno.readTextFile(`${dir}/overall-summary.json`);
    const parsed = JSON.parse(text);
    assertEquals(typeof parsed.run_id, "string");
    assertEquals(parsed.summary.passed, 2);
    assertEquals(parsed.ok, true);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("writeOverallSummary: does not write file when noJson is true", async () => {
  const dir = await Deno.makeTempDir();
  try {
    await writeOverallSummary({
      context: makeContext(`${dir}/run`),
      results: [makeResultItem("01", 1, 0)],
      selected: [],
      args: makeArgs({ noJson: true }),
      reportPaths: [],
      reportsDir: dir,
      fatalError: null,
      withPds2: false,
    });
    let exists = false;
    try {
      await Deno.stat(`${dir}/overall-summary.json`);
      exists = true;
    } catch { /* expected */ }
    assertEquals(exists, false);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("writeOverallSummary: ok is false when there are failures", async () => {
  const dir = await Deno.makeTempDir();
  try {
    await writeOverallSummary({
      context: makeContext(`${dir}/run`),
      results: [makeResultItem("01", 0, 1)],
      selected: [],
      args: makeArgs({ noJson: false }),
      reportPaths: [],
      reportsDir: dir,
      fatalError: null,
      withPds2: false,
    });
    const parsed = JSON.parse(await Deno.readTextFile(`${dir}/overall-summary.json`));
    assertEquals(parsed.ok, false);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("writeOverallSummary: fatalError increments failed count in JSON", async () => {
  const dir = await Deno.makeTempDir();
  try {
    await writeOverallSummary({
      context: makeContext(`${dir}/run`),
      results: [],
      selected: [],
      args: makeArgs({ noJson: false }),
      reportPaths: [],
      reportsDir: dir,
      fatalError: new Error("something broke"),
      withPds2: false,
    });
    const parsed = JSON.parse(await Deno.readTextFile(`${dir}/overall-summary.json`));
    assertEquals(parsed.summary.failed, 1);
    assertEquals(parsed.error, "something broke");
    assertEquals(parsed.ok, false);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("writeOverallSummary: non-Error fatalError has no error field in JSON", async () => {
  const dir = await Deno.makeTempDir();
  try {
    await writeOverallSummary({
      context: makeContext(`${dir}/run`),
      results: [],
      selected: [],
      args: makeArgs({ noJson: false }),
      reportPaths: [],
      reportsDir: dir,
      fatalError: "string error",
      withPds2: false,
    });
    const parsed = JSON.parse(await Deno.readTextFile(`${dir}/overall-summary.json`));
    assertEquals(parsed.error, undefined);
    assertEquals(parsed.summary.failed, 1);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("writeOverallSummary: JSON includes run_id, scenario_ids, binary_mode, client_flow", async () => {
  const dir = await Deno.makeTempDir();
  try {
    await writeOverallSummary({
      context: { runId: "my-run-xyz", runDir: dir, diagnosticsDir: dir },
      results: [],
      selected: [makeScenarioInfo("42"), makeScenarioInfo("07")],
      args: makeArgs({ noJson: false, binary: true, clientFlow: "smoke" }),
      reportPaths: [],
      reportsDir: dir,
      fatalError: null,
      withPds2: true,
    });
    const parsed = JSON.parse(await Deno.readTextFile(`${dir}/overall-summary.json`));
    assertEquals(parsed.run_id, "my-run-xyz");
    assertEquals(parsed.scenario_ids, ["42", "07"]);
    assertEquals(parsed.binary_mode, true);
    assertEquals(parsed.client_flow, "smoke");
    assertEquals(parsed.pds2, true);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
