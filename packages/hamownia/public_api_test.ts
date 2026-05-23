import { assertEquals } from "@std/assert";
import { assert as scenarioAssert, ScenarioResult, timedCall } from "./mod.ts";
import { createCharacterRegistry, createScenarioConfig } from "./config.ts";
import {
  applyTopologyEnvironment,
  startLocalNetwork,
} from "@garazyk/hamownia/atproto_network.ts";
import {
  defaultBinaryServices,
  startBinaryServices,
} from "@garazyk/hamownia/binary_services.ts";
import { stopStaleDockerE2e } from "@garazyk/hamownia/stale_cleanup.ts";
import {
  buildDockerRunnerArgs,
  DOCKER_RUNNER_TIMEOUT_EXIT_CODE,
} from "@garazyk/hamownia/docker_runner.ts";
import { buildOtelReexecEnv } from "@garazyk/hamownia/run_command.ts";

Deno.test("hamownia root exposes scenario authoring primitives", () => {
  assertEquals(typeof ScenarioResult, "function");
  assertEquals(typeof timedCall, "function");
  assertEquals(typeof scenarioAssert.equal, "function");
});

Deno.test("hamownia config factory supports explicit registry defaults", () => {
  const config = createScenarioConfig({
    pds1: "http://pds-one.test",
    pds2: "http://pds-two.test",
  });
  const registry = createCharacterRegistry(config);

  assertEquals(registry.getCharacter("luna").pdsUrl, "http://pds-one.test");
  assertEquals(registry.getCharacter("nova").pdsUrl, "http://pds-two.test");
});

Deno.test("hamownia orchestration APIs are explicit subpath exports", () => {
  assertEquals(typeof startLocalNetwork, "function");
  assertEquals(typeof applyTopologyEnvironment, "function");
  assertEquals(typeof startBinaryServices, "function");
  assertEquals(defaultBinaryServices(), [
    "plc",
    "pds",
    "relay",
    "appview",
    "germ",
  ]);
  assertEquals(typeof stopStaleDockerE2e, "function");
  assertEquals(typeof buildDockerRunnerArgs, "function");
  assertEquals(DOCKER_RUNNER_TIMEOUT_EXIT_CODE, 124);
  assertEquals(typeof buildOtelReexecEnv, "function");
});
