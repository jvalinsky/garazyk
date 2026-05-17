import { assertEquals } from "@std/assert";
import { assert as scenarioAssert, ScenarioResult, timedCall } from "./mod.ts";
import { createCharacterRegistry, createScenarioConfig } from "./config.ts";
import { startLocalNetwork } from "./atproto_network.ts";

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

Deno.test("hamownia network orchestration is an explicit subpath export", () => {
  assertEquals(typeof startLocalNetwork, "function");
});
