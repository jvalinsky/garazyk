import { assert, assertEquals } from "@std/assert";
import { join } from "@std/path";
import {
  computeRunDir,
  initRunDir,
  neededPorts,
  serviceUrl,
  serviceUrlFromManifest,
} from "./docker_config.ts";
import type {
  ClockSource,
  EnvSource,
  FileSystemOps,
  ProcessInfo,
} from "./docker_config.ts";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const basePorts = [2582, 2583, 2584, 3200, 8082, 2590, 8080, 8081];

/** Build a mock EnvSource from a plain record. */
function mockEnv(
  entries: Record<string, string>,
): EnvSource {
  return { get: (key: string) => entries[key] };
}

/** A mock EnvSource that returns undefined for everything. */
const emptyEnv: EnvSource = { get: () => undefined };

/** A mock file system that records mkdirSync calls. */
class MockFs implements FileSystemOps {
  dirs: string[] = [];
  mkdirSync(path: string, _opts?: { recursive?: boolean }): void {
    this.dirs.push(path);
  }
}

// ---------------------------------------------------------------------------
// neededPorts
// ---------------------------------------------------------------------------

Deno.test("neededPorts: returns the base set of ports when no options are given", () => {
  const ports = neededPorts({});
  assertEquals(ports.length, 8);
  for (const p of basePorts) {
    assert(ports.includes(p), `expected ${p} in ports`);
  }
});

Deno.test("neededPorts: adds pds2 port when withPds2 is enabled", () => {
  const ports = neededPorts({ withPds2: true });
  const expected = new Set([...basePorts, 2587]);
  assertEquals(new Set(ports), expected);
});

Deno.test("neededPorts: adds otel ports when otel is enabled", () => {
  const ports = neededPorts({ otel: true });
  const expected = new Set([...basePorts, 4317, 4318, 3301]);
  assertEquals(new Set(ports), expected);
});

Deno.test("neededPorts: includes both pds2 and otel ports when both flags are on", () => {
  const ports = neededPorts({ withPds2: true, otel: true });
  const expected = new Set([...basePorts, 2587, 4317, 4318, 3301]);
  assertEquals(new Set(ports), expected);
});

Deno.test("neededPorts: returns a new array each time", () => {
  const a = neededPorts({});
  const b = neededPorts({});
  assertEquals(a, b);
  a.push(9999);
  assertEquals(neededPorts({}).length, 8);
});

// ---------------------------------------------------------------------------
// serviceUrl (with DI EnvSource)
// ---------------------------------------------------------------------------

Deno.test("serviceUrl: uses the default port from SERVICE_PORTS", () => {
  assertEquals(serviceUrl("pds", emptyEnv), "http://127.0.0.1:2583");
  assertEquals(serviceUrl("germ", emptyEnv), "http://127.0.0.1:8082");
});

Deno.test("serviceUrl: falls back to port 0 for unknown services", () => {
  assertEquals(serviceUrl("unknown_service", emptyEnv), "http://127.0.0.1:0");
});

Deno.test("serviceUrl: honors the env-var override via EnvSource", () => {
  const env = mockEnv({ PDS_PORT: "9090" });
  assertEquals(serviceUrl("pds", env), "http://127.0.0.1:9090");
});

Deno.test("serviceUrl: URL env override wins over port env override", () => {
  const env = mockEnv({
    PDS_URL: "http://127.0.0.1:34567/",
    PDS_PORT: "9090",
  });
  assertEquals(serviceUrl("pds", env), "http://127.0.0.1:34567");
});

Deno.test("serviceUrl: constructs the URL with case-insensitive env lookup", () => {
  const env = mockEnv({ RELAY_PORT: "7777" });
  assertEquals(serviceUrl("relay", env), "http://127.0.0.1:7777");
});

Deno.test("serviceUrl: prefers env override over SERVICE_PORTS default", () => {
  const env = mockEnv({ PLC_PORT: "10000" });
  assertEquals(serviceUrl("plc", env), "http://127.0.0.1:10000");
});

Deno.test("serviceUrl: handles empty-string env value gracefully", () => {
  const env = mockEnv({ PDS_PORT: "" });
  assertEquals(serviceUrl("pds", env), "http://127.0.0.1:2583");
});

// ---------------------------------------------------------------------------
// computeRunDir (pure function, no side effects)
// ---------------------------------------------------------------------------

