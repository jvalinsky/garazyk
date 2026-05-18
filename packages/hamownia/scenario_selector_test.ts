import { assertEquals } from "@std/assert";
import { requires, Role } from "@garazyk/schemat";
import type { ScenarioRequirement, Topology } from "@garazyk/schemat";
import { selectScenarios } from "./scenario_selector.ts";
import type { ScenarioInfo } from "./scenario_metadata.ts";

/** Helper to convert string-form requirements to ScenarioRequirement objects. */
function req(...strings: string[]): ScenarioRequirement[] {
  return strings.map((value) => {
    const [roleName, capability] = value.split(":");
    if (roleName === Role.plc) return requires(Role.plc, capability as never);
    if (roleName === Role.relay) {
      return requires(Role.relay, capability as never);
    }
    if (roleName === Role.appview) {
      return requires(Role.appview, capability as never);
    }
    if (roleName === Role.chat) return requires(Role.chat, capability as never);
    throw new Error(`Unsupported test requirement: ${value}`);
  });
}

Deno.test("selectScenarios: role-scoped requirements filter default runs", () => {
  const topology: Topology = {
    serviceUrls: {},
    internalUrls: {},
    serviceNames: {},
    capabilities: new Set(["didResolution", "subscribeRepos"]),
    capabilitiesByRole: {
      plc: new Set(["didResolution"]),
      relay: new Set(["subscribeRepos"]),
      appview: new Set([]),
    },
  };
  const scenarios: ScenarioInfo[] = [
    {
      id: "01",
      name: "ok",
      path: "/tmp/01.ts",
      needsPds2: false,
      browserFlows: [],
      requires: req("plc:didResolution"),
      optional: [],
      parameters: {},
    },
    {
      id: "09",
      name: "missing appview",
      path: "/tmp/09.ts",
      needsPds2: false,
      browserFlows: [],
      requires: req("relay:subscribeRepos", "appview:backfill"),
      optional: [],
      parameters: {},
    },
  ];

  const selected = selectScenarios(scenarios, {
    scenarioIds: [],
    clientFlow: "none",
    pds2: false,
  }, topology);

  assertEquals(selected.map((s) => s.id), ["01"]);
});

Deno.test("selectScenarios: optional capabilities do not block default runs", () => {
  const topology: Topology = {
    serviceUrls: {},
    internalUrls: {},
    serviceNames: {},
    capabilities: new Set(["didResolution"]),
    capabilitiesByRole: {
      plc: new Set(["didResolution"]),
    },
  };
  const scenarios: ScenarioInfo[] = [
    {
      id: "01",
      name: "optional missing",
      path: "/tmp/01.ts",
      needsPds2: false,
      browserFlows: [],
      requires: req("plc:didResolution"),
      optional: req("appview:backfill"),
      parameters: {},
    },
  ];

  const selected = selectScenarios(scenarios, {
    scenarioIds: [],
    clientFlow: "none",
    pds2: false,
  }, topology);

  assertEquals(selected.map((s) => s.id), ["01"]);
});

Deno.test("selectScenarios: PDS2 scenarios are filtered by default and auto-enable when explicitly selected", () => {
  const topology: Topology = {
    serviceUrls: {},
    internalUrls: {},
    serviceNames: {},
    capabilities: new Set(["didResolution"]),
    capabilitiesByRole: {
      plc: new Set(["didResolution"]),
    },
  };
  const scenarios: ScenarioInfo[] = [
    {
      id: "35",
      name: "pds2 federation",
      path: "/tmp/35.ts",
      needsPds2: true,
      browserFlows: [],
      requires: req("plc:didResolution"),
      optional: [],
      parameters: {},
    },
  ];

  const defaultSelected = selectScenarios(scenarios, {
    scenarioIds: [],
    clientFlow: "none",
    pds2: false,
  }, topology);
  assertEquals(
    defaultSelected.map((s) => s.id),
    [],
  );

  const explicitSelected = selectScenarios(scenarios, {
    scenarioIds: ["35"],
    clientFlow: "none",
    pds2: false,
  }, topology);
  assertEquals(explicitSelected.map((s) => s.id), ["35"]);
  assertEquals(
    explicitSelected.some((s) => s.needsPds2),
    true,
  );
});

Deno.test("selectScenarios: explicit scenario IDs bypass missing requirements", () => {
  const topology: Topology = {
    serviceUrls: {},
    internalUrls: {},
    serviceNames: {},
    capabilities: new Set(["subscribeRepos"]),
    capabilitiesByRole: {
      relay: new Set(["subscribeRepos"]),
      appview: new Set([]),
    },
  };
  const scenarios: ScenarioInfo[] = [
    {
      id: "09",
      name: "explicit missing appview",
      path: "/tmp/09.ts",
      needsPds2: false,
      browserFlows: [],
      requires: req("relay:subscribeRepos", "appview:backfill"),
      optional: [],
      parameters: {},
    },
  ];

  const selected = selectScenarios(scenarios, {
    scenarioIds: ["09"],
    clientFlow: "none",
    pds2: false,
  }, topology);

  assertEquals(selected.map((s) => s.id), ["09"]);
});
