import { assertEquals, assertThrows } from "@std/assert";
import { compileTopology, renderComposeYaml, validatePreset } from "./topology_compiler.ts";
import {
  createTopologyManifest,
  loadTopologyManifest,
  resolveTopology,
  ServiceAdapter,
  Topology,
  TopologyPreset,
} from "./topology.ts";
import { normalizeTopologyPreset, parseRawTopologyPresetV1 } from "./topology_schema.ts";
import { ScenarioInfo, selectScenarios } from "../../run_scenarios.ts";

const VALID_ADAPTER: ServiceAdapter = {
  name: "test-pds",
  healthCheck: { path: "/xrpc/com.atproto.server.describeServer" },
  capabilities: ["describeServer", "createAccount"],
  ports: ["2583:2583"],
};

const VALID_PRESET: TopologyPreset = {
  name: "test-preset",
  description: "A test topology preset",
  roles: {
    pds: VALID_ADAPTER,
  },
};

Deno.test("validatePreset: valid preset returns no errors", () => {
  const errors = validatePreset(VALID_PRESET);
  assertEquals(errors.length, 0);
});

Deno.test("validatePreset: missing name", () => {
  const preset = { ...VALID_PRESET, name: "" };
  const errors = validatePreset(preset);
  assertEquals(errors.length, 1);
  assertEquals(errors[0], "Missing preset name");
});

Deno.test("validatePreset: no roles", () => {
  const preset = { ...VALID_PRESET, roles: {} };
  const errors = validatePreset(preset);
  assertEquals(errors.length, 1);
  assertEquals(errors[0], "No roles defined");
});

Deno.test("validatePreset: adapter missing name", () => {
  const preset = { ...VALID_PRESET, roles: { pds: { ...VALID_ADAPTER, name: "" } } };
  const errors = validatePreset(preset);
  assertEquals(errors.length, 1);
  assertEquals(errors[0], 'Role "pds": missing adapter name');
});

Deno.test("validatePreset: adapter missing healthCheck", () => {
  const adapter = { ...VALID_ADAPTER, healthCheck: undefined as any };
  const preset = { ...VALID_PRESET, roles: { pds: adapter } };
  const errors = validatePreset(preset);
  assertEquals(errors.length, 1);
});

Deno.test("validatePreset: adapter no capabilities", () => {
  const adapter = { ...VALID_ADAPTER, capabilities: [] };
  const preset = { ...VALID_PRESET, roles: { pds: adapter } };
  const errors = validatePreset(preset);
  assertEquals(errors.length, 1);
  assertEquals(errors[0], 'Role "pds": no capabilities declared');
});

Deno.test("validatePreset: duplicate host ports", () => {
  const preset = {
    ...VALID_PRESET,
    roles: {
      pds: { ...VALID_ADAPTER, ports: ["2583:2583"] },
      pds2: { ...VALID_ADAPTER, name: "test-pds2", ports: ["2583:2587"] },
    },
  };
  const errors = validatePreset(preset);
  assertEquals(errors.length, 1);
  assertEquals(errors[0], 'Duplicate host port: 2583 (used by role "pds2" and another)');
});

Deno.test("renderComposeYaml: produces valid YAML structure", () => {
  const yaml = renderComposeYaml(VALID_PRESET, {
    preset: "test",
    runDir: "/tmp",
    repoRoot: "/repo",
    composeProject: "test",
  });

  assertEquals(yaml.includes("services:"), true);
  assertEquals(yaml.includes("local-pds:"), true);
  assertEquals(yaml.includes("healthcheck:"), true);
  assertEquals(yaml.includes("topology_net:"), true);
});

