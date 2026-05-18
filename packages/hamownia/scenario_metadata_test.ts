import { Cap, requires, Role } from "@garazyk/schemat";
import { normalizeScenarioRequirements } from "./scenario_metadata.ts";

import { assertEquals } from "@std/assert";

function compileTimeScenarioRequirementRejections(): void {
  const rawRequirement = "plc" + ":didResolution";
  // @ts-expect-error scenario requirements must be typed role/capability objects.
  normalizeScenarioRequirements([rawRequirement], "raw-string");

  normalizeScenarioRequirements(
    [
      // @ts-expect-error relay capabilities are rejected for plc requirements.
      requires(Role.plc, Cap.relay.subscribeRepos),
    ],
    "wrong-role",
  );
}
void compileTimeScenarioRequirementRejections;

Deno.test("normalizeScenarioRequirements accepts typed requirements", () => {
  assertEquals(
    normalizeScenarioRequirements([
      requires(Role.plc, Cap.plc.didResolution),
    ], "valid"),
    [{ role: Role.plc, capability: Cap.plc.didResolution }],
  );
});
