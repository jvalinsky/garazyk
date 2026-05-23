import { Cap, requires, Role } from "@garazyk/schemat";
import {
  browserFlows,
  formatRequirement,
  getRequires,
  getTimeout,
  hasRequirement,
  isScenarioCompatible,
  missingRequirements,
  missingRequirementsDescription,
  needsPds2,
  normalizeScenarioRequirements,
} from "./scenario_metadata.ts";

import { assertEquals, assertStringIncludes } from "@std/assert";

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

// ---------------------------------------------------------------------------
// needsPds2
// ---------------------------------------------------------------------------

Deno.test("needsPds2: returns true for scenario 05 (needsPds2: true)", () => {
  assertEquals(needsPds2("05"), true);
});

Deno.test("needsPds2: returns true for scenario 12", () => {
  assertEquals(needsPds2("12"), true);
});

Deno.test("needsPds2: returns false for scenario 01 (no pds2 flag)", () => {
  assertEquals(needsPds2("01"), false);
});

Deno.test("needsPds2: returns false for unknown scenario", () => {
  assertEquals(needsPds2("nonexistent-99"), false);
});

// ---------------------------------------------------------------------------
// browserFlows
// ---------------------------------------------------------------------------

Deno.test("browserFlows: returns smoke and login for scenario 11", () => {
  const flows = browserFlows("11");
  assertEquals(flows.includes("smoke"), true);
  assertEquals(flows.includes("login"), true);
});

Deno.test("browserFlows: returns empty array for scenario 01 (no browser)", () => {
  assertEquals(browserFlows("01"), []);
});

Deno.test("browserFlows: returns empty array for unknown scenario", () => {
  assertEquals(browserFlows("nonexistent"), []);
});

Deno.test("browserFlows: scenario 59 has smoke, login, and deep", () => {
  const flows = browserFlows("59");
  assertEquals(flows.includes("smoke"), true);
  assertEquals(flows.includes("login"), true);
  assertEquals(flows.includes("deep"), true);
});

// ---------------------------------------------------------------------------
// getRequires
// ---------------------------------------------------------------------------

Deno.test("getRequires: returns requirements for scenario 01", () => {
  const reqs = getRequires("01");
  assertEquals(reqs.length > 0, true);
  assertEquals(reqs[0].role, Role.plc);
  assertEquals(reqs[0].capability, Cap.plc.didResolution);
});

Deno.test("getRequires: returns empty array for unknown scenario", () => {
  assertEquals(getRequires("nonexistent"), []);
});

Deno.test("getRequires: returns multiple requirements for scenario 09", () => {
  const reqs = getRequires("09");
  assertEquals(reqs.length >= 3, true);
});

Deno.test("getRequires: scenario 11 requires the garazyk-ui role", () => {
  const reqs = getRequires("11");
  assertEquals(reqs, [
    requires(Role.ui, Cap.ui.smoke),
    requires(Role.ui, Cap.ui.login),
    requires(Role.ui, Cap.ui.oauth),
    requires(Role.ui, Cap.ui.admin),
  ]);
});

Deno.test("getRequires: cache scenarios advertise Mikrus and Beskid requirements", () => {
  assertEquals(
    getRequires("60").some((req) =>
      req.role === Role.mikrus &&
      req.capability === Cap.mikrus.getBacklinksCount
    ),
    true,
  );
  assertEquals(
    getRequires("69").some((req) =>
      req.role === Role.beskid &&
      req.capability === Cap.beskid.hydrateQueryResponse
    ),
    true,
  );
  assertEquals(
    getRequires("92").some((req) =>
      req.role === Role.beskid && req.capability === Cap.beskid.recordCache
    ),
    true,
  );
  assertEquals(
    getRequires("92").some((req) =>
      req.role === Role.mikrus && req.capability === Cap.mikrus.getBacklinks
    ),
    true,
  );
});

// ---------------------------------------------------------------------------
// getTimeout
// ---------------------------------------------------------------------------

Deno.test("getTimeout: returns undefined for scenarios without timeout override", () => {
  assertEquals(getTimeout("01"), undefined);
});

Deno.test("getTimeout: returns undefined for unknown scenario", () => {
  assertEquals(getTimeout("nonexistent"), undefined);
});

// ---------------------------------------------------------------------------
// formatRequirement
// ---------------------------------------------------------------------------