Deno.test("renderComposeYaml: image-based adapter", () => {
  const imageAdapter: ServiceAdapter = {
    name: "reference-pds",
    image: "ghcr.io/bluesky-social/atproto/pds:latest",
    healthCheck: { path: "/xrpc/com.atproto.server.describeServer" },
    capabilities: ["describeServer"],
  };
  const preset = { ...VALID_PRESET, roles: { pds: imageAdapter } };

  const yaml = renderComposeYaml(preset, {
    preset: "test",
    runDir: "/tmp",
    repoRoot: "/repo",
    composeProject: "test",
  });

  assertEquals(yaml.includes("image: ghcr.io/bluesky-social/atproto/pds:latest"), true);
  assertEquals(yaml.includes("build:"), false);
});

Deno.test("renderComposeYaml: includes depends_on", () => {
  const adapter = { ...VALID_ADAPTER, dependsOn: ["local-plc"] };
  const preset = { ...VALID_PRESET, roles: { pds: adapter } };

  const yaml = renderComposeYaml(preset, {
    preset: "test",
    runDir: "/tmp",
    repoRoot: "/repo",
    composeProject: "test",
  });

  assertEquals(yaml.includes("depends_on:"), true);
  assertEquals(yaml.includes("local-plc:"), true);
  assertEquals(yaml.includes("condition: service_healthy"), true);
});

Deno.test("renderComposeYaml: health check with auth headers", () => {
  const adapter: ServiceAdapter = {
    name: "test-appview",
    healthCheck: {
      path: "/admin/backfill/status",
      headers: { Authorization: "Bearer localdevadmin" },
    },
    capabilities: ["backfill"],
  };
  const preset = { ...VALID_PRESET, roles: { appview: adapter } };

  const yaml = renderComposeYaml(preset, {
    preset: "test",
    runDir: "/tmp",
    repoRoot: "/repo",
    composeProject: "test",
  });

  assertEquals(yaml.includes("Authorization: Bearer localdevadmin"), true);
});