Deno.test("computeRunDir: returns default paths with no overrides", () => {
  const clock: ClockSource = { now: () => 0 };
  const proc: ProcessInfo = { pid: 12345 };
  const ctx = computeRunDir(undefined, { env: emptyEnv, proc, clock });
  assert(ctx.runId.includes("12345"), "runId should contain pid");
  assertEquals(ctx.baseDir, "/tmp/garazyk-atproto-e2e");
  assert(ctx.runDir.startsWith(ctx.baseDir));
  assert(ctx.diagnosticsDir.endsWith("/diagnostics"));
  assert(ctx.logDir.endsWith("/logs"));
  assert(ctx.pidFile.endsWith("/pids.txt"));
  assert(ctx.resourceManifestFile.endsWith("/resource-manifest.json"));
  assert(ctx.composeProject.startsWith("garazyk-e2e-"));
});

Deno.test("computeRunDir: uses requested run ID", () => {
  const ctx = computeRunDir("my-custom-run", { env: emptyEnv });
  assertEquals(ctx.runId, "my-custom-run");
  assert(ctx.runDir.includes("my-custom-run"));
});

Deno.test("computeRunDir: sanitizes the run ID", () => {
  const ctx = computeRunDir("Test Run!@#", { env: emptyEnv });
  assert(!ctx.runId.includes(" "), "spaces should be removed");
  assert(!ctx.runId.includes("@"), "special chars removed");
  assert(!ctx.runId.includes("#"), "special chars removed");
  assertEquals(ctx.runId, "test-run---");
});

Deno.test("computeRunDir: respects ATPROTO_E2E_BASE_DIR env override", () => {
  const env = mockEnv({ ATPROTO_E2E_BASE_DIR: "/custom/base" });
  const ctx = computeRunDir("test", { env });
  assertEquals(ctx.baseDir, "/custom/base");
  assert(ctx.runDir.startsWith("/custom/base"));
});

Deno.test("computeRunDir: respects ATPROTO_E2E_RUN_DIR env override", () => {
  const env = mockEnv({ ATPROTO_E2E_RUN_DIR: "/custom/run" });
  const ctx = computeRunDir("test", { env });
  assertEquals(ctx.runDir, "/custom/run");
});

Deno.test("computeRunDir: respects ATPROTO_E2E_DIAGNOSTICS_DIR env override", () => {
  const env = mockEnv({ ATPROTO_E2E_DIAGNOSTICS_DIR: "/custom/diag" });
  const ctx = computeRunDir("test", { env });
  assertEquals(ctx.diagnosticsDir, "/custom/diag");
});

Deno.test("computeRunDir: respects ATPROTO_E2E_LOG_DIR env override", () => {
  const env = mockEnv({ ATPROTO_E2E_LOG_DIR: "/custom/logs" });
  const ctx = computeRunDir("test", { env });
  assertEquals(ctx.logDir, "/custom/logs");
});

Deno.test("computeRunDir: respects ATPROTO_E2E_PID_FILE env override", () => {
  const env = mockEnv({ ATPROTO_E2E_PID_FILE: "/custom/pids.txt" });
  const ctx = computeRunDir("test", { env });
  assertEquals(ctx.pidFile, "/custom/pids.txt");
});

Deno.test("computeRunDir: respects ATPROTO_RESOURCE_MANIFEST env override", () => {
  const env = mockEnv({ ATPROTO_RESOURCE_MANIFEST: "/custom/resources.json" });
  const ctx = computeRunDir("test", { env });
  assertEquals(ctx.resourceManifestFile, "/custom/resources.json");
});

Deno.test("computeRunDir: respects ATPROTO_E2E_COMPOSE_PROJECT env override", () => {
  const env = mockEnv({ ATPROTO_E2E_COMPOSE_PROJECT: "my-project" });
  const ctx = computeRunDir("test", { env });
  assertEquals(ctx.composeProject, "my-project");
});

Deno.test("computeRunDir: sanitizes compose project name from run ID", () => {
  const ctx = computeRunDir("test.run_2025", { env: emptyEnv });
  assert(
    !ctx.composeProject.includes("."),
    "dots should be removed from compose project",
  );
  assert(
    !ctx.composeProject.includes("_"),
    "underscores should be removed from compose project",
  );
});

