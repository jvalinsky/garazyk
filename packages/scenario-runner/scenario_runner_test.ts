import { assertEquals, assertStringIncludes } from "@std/assert";
import { runScenario } from "./scenario_runner.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import type { Topology } from "@garazyk/atproto-topology";

function args(): RunnerArgs {
  return {
    scenarioIds: [],
    list: false,
    setupOnly: false,
    setup: false,
    teardown: false,
    teardownOnly: false,
    noSetup: true,
    binary: false,
    pds2: false,
    verbose: false,
    noJson: true,
    keepRunning: false,
    collectDiagnostics: false,
    timeout: 1,
    clientFlow: "none",
    allowHybridNetwork: false,
    runner: "host",
    otel: false,
  };
}

function topology(): Topology {
  return {
    serviceUrls: {
      pds: "http://localhost:2583",
      pds2: "http://localhost:2587",
    },
    internalUrls: {},
    serviceNames: {},
    capabilities: new Set(),
    capabilitiesByRole: {},
  };
}

function scenario(path: string, name = "Test Scenario"): ScenarioInfo {
  return {
    id: "99",
    name,
    path,
    requires: [],
    optional: [],
    needsPds2: false,
    browserFlows: [],
    parameters: {},
  };
}

async function writeScenario(source: string): Promise<string> {
  const dir = await Deno.makeTempDir({ prefix: "garazyk-scenario-test-" });
  const path = `${dir}/scenario.ts`;
  await Deno.writeTextFile(path, source);
  return path;
}

Deno.test("runScenario host child succeeds and returns report", async () => {
  const path = await writeScenario(`
    import { ScenarioResult } from "@garazyk/scenario-runner";
    export function run(): ScenarioResult {
      const result = new ScenarioResult("child success");
      result.start();
      result.stepPassed("step", "ok", 5);
      result.recordArtifact("artifact", { ok: true });
      result.metadata.source = "child";
      result.finish();
      return result;
    }
  `);

  const result = await runScenario(
    scenario(path),
    5,
    args(),
    topology(),
    "",
    "",
  );
  assertEquals(result.ok, true);
  assertEquals(result.passed, 1);
  assertEquals(result.artifacts.artifact, { ok: true });
  assertEquals(result.metadata.source, "child");
});

Deno.test("runScenario host child reports missing run export", async () => {
  const path = await writeScenario(`export const value = 1;`);

  const result = await runScenario(
    scenario(path),
    5,
    args(),
    topology(),
    "",
    "",
  );
  assertEquals(result.ok, false);
  assertEquals(result.failed, 1);
  assertStringIncludes(result.steps[0].detail, "No run() export");
});

Deno.test("runScenario host child kills hanging scenario on timeout", async () => {
  const path = await writeScenario(`
    import { ScenarioResult } from "@garazyk/scenario-runner";
    export async function run(): Promise<ScenarioResult> {
      await new Promise((resolve) => setTimeout(resolve, 60_000));
      const result = new ScenarioResult("late");
      result.stepPassed("late");
      return result;
    }
  `);

  const started = Date.now();
  const result = await runScenario(
    scenario(path),
    1,
    args(),
    topology(),
    "",
    "",
  );
  assertEquals(result.ok, false);
  assertEquals(result.failed, 1);
  assertStringIncludes(result.steps[0].detail, "Timed out after 1s");
  assertEquals(Date.now() - started < 5_000, true);
});