Deno.test("compileTopology: writes compose file and returns URLs", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const result = await compileTopology({
      preset: VALID_PRESET,
      runDir,
      repoRoot: "/repo",
      composeProject: "test",
    });

    assertEquals(result.composeFile, `${runDir}/docker-compose.topology.yml`);
    assertEquals(result.serviceUrls.pds, "http://localhost:2583");
    assertEquals(result.internalUrls.pds, "http://local-pds:2583");
    assertEquals(result.capabilities.has("describeServer"), true);
    assertEquals(result.capabilities.has("createAccount"), true);

    // Verify the file was written
    const stat = await Deno.stat(result.composeFile);
    assertEquals(stat.isFile, true);
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("compileTopology: invalid preset throws", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const badPreset = { ...VALID_PRESET, name: "" };
    let threw = false;
    try {
      await compileTopology({
        preset: badPreset,
        runDir,
        repoRoot: "/repo",
        composeProject: "test",
      });
    } catch (e) {
      threw = true;
      assertEquals(e instanceof Error, true);
      assertEquals((e as Error).message.includes("Invalid topology preset"), true);
    }
    assertEquals(threw, true);
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("renderComposeYaml: sidecars rendered as separate services", () => {
  const adapterWithSidecar: ServiceAdapter = {
    name: "reference-plc",
    image: "ghcr.io/did-method-plc/did-method-plc:latest",
    healthCheck: { path: "/_health" },
    capabilities: ["didResolution"],
    ports: ["2582:3000"],
    dependsOn: ["local-plc-db"],
    sidecars: {
      "local-plc-db": {
        image: "postgres:16-alpine",
        env: { POSTGRES_USER: "plc", POSTGRES_PASSWORD: "plc", POSTGRES_DB: "plc" },
        volumes: ["ref_plc_pg_data:/var/lib/postgresql/data"],
        healthCheck: { path: null, customTest: ["CMD-SHELL", "pg_isready -U plc"] },
      },
    },
  };
  const preset = { ...VALID_PRESET, roles: { plc: adapterWithSidecar } };

  const yaml = renderComposeYaml(preset, {
    preset: "test",
    runDir: "/tmp",
    repoRoot: "/repo",
    composeProject: "test",
  });

  assertEquals(yaml.includes("local-plc:"), true);
  assertEquals(yaml.includes("local-plc-db:"), true);
  assertEquals(yaml.includes("image: postgres:16-alpine"), true);
  assertEquals(yaml.includes("pg_isready -U plc"), true);
  assertEquals(yaml.includes("ref_plc_pg_data"), true);
});

Deno.test("renderComposeYaml: customTest health check", () => {
  const adapter: ServiceAdapter = {
    name: "test-db",
    image: "postgres:16-alpine",
    healthCheck: { path: null, customTest: ["CMD-SHELL", "pg_isready"] },
    capabilities: ["database"],
  };
  const preset = { ...VALID_PRESET, roles: { plc: adapter } };

  const yaml = renderComposeYaml(preset, {
    preset: "test",
    runDir: "/tmp",
    repoRoot: "/repo",
    composeProject: "test",
  });

  assertEquals(yaml.includes("pg_isready"), true);
  assertEquals(yaml.includes("curl"), false);
});

Deno.test("compileTopology: reference-plc preset loads and compiles", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const result = await compileTopology({
      preset: "reference-plc",
      runDir,
      repoRoot: "/Users/jack/Software/garazyk",
      composeProject: "test",
    });

    assertEquals(result.capabilities.has("didResolution"), true);
    assertEquals(result.capabilities.has("createAccount"), true);
    assertEquals(result.serviceUrls.plc, "http://localhost:2582");

    // Verify the file was written
    const content = await Deno.readTextFile(result.composeFile);
    assertEquals(content.includes("local-plc:"), true);
    assertEquals(content.includes("local-plc-db:"), true);
    assertEquals(content.includes("postgres:16-alpine"), true);
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("compileTopology: allegedly-plc preset loads and compiles", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const result = await compileTopology({
      preset: "allegedly-plc",
      runDir,
      repoRoot: "/Users/jack/Software/garazyk",
      composeProject: "test",
    });

    assertEquals(result.capabilities.has("didResolution"), true);
    assertEquals(result.capabilities.has("createAccount"), true);
    assertEquals(result.serviceUrls.plc, "http://localhost:2582");

    // Verify the file was written
    const content = await Deno.readTextFile(result.composeFile);
    assertEquals(content.includes("local-plc:"), true);
    assertEquals(content.includes("allegedly"), true);
    assertEquals(content.includes("local-ref-plc:"), true);
    assertEquals(content.includes("local-plc-db:"), true);
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("compileTopology: appviewlite preset loads and compiles", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const result = await compileTopology({
      preset: "appviewlite",
      runDir,
      repoRoot: "/Users/jack/Software/garazyk",
      composeProject: "test",
    });

    assertEquals(result.capabilities.has("getTimeline"), true);
    assertEquals(result.capabilities.has("multiProtocol"), true);
    assertEquals(result.serviceUrls.appview, "http://localhost:3200");

    const content = await Deno.readTextFile(result.composeFile);
    assertEquals(content.includes("local-appview:"), true);
    assertEquals(content.includes("appviewlite"), true);
    assertEquals(content.includes("APPVIEWLITE_PLC_DIRECTORY"), true);
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("compileTopology: happyview preset loads and compiles", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const result = await compileTopology({
      preset: "happyview",
      runDir,
      repoRoot: "/Users/jack/Software/garazyk",
      composeProject: "test",
    });

    assertEquals(result.capabilities.has("lexiconDriven"), true);
    assertEquals(result.capabilities.has("luaScripting"), true);
    assertEquals(result.serviceUrls.appview, "http://localhost:3200");

    const content = await Deno.readTextFile(result.composeFile);
    assertEquals(content.includes("local-appview:"), true);
    assertEquals(content.includes("happyview"), true);
    assertEquals(content.includes("RELAY_URL"), true);
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("compileTopology: parakeet preset loads and compiles", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const result = await compileTopology({
      preset: "parakeet",
      runDir,
      repoRoot: "/Users/jack/Software/garazyk",
      composeProject: "test",
    });

    assertEquals(result.capabilities.has("getTimeline"), true);
    assertEquals(result.capabilities.has("getProfile"), true);
    assertEquals(result.serviceUrls.appview, "http://localhost:3200");

    const content = await Deno.readTextFile(result.composeFile);
    assertEquals(content.includes("local-appview:"), true);
    assertEquals(content.includes("parakeet"), true);
    // Sidecars
    assertEquals(content.includes("local-parakeet-consumer:"), true);
    assertEquals(content.includes("local-parakeet-index:"), true);
    assertEquals(content.includes("local-parakeet-db:"), true);
    assertEquals(content.includes("local-parakeet-redis:"), true);
    assertEquals(content.includes("postgres:16-alpine"), true);
    assertEquals(content.includes("redis:7-alpine"), true);
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("renderComposeYaml: source build renders build.context and dockerfile", () => {
  const preset: TopologyPreset = {
    name: "source-test",
    description: "Test source build rendering",
    roles: {
      pds: {
        name: "test-pds",
        source: {
          repo: "https://github.com/example/pds.git",
          ref: "v1.0.0",
          dockerDir: "packages/pds",
          dockerfile: "Dockerfile.prod",
          buildArgs: { VERSION: "1.0.0" },
        },
        healthCheck: { path: "/health" },
        capabilities: ["describeServer"],
        ports: ["2583:2583"],
      },
    },
  };

  const yaml = renderComposeYaml(preset, {
    preset: "source-test",
    runDir: "/tmp/topology-test",
    repoRoot: "/repo",
    composeProject: "test",
  });

  assertEquals(yaml.includes("build:"), true);
  assertEquals(yaml.includes("context: /tmp/topology-test/sources/test-pds/packages/pds"), true);
  assertEquals(yaml.includes("dockerfile: Dockerfile.prod"), true);
  assertEquals(yaml.includes("args:"), true);
  assertEquals(yaml.includes("VERSION:"), true);
  // Should NOT have image: line
  assertEquals(yaml.includes("image:"), false);
});

Deno.test("compileTopology: source build collects sources in result", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const result = await compileTopology({
      preset: "reference-pds",
      runDir,
      repoRoot: "/Users/jack/Software/garazyk",
      composeProject: "test",
    });

    // reference-pds uses source build
    assertEquals(result.sources.length >= 1, true);
    const pdsSource = result.sources.find((s) => s.name === "reference-pds");
    assertEquals(pdsSource !== undefined, true);
    assertEquals(pdsSource!.repo, "https://github.com/bluesky-social/pds.git");
    assertEquals(pdsSource!.ref, "v0.4.219");
    assertEquals(pdsSource!.cloneDir.includes("sources/reference-pds"), true);

    // Compose YAML should have build.context, not image
    const content = await Deno.readTextFile(result.composeFile);
    assertEquals(content.includes("build:"), true);
    assertEquals(content.includes("context:"), true);
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("compileTopology: happyview source build with buildArgs", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const result = await compileTopology({
      preset: "happyview",
      runDir,
      repoRoot: "/Users/jack/Software/garazyk",
      composeProject: "test",
    });

    const hvSource = result.sources.find((s) => s.name === "happyview");
    assertEquals(hvSource !== undefined, true);
    assertEquals(hvSource!.repo, "https://github.com/gamesgamesgamesgamesgames/happyview.git");
    assertEquals(hvSource!.ref, "v2.7.0");
    assertEquals(hvSource!.buildArgs["HAPPYVIEW_VERSION"], "2.7.0");

    const content = await Deno.readTextFile(result.composeFile);
    assertEquals(content.includes("HAPPYVIEW_VERSION"), true);
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("compileTopology: zlay-relay does not inherit Garazyk relay command or clear entrypoint", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const result = await compileTopology({
      preset: "zlay-relay",
      runDir,
      repoRoot: "/Users/jack/Software/garazyk",
      composeProject: "test",
    });

    const content = await Deno.readTextFile(result.composeFile);
    assertEquals(content.includes("entrypoint: []"), false);
    assertEquals(
      content.includes(
        'command: ["serve","--upstream","ws://local-pds:2583/xrpc/com.atproto.sync.subscribeRepos"',
      ),
      false,
    );
    assertEquals(
      result.manifest.health.some((probe) =>
        probe.role === "relay" && probe.mode === "docker-health"
      ),
      true,
    );
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("resolveTopology: inherited capabilities are visible by role", () => {
  const topology = resolveTopology(undefined, "zlay-relay");
  assertEquals(topology.capabilities.has("didResolution"), true);
  assertEquals(topology.capabilitiesByRole.plc.has("didResolution"), true);
  assertEquals(topology.capabilitiesByRole.pds.has("createAccount"), true);
  assertEquals(topology.capabilitiesByRole.relay.has("subscribeRepos"), true);
});

Deno.test("createTopologyManifest: public and internal URLs use host and container ports", () => {
  const preset: TopologyPreset = {
    name: "port-test",
    description: "Port mapping test",
    roles: {
      appview: {
        name: "happyview",
        image: "example/happyview:latest",
        ports: ["3200:3000"],
        healthCheck: { path: "/" },
        capabilities: ["getTimeline"],
      },
    },
  };

  const manifest = createTopologyManifest(preset, {
    runDir: "/tmp/port-test",
    repoRoot: "/repo",
  });

  assertEquals(manifest.serviceUrls.appview, "http://localhost:3200");
  assertEquals(manifest.internalUrls.appview, "http://local-appview:3000");
  assertEquals(manifest.diagnostics[0].url, "http://localhost:3200/");
});

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
      requires: ["plc:didResolution"],
      optional: [],
    },
    {
      id: "09",
      name: "missing appview",
      path: "/tmp/09.ts",
      needsPds2: false,
      browserFlows: [],
      requires: ["relay:subscribeRepos", "appview:backfill"],
      optional: [],
    },
  ];

  const selected = selectScenarios(scenarios, {
    scenarioIds: [],
    clientFlow: "none",
    pds2: false,
  }, topology);

  assertEquals(selected.map((scenario) => scenario.id), ["01"]);
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
      requires: ["plc:didResolution"],
      optional: ["appview:backfill"],
    },
  ];

  const selected = selectScenarios(scenarios, {
    scenarioIds: [],
    clientFlow: "none",
    pds2: false,
  }, topology);

  assertEquals(selected.map((scenario) => scenario.id), ["01"]);
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
      requires: ["plc:didResolution"],
      optional: [],
    },
  ];

  const defaultSelected = selectScenarios(scenarios, {
    scenarioIds: [],
    clientFlow: "none",
    pds2: false,
  }, topology);
  assertEquals(defaultSelected.map((scenario) => scenario.id), []);

  const explicitSelected = selectScenarios(scenarios, {
    scenarioIds: ["35"],
    clientFlow: "none",
    pds2: false,
  }, topology);
  assertEquals(explicitSelected.map((scenario) => scenario.id), ["35"]);
  assertEquals(explicitSelected.some((scenario) => scenario.needsPds2), true);
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
      requires: ["relay:subscribeRepos", "appview:backfill"],
      optional: [],
    },
  ];

  const selected = selectScenarios(scenarios, {
    scenarioIds: ["09"],
    clientFlow: "none",
    pds2: false,
  }, topology);

  assertEquals(selected.map((scenario) => scenario.id), ["09"]);
});

