import { assert, assertEquals } from "@std/assert";
import {
  computeRunDir,
  initRunDir,
  neededPorts,
  serviceUrl,
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

const basePorts = [2582, 2583, 2584, 3200, 8080, 8081];

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
  assertEquals(ports.length, 6);
  for (const p of basePorts) assert(ports.includes(p), `expected ${p} in ports`);
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
  assertEquals(neededPorts({}).length, 6);
});

// ---------------------------------------------------------------------------
// serviceUrl (with DI EnvSource)
// ---------------------------------------------------------------------------

Deno.test("serviceUrl: uses the default port from SERVICE_PORTS", () => {
  assertEquals(serviceUrl("pds", emptyEnv), "http://127.0.0.1:2583");
});

Deno.test("serviceUrl: falls back to port 0 for unknown services", () => {
  assertEquals(serviceUrl("unknown_service", emptyEnv), "http://127.0.0.1:0");
});

Deno.test("serviceUrl: honors the env-var override via EnvSource", () => {
  const env = mockEnv({ PDS_PORT: "9090" });
  assertEquals(serviceUrl("pds", env), "http://127.0.0.1:9090");
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

Deno.test("computeRunDir: respects ATPROTO_E2E_COMPOSE_PROJECT env override", () => {
  const env = mockEnv({ ATPROTO_E2E_COMPOSE_PROJECT: "my-project" });
  const ctx = computeRunDir("test", { env });
  assertEquals(ctx.composeProject, "my-project");
});

Deno.test("computeRunDir: sanitizes compose project name from run ID", () => {
  const ctx = computeRunDir("test.run_2025", { env: emptyEnv });
  assert(!ctx.composeProject.includes("."), "dots should be removed from compose project");
  assert(!ctx.composeProject.includes("_"), "underscores should be removed from compose project");
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
  assert(typeof ctx.composeProject === "string");
  assert(typeof ctx.baseDir === "string");
});