Deno.test("formatRequirement: formats role:capability as string", () => {
  const req = requires(Role.plc, Cap.plc.didResolution);
  const formatted = formatRequirement(req);
  assertStringIncludes(formatted, "plc");
  assertStringIncludes(formatted, "didResolution");
});

// ---------------------------------------------------------------------------
// hasRequirement
// ---------------------------------------------------------------------------

function makeTopology(
  roleCapMap: Record<string, string[]>,
): import("@garazyk/schemat").Topology {
  const capabilitiesByRole: Record<string, Set<string>> = {};
  const allCaps = new Set<string>();
  for (const [role, caps] of Object.entries(roleCapMap)) {
    capabilitiesByRole[role] = new Set(caps);
    for (const c of caps) allCaps.add(c);
  }
  return {
    serviceUrls: {},
    internalUrls: {},
    serviceNames: {},
    capabilities: allCaps,
    capabilitiesByRole,
  };
}

Deno.test("hasRequirement: returns true when capability is present in topology", () => {
  const topo = makeTopology({ plc: [Cap.plc.didResolution] });
  const needed = requires(Role.plc, Cap.plc.didResolution);
  assertEquals(hasRequirement(topo, needed), true);
});

Deno.test("hasRequirement: returns false when capability is missing from topology", () => {
  const topo = makeTopology({ plc: [Cap.plc.didResolution] });
  const needed = requires(Role.relay, Cap.relay.subscribeRepos);
  assertEquals(hasRequirement(topo, needed), false);
});

// ---------------------------------------------------------------------------
// missingRequirements
// ---------------------------------------------------------------------------

function makeScenarioInfo(
  id: string,
  reqs: ReturnType<typeof requires>[],
  pds2 = false,
): import("./scenario_metadata.ts").ScenarioInfo {
  return {
    id,
    name: `Scenario ${id}`,
    path: `/scenarios/${id}.ts`,
    requires: reqs,
    optional: [],
    needsPds2: pds2,
    browserFlows: [],
    parameters: {},
  };
}

Deno.test("missingRequirements: returns empty when all requirements are met", () => {
  const topo = makeTopology({
    plc: [Cap.plc.didResolution],
    relay: [Cap.relay.subscribeRepos],
  });
  const scenario = makeScenarioInfo("test", [
    requires(Role.plc, Cap.plc.didResolution),
  ]);
  assertEquals(missingRequirements(scenario, topo), []);
});

Deno.test("missingRequirements: returns missing requirements", () => {
  const topo = makeTopology({ plc: [Cap.plc.didResolution] });
  const scenario = makeScenarioInfo("test", [
    requires(Role.plc, Cap.plc.didResolution),
    requires(Role.relay, Cap.relay.subscribeRepos),
  ]);
  const missing = missingRequirements(scenario, topo);
  assertEquals(missing.length, 1);
  assertEquals(missing[0].role, Role.relay);
});

// ---------------------------------------------------------------------------
// isScenarioCompatible
// ---------------------------------------------------------------------------

Deno.test("isScenarioCompatible: returns true when all requirements are met", () => {
  const topo = makeTopology({ plc: [Cap.plc.didResolution] });
  const scenario = makeScenarioInfo("01", [
    requires(Role.plc, Cap.plc.didResolution),
  ]);
  assertEquals(isScenarioCompatible(scenario, topo), true);
});

Deno.test("isScenarioCompatible: returns false when a requirement is missing", () => {
  const topo = makeTopology({});
  const scenario = makeScenarioInfo("09", [
    requires(Role.relay, Cap.relay.subscribeRepos),
  ]);
  assertEquals(isScenarioCompatible(scenario, topo), false);
});

Deno.test("isScenarioCompatible: scenario with no requirements is always compatible", () => {
  const topo = makeTopology({});
  const scenario = makeScenarioInfo("any", []);
  assertEquals(isScenarioCompatible(scenario, topo), true);
});

Deno.test("isScenarioCompatible: returns false when pds2 scenario but topology lacks pds2", () => {
  const topo = makeTopology({ plc: [Cap.plc.didResolution] }); // no pds2 key
  const scenario = makeScenarioInfo("05", [
    requires(Role.plc, Cap.plc.didResolution),
  ], true);
  assertEquals(isScenarioCompatible(scenario, topo), false);
});
