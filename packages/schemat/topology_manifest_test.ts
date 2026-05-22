import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  createTopologyManifest,
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
  assertEquals(parsePortMapping(undefined), {
    hostPort: "",
    containerPort: "",
  });
  assertEquals(parsePortMapping(""), { hostPort: "", containerPort: "" });
});

Deno.test("parsePortMapping: treats a single port as both host and container ports", () => {
  assertEquals(parsePortMapping("8080"), {
    hostPort: "8080",
    containerPort: "8080",
  });
});

Deno.test("parsePortMapping: parses host and container ports from a two-part mapping", () => {
  assertEquals(parsePortMapping("8080:80"), {
    hostPort: "8080",
    containerPort: "80",
  });
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
  assertEquals(
    internalUrlForRole("pds", makeAdapter()),
    "http://local-pds:2583",
  );
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
      composeServiceNames: [
        "database",
        "local-relay",
        "ui-custom",
        "pds-custom",
      ],
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

// ---------------------------------------------------------------------------
// createTopologyManifest tests
// ---------------------------------------------------------------------------

function makePreset(overrides: Partial<TopologyPreset> = {}): TopologyPreset {
  return {
    name: "test-topology",
    description: "Test topology",
    roles: {},
    ...overrides,
  };
}

Deno.test("createTopologyManifest: produces a v2 manifest with basic metadata", () => {
  const preset = makePreset({
    roles: {
      pds: makeAdapter({
        name: "pds",
        capabilities: ["createSession", "admin"],
      }),
    },
  });

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/test-run",
    repoRoot: "/repo",
  });

  assertEquals(manifest.version, 2);
  assertEquals(manifest.name, "test-topology");
  assertEquals(manifest.description, "Test topology");
  assertEquals(manifest.runDir, "/tmp/test-run");
  assertEquals(manifest.repoRoot, "/repo");
});

Deno.test("createTopologyManifest: resolves service URLs for each role", () => {
  const preset = makePreset({
    roles: {
      pds: makeAdapter({
        name: "pds",
        ports: ["2599:2583"],
        capabilities: ["createSession"],
      }),
      relay: makeAdapter({
        name: "relay",
        ports: ["2598:2584"],
        capabilities: ["subscribeRepos"],
      }),
    },
  });

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/test-run",
    repoRoot: "/repo",
  });

  assertEquals(manifest.serviceUrls.pds, "http://localhost:2599");
  assertEquals(manifest.serviceUrls.relay, "http://localhost:2598");
  assertEquals(manifest.internalUrls.pds, "http://local-pds:2583");
  assertEquals(manifest.internalUrls.relay, "http://local-relay:2584");
});

Deno.test("createTopologyManifest: populates service names from adapters", () => {
  const preset = makePreset({
    roles: {
      pds: makeAdapter({
        name: "pds",
        serviceName: "custom-pds",
        capabilities: ["createSession"],
      }),
    },
  });

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/test-run",
    repoRoot: "/repo",
  });

  assertEquals(manifest.serviceNames.pds, "custom-pds");
});

Deno.test("createTopologyManifest: collects capabilities across all roles", () => {
  const preset = makePreset({
    roles: {
      pds: makeAdapter({
        name: "pds",
        capabilities: ["createSession", "admin"],
      }),
      relay: makeAdapter({
        name: "relay",
        capabilities: ["subscribeRepos"],
      }),
    },
  });

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/test-run",
    repoRoot: "/repo",
  });

  assert(manifest.capabilities.includes("createSession"));
  assert(manifest.capabilities.includes("admin"));
  assert(manifest.capabilities.includes("subscribeRepos"));
  assertEquals(manifest.capabilitiesByRole.pds, ["createSession", "admin"]);
  assertEquals(manifest.capabilitiesByRole.relay, ["subscribeRepos"]);
});

