import { assertEquals } from "@std/assert";
import { requiresManagedNetworkPreflight } from "./preflight.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";

function scenario(externalLifecycle: boolean): ScenarioInfo {
  return {
    id: externalLifecycle ? "100" : "01",
    name: "preflight fixture",
    path: "/tmp/scenario.ts",
    externalLifecycle,
    needsPds2: false,
    needsPds3: false,
    browserFlows: [],
    requires: [],
    optional: [],
    parameters: {},
  };
}

Deno.test("external-lifecycle-only selection skips managed network preflight", () => {
  assertEquals(requiresManagedNetworkPreflight([scenario(true)]), false);
});

Deno.test("mixed selection keeps managed network preflight", () => {
  assertEquals(
    requiresManagedNetworkPreflight([scenario(true), scenario(false)]),
    true,
  );
});

Deno.test("empty selection keeps managed network preflight", () => {
  assertEquals(requiresManagedNetworkPreflight([]), true);
});
