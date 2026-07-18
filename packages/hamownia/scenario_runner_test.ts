import { assertEquals, assertStringIncludes } from "@std/assert";
import {
  buildDockerScenarioRunnerOptions,
  buildHostScenarioEnv,
  runScenario,
} from "./scenario_runner.ts";
import { buildDockerRunnerArgs } from "./docker_runner.ts";
import type { RunnerArgs } from "./run_scenarios_types.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";
import type { Topology } from "@garazyk/schemat";

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
    isolation: "auto",
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
    needsPds3: false,
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
    import { ScenarioResult } from "@garazyk/hamownia";
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

Deno.test("buildHostScenarioEnv exposes normalized host service URLs", () => {
  const topo = topology();
  topo.serviceUrls = {
    pds: "http://localhost:2583",
    pds2: "http://localhost:2587",
    chat: "http://localhost:2585",
    mikrus: "http://localhost:3210",
    beskid: "http://localhost:8085",
    relay: "ws://localhost:2584",
  };
  topo.manifest = {
    version: 1,
    name: "test",
    networkName: "test-net",
    serviceUrls: topo.serviceUrls,
    internalUrls: {},
    serviceNames: {},
    scenarioEnv: {
      CHAT_URL: "http://localhost:2585",
      CUSTOM_VALUE: "localhost",
    },
  } as unknown as Topology["manifest"];

  const env = buildHostScenarioEnv(args(), topo);

  assertEquals(env.PDS_URL, "http://127.0.0.1:2583");
  assertEquals(env.PDS2_URL, "http://127.0.0.1:2587");
  assertEquals(env.CHAT_URL, "http://127.0.0.1:2585");
  assertEquals(env.MIKRUS_URL, "http://127.0.0.1:3210");
  assertEquals(env.BESKID_URL, "http://127.0.0.1:8085");
  assertEquals(env.RELAY_URL, "ws://127.0.0.1:2584");
  assertEquals(env.CUSTOM_VALUE, "localhost");
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
    import { ScenarioResult } from "@garazyk/hamownia";
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

Deno.test("Docker scenario options use schemat roleEnvKey mapping", () => {
  const dockerArgs = args();
  dockerArgs.runner = "docker";
  dockerArgs.clientFlow = "smoke";
  dockerArgs.allowHybridNetwork = true;
  dockerArgs.webClient = "dashboard";
  dockerArgs.topology = "garazyk-default";
  const topo = topology();
  topo.internalUrls = {
    pds2: "http://local-pds2:2583",
    appview: "http://local-appview:3200",
  };
  topo.capabilities = new Set(["createAccount"]);

  const options = buildDockerScenarioRunnerOptions(
    scenario("/repo/scripts/scenarios/scenarios/99_test.ts"),
    30,
    dockerArgs,
    topo,
    "/repo",
    "garazyk-test",
  );
  const dockerCliArgs = buildDockerRunnerArgs({
    ...options,
    containerName: "hamownia-mapping-test",
  });

  assertEquals(options.roleEnvMapper?.("pds2"), "PDS2_URL");
  assertEquals(dockerCliArgs.includes("PDS2_URL=http://local-pds2:2583"), true);
  assertEquals(
    dockerCliArgs.includes("APPVIEW_URL=http://local-appview:3200"),
    true,
  );
  assertEquals(
    dockerCliArgs.includes("ATPROTO_TOPOLOGY_CAPABILITIES=createAccount"),
    true,
  );
  assertEquals(options.env?.ATPROTO_CLIENT_FLOW, "smoke");
  assertEquals(options.env?.ATPROTO_ALLOW_HYBRID_NETWORK, "1");
  assertEquals(options.env?.ATPROTO_WEB_CLIENT, "dashboard");
  assertEquals(options.env?.ATPROTO_TOPOLOGY, "garazyk-default");
});

Deno.test("Docker scenario options expose implicit default topology", () => {
  const dockerArgs = args();
  dockerArgs.runner = "docker";
  const topo = topology();
  topo.preset = {
    name: "garazyk-default",
    description: "standard local network",
    roles: {},
  };

  const options = buildDockerScenarioRunnerOptions(
    scenario("/repo/scripts/scenarios/scenarios/11_lab_oauth_login.ts"),
    30,
    dockerArgs,
    topo,
    "/repo",
    "garazyk-test",
  );

  assertEquals(options.env?.ATPROTO_TOPOLOGY, "garazyk-default");
});