Deno.test("computeRunDir: uses deterministic clock for run ID", () => {
  const clock: ClockSource = { now: () => 1716566400000 }; // 2024-05-24T16:00:00.000Z
  const proc: ProcessInfo = { pid: 42 };
  const ctx = computeRunDir(undefined, { env: emptyEnv, proc, clock });
  assertEquals(ctx.runId, "2024-05-24t1600z-42");
});

// ---------------------------------------------------------------------------
// initRunDir (side-effectful, but testable with DI)
// ---------------------------------------------------------------------------

Deno.test("initRunDir: creates directories via injected fs", () => {
  const fs = new MockFs();
  const ctx = initRunDir("test-run", { fs, env: emptyEnv, mutateEnv: false });
  assertEquals(ctx.runId, "test-run");
  assert(fs.dirs.includes(ctx.runDir));
  assert(fs.dirs.includes(ctx.diagnosticsDir));
  assert(fs.dirs.includes(ctx.logDir));
});

Deno.test("initRunDir: creates directories with recursive flag", () => {
  const dirs: Array<{ path: string; opts: { recursive?: boolean } }> = [];
  const fs: FileSystemOps = {
    mkdirSync(path, opts) {
      dirs.push({ path, opts: opts ?? {} });
    },
  };
  initRunDir("recurse-test", { fs, env: emptyEnv, mutateEnv: false });
  assertEquals(dirs.length, 3);
  for (const d of dirs) {
    assertEquals(d.opts.recursive, true);
  }
});

Deno.test("initRunDir: returns same context shape as computeRunDir", () => {
  const fs = new MockFs();
  const ctx = initRunDir("shape-test", { fs, env: emptyEnv, mutateEnv: false });
  assert(typeof ctx.runId === "string");
  assert(typeof ctx.runDir === "string");
  assert(typeof ctx.diagnosticsDir === "string");
  assert(typeof ctx.logDir === "string");
  assert(typeof ctx.pidFile === "string");
  assert(typeof ctx.resourceManifestFile === "string");
  assert(typeof ctx.composeProject === "string");
  assert(typeof ctx.baseDir === "string");
});

// ---------------------------------------------------------------------------
// serviceUrlFromManifest (filesystem-aware)
// ---------------------------------------------------------------------------

Deno.test("serviceUrlFromManifest: returns undefined when no manifest env is set", () => {
  const result = serviceUrlFromManifest("pds", emptyEnv);
  assertEquals(result, undefined);
});

Deno.test("serviceUrlFromManifest: returns undefined when manifest file does not exist", async () => {
  const dir = await Deno.makeTempDir({ prefix: "service-url-manifest-test-" });
  const manifestPath = join(dir, "nonexistent.json");
  const env = mockEnv({ ATPROTO_RESOURCE_MANIFEST: manifestPath });
  const result = serviceUrlFromManifest("pds", env);
  assertEquals(result, undefined);
  await Deno.remove(dir, { recursive: true });
});

Deno.test("serviceUrlFromManifest: returns hostUrl from services in manifest", async () => {
  const dir = await Deno.makeTempDir({ prefix: "service-url-manifest-test-" });
  const manifestPath = join(dir, "manifest.json");
  const manifest = {
    services: {
      pds: { hostUrl: "http://127.0.0.1:35000" },
      plc: { hostUrl: "http://127.0.0.1:35001" },
    },
  };
  await Deno.writeTextFile(manifestPath, JSON.stringify(manifest));
  const env = mockEnv({ ATPROTO_RESOURCE_MANIFEST: manifestPath });
  assertEquals(serviceUrlFromManifest("pds", env), "http://127.0.0.1:35000");
  assertEquals(serviceUrlFromManifest("plc", env), "http://127.0.0.1:35001");
  assertEquals(serviceUrlFromManifest("relay", env), undefined);
  await Deno.remove(dir, { recursive: true });
});

Deno.test("serviceUrlFromManifest: returns hostUrl from mockProviders in manifest", async () => {
  const dir = await Deno.makeTempDir({ prefix: "service-url-manifest-test-" });
  const manifestPath = join(dir, "manifest.json");
  const manifest = {
    mockProviders: {
      twilio: { hostUrl: "http://127.0.0.1:38000" },
    },
  };
  await Deno.writeTextFile(manifestPath, JSON.stringify(manifest));
  const env = mockEnv({ ATPROTO_RESOURCE_MANIFEST: manifestPath });
  assertEquals(serviceUrlFromManifest("twilio", env), "http://127.0.0.1:38000");
  await Deno.remove(dir, { recursive: true });
});