Deno.test("createTopologyManifest: generates health probes for HTTP health checks", () => {
  const preset = makePreset({
    roles: {
      pds: makeAdapter({
        name: "pds",
        healthCheck: { path: "/xrpc/_health", port: 2583 },
        capabilities: ["createSession"],
      }),
    },
  });

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/test-run",
    repoRoot: "/repo",
  });

  assertEquals(manifest.health.length, 1);
  assertEquals(manifest.health[0].role, "pds");
  assertEquals(manifest.health[0].mode, "http");
  assert(manifest.health[0].url?.includes("/xrpc/_health"));
});

Deno.test("createTopologyManifest: generates docker-health probes for customTest checks", () => {
  const preset = makePreset({
    roles: {
      pds: makeAdapter({
        name: "pds",
        healthCheck: { path: null, customTest: ["CMD", "echo", "ok"] },
        capabilities: ["createSession"],
      }),
    },
  });

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/test-run",
    repoRoot: "/repo",
  });

  assertEquals(manifest.health.length, 1);
  assertEquals(manifest.health[0].role, "pds");
  assertEquals(manifest.health[0].mode, "docker-health");
});

Deno.test("createTopologyManifest: populates urls.v2 with host and docker maps", () => {
  const preset = makePreset({
    roles: {
      pds: makeAdapter({
        name: "pds",
        ports: ["2599:2583"],
        capabilities: ["createSession"],
      }),
    },
  });

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/test-run",
    repoRoot: "/repo",
  });

  assertEquals(manifest.urls.host.pds, "http://localhost:2599");
  assertEquals(manifest.urls.docker.pds, "http://local-pds:2583");
});

Deno.test("createTopologyManifest: populates env with runner and scenario maps", () => {
  const preset = makePreset({
    roles: {
      pds: makeAdapter({
        name: "pds",
        ports: ["2599:2583"],
        capabilities: ["createSession"],
        scenarioEnv: { CUSTOM_VAR: "custom_value" },
      }),
    },
  });

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/test-run",
    repoRoot: "/repo",
  });

  assertEquals(manifest.env.hostRunner.PDS_URL, "http://localhost:2599");
  assertEquals(manifest.env.dockerRunner.PDS_URL, "http://local-pds:2583");
  assertEquals(manifest.env.scenario.CUSTOM_VAR, "custom_value");
});

Deno.test("createTopologyManifest: populates services summary with dependencies and secrets", () => {
  const preset = makePreset({
    roles: {
      pds: makeAdapter({
        name: "pds",
        capabilities: ["createSession"],
        dependsOn: ["database"],
        env: { DB_TOKEN: "secret123", DB_HOST: "localhost" },
      }),
    },
  });

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/test-run",
    repoRoot: "/repo",
  });

  const pdsService = manifest.services.pds;
  assertEquals(pdsService.role, "pds");
  assertEquals(pdsService.name, "pds");
  assertEquals(pdsService.capabilities, ["createSession"]);
  assertEquals(pdsService.dependencies.requested, ["database"]);
  assert(pdsService.secrets.includes("DB_TOKEN"));
  assert(!pdsService.secrets.includes("DB_HOST"));
});

Deno.test("createTopologyManifest: throws on unresolved inherited adapter", () => {
  const preset: TopologyPreset = {
    name: "test",
    description: "test",
    roles: {
      pds: { inherit: "base" } as unknown as ServiceAdapter,
    },
  };

  assertThrows(
    () =>
      createTopologyManifest(preset, {
        runDir: "/tmp/test-run",
        repoRoot: "/repo",
      }),
    Error,
    'Preset "test" still has unresolved inheritance',
  );
});

Deno.test("createTopologyManifest: uses custom composeFile when provided", () => {
  const preset = makePreset({
    roles: {
      pds: makeAdapter({
        name: "pds",
        capabilities: ["createSession"],
      }),
    },
  });

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/test-run",
    repoRoot: "/repo",
    composeFile: "/custom/compose.yml",
  });

  assertEquals(manifest.composeFile, "/custom/compose.yml");
});
