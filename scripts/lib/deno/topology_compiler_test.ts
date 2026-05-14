import { assertEquals } from "@std/assert";
import { validatePreset, renderComposeYaml, compileTopology } from "./topology_compiler.ts";
import { TopologyPreset, ServiceAdapter } from "./topology.ts";

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