Deno.test("serviceUrl: prefers manifest URL over SERVICE_PORTS default", async () => {
  const dir = await Deno.makeTempDir({ prefix: "service-url-manifest-test-" });
  const manifestPath = join(dir, "manifest.json");
  const manifest = {
    services: {
      pds: { hostUrl: "http://127.0.0.1:35000" },
    },
  };
  await Deno.writeTextFile(manifestPath, JSON.stringify(manifest));
  // Set the env var so serviceUrl() can find the manifest
  const originalValue = Deno.env.get("ATPROTO_RESOURCE_MANIFEST");
  Deno.env.set("ATPROTO_RESOURCE_MANIFEST", manifestPath);
  try {
    assertEquals(serviceUrl("pds"), "http://127.0.0.1:35000");
    // Other services without manifest entries still fall back to SERVICE_PORTS
    assertEquals(serviceUrl("relay"), "http://127.0.0.1:2584");
  } finally {
    if (originalValue !== undefined) {
      Deno.env.set("ATPROTO_RESOURCE_MANIFEST", originalValue);
    } else {
      Deno.env.delete("ATPROTO_RESOURCE_MANIFEST");
    }
    await Deno.remove(dir, { recursive: true });
  }
});

// ---------------------------------------------------------------------------
// neededPorts (manifest-aware)
// ---------------------------------------------------------------------------

Deno.test("neededPorts: returns manifest ports when a manifest is available", async () => {
  const dir = await Deno.makeTempDir({ prefix: "needed-ports-manifest-test-" });
  const manifestPath = join(dir, "manifest.json");
  const manifest = {
    services: {
      pds: { hostPort: 35000 },
      plc: { hostPort: 35001 },
      relay: { hostPort: 35002 },
    },
    mockProviders: {
      twilio: { hostPort: 38000 },
    },
    portLeases: [
      { port: 35000 },
      { port: 35001 },
      { port: 35002 },
      { port: 38000 },
    ],
  };
  await Deno.writeTextFile(manifestPath, JSON.stringify(manifest));
  const originalValue = Deno.env.get("ATPROTO_RESOURCE_MANIFEST");
  Deno.env.set("ATPROTO_RESOURCE_MANIFEST", manifestPath);
  try {
    const ports = neededPorts({});
    assert(ports.includes(35000), "expected pds port 35000");
    assert(ports.includes(35001), "expected plc port 35001");
    assert(ports.includes(35002), "expected relay port 35002");
    assert(ports.includes(38000), "expected twilio port 38000");
    // Should NOT include the fixed default ports
    assert(!ports.includes(2583), "should not include fixed pds port 2583");
  } finally {
    if (originalValue !== undefined) {
      Deno.env.set("ATPROTO_RESOURCE_MANIFEST", originalValue);
    } else {
      Deno.env.delete("ATPROTO_RESOURCE_MANIFEST");
    }
    await Deno.remove(dir, { recursive: true });
  }
});

Deno.test("neededPorts: adds otel ports even with manifest", async () => {
  const dir = await Deno.makeTempDir({ prefix: "needed-ports-manifest-test-" });
  const manifestPath = join(dir, "manifest.json");
  const manifest = {
    services: { pds: { hostPort: 35000 } },
    portLeases: [{ port: 35000 }],
  };
  await Deno.writeTextFile(manifestPath, JSON.stringify(manifest));
  const originalValue = Deno.env.get("ATPROTO_RESOURCE_MANIFEST");
  Deno.env.set("ATPROTO_RESOURCE_MANIFEST", manifestPath);
  try {
    const ports = neededPorts({ otel: true });
    assert(ports.includes(4317), "expected otel port 4317");
    assert(ports.includes(4318), "expected otel port 4318");
    assert(ports.includes(3301), "expected otel port 3301");
  } finally {
    if (originalValue !== undefined) {
      Deno.env.set("ATPROTO_RESOURCE_MANIFEST", originalValue);
    } else {
      Deno.env.delete("ATPROTO_RESOURCE_MANIFEST");
    }
    await Deno.remove(dir, { recursive: true });
  }
});
