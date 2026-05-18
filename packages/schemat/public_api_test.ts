import { assertEquals } from "@std/assert";
import { resolveTopology, TopologyRegistry } from "./mod.ts";
import { serviceUrl } from "./runtime.ts";
import { parseScenarioRequirement } from "./topology_schema.ts";

Deno.test("schemat root exposes pure topology parsing and resolution", () => {
  const requirement = parseScenarioRequirement("pds:createAccount");
  assertEquals(requirement.role, "pds");
  assertEquals(requirement.capability, "createAccount");

  const topology = resolveTopology(undefined, "garazyk-default");
  assertEquals(topology.serviceUrls.pds, "http://localhost:2583");
  assertEquals(
    TopologyRegistry.listPresets().includes("garazyk-default"),
    true,
  );
});

Deno.test("schemat runtime helpers are explicit subpath exports", () => {
  assertEquals(serviceUrl("pds"), "http://127.0.0.1:2583");
});
