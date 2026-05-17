/**
 * Unit tests for ScenarioResult, timedCall, timedCallChecked, and unwrapOutcome.
 */

import { assertEquals, assertInstanceOf, assertRejects } from "jsr:@std/assert";
import {
  ScenarioResult,
  StepResult,
  StepStatus,
  timedCall,
  timedCallChecked,
  type TimedCallOutcome,
  unwrapOutcome,
} from "./runner.ts";

// ---------------------------------------------------------------------------
// ScenarioResult
// ---------------------------------------------------------------------------

Deno.test("ScenarioResult: starts with no steps", () => {
  const r = new ScenarioResult("test-scenario");
  assertEquals(r.scenarioName, "test-scenario");
  assertEquals(r.steps.length, 0);
  assertEquals(r.passed, 0);
  assertEquals(r.failed, 0);
  assertEquals(r.skipped, 0);
  assertEquals(r.total, 0);
  assertEquals(r.ok, false);
});

Deno.test("ScenarioResult: stepPassed increments passed count", () => {
  const r = new ScenarioResult("test");
  r.stepPassed("step 1", "detail", 100);
  assertEquals(r.passed, 1);
  assertEquals(r.failed, 0);
  assertEquals(r.total, 1);
  assertEquals(r.ok, true);
});

Deno.test("ScenarioResult: stepFailed makes ok false", () => {
  const r = new ScenarioResult("test");
  r.stepPassed("step 1");
  r.stepFailed("step 2", "error detail", 50);
  assertEquals(r.passed, 1);
  assertEquals(r.failed, 1);
  assertEquals(r.total, 2);
  assertEquals(r.ok, false);
});

Deno.test("ScenarioResult: stepSkipped counts as skipped", () => {
  const r = new ScenarioResult("test");
  r.stepSkipped("optional step", "not available");
  assertEquals(r.skipped, 1);
  assertEquals(r.passed, 0);
  assertEquals(r.failed, 0);
  assertEquals(r.ok, true);
});

Deno.test("ScenarioResult: ok is true when all steps pass or skip", () => {
  const r = new ScenarioResult("test");
  r.stepPassed("step 1");
  r.stepSkipped("step 2");
  assertEquals(r.ok, true);
});

Deno.test("ScenarioResult: ok is false when empty", () => {
  const r = new ScenarioResult("test");
  assertEquals(r.ok, false);
});

// ---------------------------------------------------------------------------
// ScenarioResult: start/finish timestamps
// ---------------------------------------------------------------------------

Deno.test("ScenarioResult: start and finish set timestamps", () => {
  const r = new ScenarioResult("test");
  r.start();
  assertEquals(r.startedAt !== null, true);
  r.finish();
  assertEquals(r.finishedAt !== null, true);
  assertEquals(r.finishedAt! >= r.startedAt!, true);
});

// ---------------------------------------------------------------------------
// ScenarioResult: artifacts
// ---------------------------------------------------------------------------

Deno.test("ScenarioResult: recordArtifact stores data", () => {
  const r = new ScenarioResult("test");
  r.recordArtifact("screenshot", { url: "http://example.com/img.png" });
  assertEquals(r.artifacts.screenshot, { url: "http://example.com/img.png" });
});

// ---------------------------------------------------------------------------
// ScenarioResult: toReport
// ---------------------------------------------------------------------------

Deno.test("ScenarioResult: toReport produces correct structure", () => {
  const r = new ScenarioResult("01_account_lifecycle");
  r.start();
  r.stepPassed("create account", "alice", 150);
  r.stepFailed("delete account", "not found", 30);
  r.stepSkipped("pds2 check", "no pds2");
  r.finish();
  r.recordArtifact("log", "data");

  const report = r.toReport();
  assertEquals(report.scenario, "01_account_lifecycle");
  assertEquals(report.ok, false);
  assertEquals(report.summary.passed, 1);
  assertEquals(report.summary.failed, 1);
  assertEquals(report.summary.skipped, 1);
  assertEquals(report.summary.total, 3);
  assertEquals(report.steps.length, 3);
  assertEquals(report.steps[0].name, "create account");
  assertEquals(report.steps[0].status, "passed");
  assertEquals(report.steps[0].duration_ms, 150);
  assertEquals(report.artifacts.log, "data");
});