Deno.test("compileTopology: every topology preset resolves, renders, and writes manifest", async () => {
  for await (const entry of Deno.readDir("scripts/scenarios/topologies")) {
    if (!entry.isFile || !entry.name.endsWith(".json")) continue;
    const preset = entry.name.replace(/\.json$/, "");
    const runDir = await Deno.makeTempDir({ prefix: `topology-${preset}-` });
    try {
      const result = await compileTopology({
        preset,
        runDir,
        repoRoot: "/Users/jack/Software/garazyk",
        composeProject: "test",
      });
      assertEquals((await Deno.stat(result.composeFile)).isFile, true);
      assertEquals((await Deno.stat(result.manifestFile)).isFile, true);
      assertEquals(result.manifest.name, preset);
    } finally {
      await Deno.remove(runDir, { recursive: true });
    }
  }
});

Deno.test("schema: unknown roles require x- namespace and metadata", () => {
  const raw = parseRawTopologyPresetV1({
    name: "bad-role",
    description: "Reject unknown role",
    roles: {
      search: {
        name: "search",
        healthCheck: { path: "/health" },
        capabilities: ["query"],
      },
    },
  }, "inline");

  assertThrows(
    () => normalizeTopologyPreset(raw),
    Error,
    'unknown role "search"',
  );
});

