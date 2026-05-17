import { assertEquals } from "@std/assert";
import {
  appendScenarioLoopResult,
  buildOtelReexecEnv,
} from "./run_scenarios.ts";
import { ScenarioResult } from "@garazyk/scenario-runner";
import type {
  ScenarioExecutionResult,
  ScenarioInfo,
} from "@garazyk/scenario-runner";

Deno.test("appendScenarioLoopResult preserves failed loop results for final summary", () => {
  const failed = new ScenarioResult("failed scenario");
  failed.start();
  failed.stepFailed("step", "boom");
  failed.finish();
  const scenario: ScenarioInfo = {
    id: "99",
    name: "failed scenario",
    path: "/tmp/scenario.ts",
    requires: [],
    optional: [],
    needsPds2: false,
    browserFlows: [],
    parameters: {},
  };
  const loopResult: ScenarioExecutionResult = {
    results: [{ scenario, result: failed }],
    reportPaths: ["/tmp/report.json"],
    crashedContainer: false,
  };
  const results: Array<{ scenario: ScenarioInfo; result: ScenarioResult }> = [];
  const reportPaths: string[] = [];

  appendScenarioLoopResult(loopResult, results, reportPaths);

  assertEquals(results.length, 1);
  assertEquals(results[0].result.ok, false);
  assertEquals(results[0].result.failed, 1);
  assertEquals(reportPaths, ["/tmp/report.json"]);
});

Deno.test("buildOtelReexecEnv sets defaults and guard", () => {
  const env = buildOtelReexecEnv(new Map());

  assertEquals(env.OTEL_DENO, "true");
  assertEquals(env.OTEL_EXPORTER_OTLP_ENDPOINT, "http://localhost:4318");
  assertEquals(env.OTEL_EXPORTER_OTLP_PROTOCOL, "http/protobuf");
  assertEquals(env.OTEL_SERVICE_NAME, "garazyk-e2e-runner");
  assertEquals(env.GARAZYK_OTEL_REEXEC, "1");
});