// ---------------------------------------------------------------------------
// timedCallChecked
// ---------------------------------------------------------------------------

Deno.test("timedCallChecked: returns { ok: true, value } on success", async () => {
  const r = new ScenarioResult("test");
  const outcome = await timedCallChecked(r, "step", async () => 42);
  assertEquals(outcome.ok, true);
  if (outcome.ok) assertEquals(outcome.value, 42);
  assertEquals(r.passed, 1);
  assertEquals(r.failed, 0);
});

Deno.test("timedCallChecked: returns { ok: false, value: null } on failure", async () => {
  const r = new ScenarioResult("test");
  const outcome = await timedCallChecked(r, "step", async () => {
    throw new Error("boom");
  });
  assertEquals(outcome.ok, false);
  assertEquals(outcome.value, null);
  assertEquals(r.failed, 1);
  assertEquals(r.passed, 0);
});

Deno.test("timedCallChecked: expectFailure=true marks passed when call throws", async () => {
  const r = new ScenarioResult("test");
  const outcome = await timedCallChecked(
    r,
    "should fail",
    async () => {
      throw new Error("expected");
    },
    undefined,
    true,
  );
  assertEquals(outcome.ok, false);
  assertEquals(outcome.value, null);
  assertEquals(r.passed, 1);
  assertEquals(r.failed, 0);
});

Deno.test("timedCallChecked: expectFailure=true marks failed when call succeeds", async () => {
  const r = new ScenarioResult("test");
  const outcome = await timedCallChecked(
    r,
    "should fail",
    async () => "surprise",
    undefined,
    true,
  );
  assertEquals(outcome.ok, false);
  assertEquals(outcome.value, null);
  assertEquals(r.failed, 1);
  assertEquals(r.passed, 0);
});

Deno.test("timedCallChecked: detailFn produces step detail", async () => {
  const r = new ScenarioResult("test");
  const outcome = await timedCallChecked(
    r,
    "step",
    async () => ({ name: "alice" }),
    (res) => `created ${res.name}`,
  );
  assertEquals(outcome.ok, true);
  if (outcome.ok) assertEquals(outcome.value.name, "alice");
  assertEquals(r.steps[0].detail, "created alice");
});

// ---------------------------------------------------------------------------
// timedCall (backward compat)
// ---------------------------------------------------------------------------

Deno.test("timedCall: returns value on success", async () => {
  const r = new ScenarioResult("test");
  const val = await timedCall(r, "step", async () => "hello");
  assertEquals(val, "hello");
  assertEquals(r.passed, 1);
});

Deno.test("timedCall: returns null on failure", async () => {
  const r = new ScenarioResult("test");
  const val = await timedCall(r, "step", async () => {
    throw new Error("fail");
  });
  assertEquals(val, null);
  assertEquals(r.failed, 1);
});

// ---------------------------------------------------------------------------
// unwrapOutcome
// ---------------------------------------------------------------------------

Deno.test("unwrapOutcome: returns value when ok=true", () => {
  const outcome: TimedCallOutcome<string> = { ok: true, value: "data" };
  assertEquals(unwrapOutcome(outcome), "data");
});

Deno.test("unwrapOutcome: throws when ok=false", () => {
  const outcome: TimedCallOutcome<string> = { ok: false, value: null };
  try {
    unwrapOutcome(outcome);
    throw new Error("Should have thrown");
  } catch (e) {
    assertInstanceOf(e, Error);
    assertEquals((e as Error).message.includes("timedCall step failed"), true);
  }
});

// ---------------------------------------------------------------------------
// StepResult
// ---------------------------------------------------------------------------

Deno.test("StepResult: constructs with defaults", () => {
  const s = new StepResult("test step", StepStatus.PASSED);
  assertEquals(s.name, "test step");
  assertEquals(s.status, StepStatus.PASSED);
  assertEquals(s.detail, "");
  assertEquals(s.durationMs, 0);
});

Deno.test("StepResult: constructs with all fields", () => {
  const s = new StepResult("test step", StepStatus.FAILED, "error msg", 250);
  assertEquals(s.name, "test step");
  assertEquals(s.status, StepStatus.FAILED);
  assertEquals(s.detail, "error msg");
  assertEquals(s.durationMs, 250);
});