Deno.test("schema: experimental roles require env/default port/runner exposure metadata", () => {
  const raw = parseRawTopologyPresetV1({
    name: "experimental-role",
    description: "Reject incomplete experimental role",
    roles: {
      "x-search": {
        name: "search",
        healthCheck: { path: "/health" },
        capabilities: ["x-search:query"],
      },
    },
  }, "inline");

  assertThrows(
    () => normalizeTopologyPreset(raw),
    Error,
    'experimental role "x-search" must declare envVar',
  );
});

Deno.test("schema: unknown role capabilities fail unless experimental namespace", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const preset: TopologyPreset = {
      name: "bad-capability",
      description: "Reject unregistered capability",
      roles: {
        relay: {
          name: "relay",
          healthCheck: { path: "/health" },
          capabilities: ["totallyNewThing"],
        },
      },
    };
    await assertThrowsAsync(
      () =>
        compileTopology({
          preset,
          runDir,
          repoRoot: "/repo",
          composeProject: "test",
        }),
      Error,
      'Capability "totallyNewThing" is not registered for role "relay"',
    );
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("compileTopology: manifest v2 separates host and docker runner env", async () => {
  const runDir = await Deno.makeTempDir({ prefix: "topology-test-" });
  try {
    const result = await compileTopology({
      preset: "hydrant",
      runDir,
      repoRoot: "/Users/jack/Software/garazyk",
      composeProject: "test",
    });

    assertEquals(result.manifest.version, 2);
    assertEquals(result.manifest.env?.hostRunner.BACKFILL_URL, "http://localhost:3000");
    assertEquals(result.manifest.env?.dockerRunner.BACKFILL_URL, "http://local-backfill:3000");
    assertEquals(result.manifest.urls?.host.backfill, "http://localhost:3000");
    assertEquals(result.manifest.urls?.docker.backfill, "http://local-backfill:3000");
  } finally {
    await Deno.remove(runDir, { recursive: true });
  }
});

Deno.test("loadTopologyManifest: malformed explicit manifest throws", async () => {
  const manifestFile = await Deno.makeTempFile({
    prefix: "bad-topology-manifest-",
    suffix: ".json",
  });
  try {
    await Deno.writeTextFile(manifestFile, "{ not json");
    assertThrows(
      () => loadTopologyManifest(manifestFile),
      Error,
      "Unable to load topology manifest",
    );
  } finally {
    await Deno.remove(manifestFile);
  }
});

async function assertThrowsAsync(
  fn: () => Promise<unknown>,
  ErrorClass: new (...args: any[]) => Error,
  msgIncludes: string,
) {
  let thrown: unknown;
  try {
    await fn();
  } catch (exc) {
    thrown = exc;
  }
  assertEquals(thrown instanceof ErrorClass, true);
  assertEquals(String((thrown as Error).message).includes(msgIncludes), true);
}
