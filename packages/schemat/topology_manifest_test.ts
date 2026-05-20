import { assertEquals, assertThrows } from "@std/assert";
import {
  defaultPortForRole,
  dependencyInfoForService,
  internalUrlForRole,
  parsePortMapping,
  publicUrlForRole,
  roleToEnvKey,
  sanitizeTopologyName,
  serviceNameForRole,
} from "./topology_manifest.ts";
import type { ServiceAdapter, TopologyPreset } from "./topology_types.ts";

function makeAdapter(overrides: Partial<ServiceAdapter> = {}): ServiceAdapter {
  return {
    name: "service",
    healthCheck: { path: null },
    capabilities: [],
    ...overrides,
  };
}

Deno.test("sanitizeTopologyName: preserves filesystem-safe characters", () => {
  assertEquals(sanitizeTopologyName("demo-1.2_topology"), "demo-1.2_topology");
});

Deno.test("sanitizeTopologyName: replaces unsafe characters with underscores", () => {
  assertEquals(
    sanitizeTopologyName("demo topology/with:bad*chars?"),
    "demo_topology_with_bad_chars_",
  );
});

Deno.test("serviceNameForRole: uses the default compose name when no adapter is provided", () => {
  assertEquals(serviceNameForRole("pds"), "local-pds");
});

Deno.test("serviceNameForRole: honors an explicit service name override", () => {
  assertEquals(
    serviceNameForRole("pds", makeAdapter({ serviceName: "custom-pds" })),
    "custom-pds",
  );
});

Deno.test("serviceNameForRole: falls back to the local name for experimental roles", () => {
  assertEquals(serviceNameForRole("x-demo-service"), "local-x-demo-service");
});

Deno.test("defaultPortForRole: returns the built-in default port", () => {
  assertEquals(defaultPortForRole("appview"), "3200");
});

Deno.test("defaultPortForRole: falls back to 8080 for unknown roles", () => {
  assertEquals(defaultPortForRole("x-demo-service"), "8080");
});

Deno.test("parsePortMapping: returns empty ports for missing or empty mappings", () => {
  assertEquals(parsePortMapping(undefined), { hostPort: "", containerPort: "" });
  assertEquals(parsePortMapping(""), { hostPort: "", containerPort: "" });
});

Deno.test("parsePortMapping: treats a single port as both host and container ports", () => {
  assertEquals(parsePortMapping("8080"), { hostPort: "8080", containerPort: "8080" });
});

Deno.test("parsePortMapping: parses host and container ports from a two-part mapping", () => {
  assertEquals(parsePortMapping("8080:80"), { hostPort: "8080", containerPort: "80" });
});

Deno.test("parsePortMapping: ignores an IP prefix and uses the last two segments", () => {
  assertEquals(
    parsePortMapping("127.0.0.1:8080:80"),
    { hostPort: "8080", containerPort: "80" },
  );
});

Deno.test("parsePortMapping: still uses the last two segments with multiple colons", () => {
  assertEquals(
    parsePortMapping("10.0.0.1:127.0.0.1:8080:80"),
    { hostPort: "8080", containerPort: "80" },
  );
});

Deno.test("publicUrlForRole: uses the mapped host port from the first port binding", () => {
  assertEquals(
    publicUrlForRole("pds", makeAdapter({ ports: ["127.0.0.1:9090:8080"] })),
    "http://localhost:9090",
  );
});

Deno.test("publicUrlForRole: falls back to the default role port when no ports are declared", () => {
  assertEquals(publicUrlForRole("pds", makeAdapter()), "http://localhost:2583");
});

Deno.test("internalUrlForRole: uses the mapped container port from the first port binding", () => {
  assertEquals(
    internalUrlForRole("pds", makeAdapter({ ports: ["127.0.0.1:9090:8080"] })),
    "http://local-pds:8080",
  );
});

Deno.test("internalUrlForRole: treats a single port as both the host and container port", () => {
  assertEquals(
    internalUrlForRole("pds", makeAdapter({ ports: ["9091"] })),
    "http://local-pds:9091",
  );
});

Deno.test("internalUrlForRole: falls back to the default role port when no ports are declared", () => {
  assertEquals(internalUrlForRole("pds", makeAdapter()), "http://local-pds:2583");
});

Deno.test("roleToEnvKey: maps built-in and experimental roles to environment keys", () => {
  assertEquals(roleToEnvKey("relay"), "RELAY_URL");
  assertEquals(roleToEnvKey("x-demo-service"), "X_DEMO_SERVICE_URL");
});

Deno.test("dependencyInfoForService: resolves direct and role dependencies", () => {
  const roles: TopologyPreset["roles"] = {
    relay: { inherit: "base-relay" },
    ui: makeAdapter({ name: "ui", serviceName: "ui-custom" }),
    pds: makeAdapter({ name: "pds", serviceName: "pds-custom" }),
  };

  assertEquals(
    dependencyInfoForService(
      {
        dependsOn: ["database"],
        dependsOnRoles: ["relay", "ui", "pds"],
      },
      roles,
    ),
    {
      requested: ["database", "relay", "ui", "pds"],
      composeServiceNames: ["database", "local-relay", "ui-custom", "pds-custom"],
    },
  );
});

Deno.test("dependencyInfoForService: throws when a referenced dependency role is missing", () => {
  assertThrows(
    () =>
      dependencyInfoForService(
        { dependsOnRoles: ["chat"] },
        {} as TopologyPreset["roles"],
      ),
    Error,
    'Dependency role "chat" is not defined in topology preset.',
  );
});
