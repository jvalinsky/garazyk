import { assertEquals } from "jsr:@std/assert";
import { createProcessLifecycle } from "./process_lifecycle.ts";
import type { NetworkSession } from "./docker_types.ts";

function makeSession(overrides: Partial<NetworkSession> = {}): NetworkSession {
  return {
    runId: "test-run",
    runDir: "/tmp/test-run",
    diagnosticsDir: "/tmp/test-run/diagnostics",
    composeProject: "garazyk-e2e-test-run",
    composeFiles: ["/repo/docker/local-network/docker-compose.yml"],
    withPds2: false,
    useBinary: false,
    ...overrides,
  };
}

Deno.test("process lifecycle tears down registered session after fatal setup failure", async () => {
  const stopped: Array<NetworkSession & { collectDiagnostics?: boolean }> = [];
  let diagnostics = 0;
  const lifecycle = createProcessLifecycle({
    args: { binary: false, keepRunning: false, teardown: false, noSetup: false },
    context: { runId: "test-run", diagnosticsDir: "/tmp/test-run/diagnostics" },
    stopLocalNetwork: async (options) => {
      stopped.push(options);
    },
  });

  lifecycle.registerNetworkSession(makeSession());
  await lifecycle.finalizeRun({
    results: [],
    fatalError: new Error("health failed"),
    collectDiagnostics: async () => {
      diagnostics++;
    },
  });

  assertEquals(diagnostics, 1);
  assertEquals(stopped.length, 1);
  assertEquals(stopped[0].composeProject, "garazyk-e2e-test-run");
});

Deno.test("process lifecycle collects diagnostics and tears down after scenario failure", async () => {
  const stopped: Array<NetworkSession & { collectDiagnostics?: boolean }> = [];
  let diagnostics = 0;
  const lifecycle = createProcessLifecycle({
    args: { binary: false, keepRunning: false, teardown: false, noSetup: false },
    context: { runId: "test-run", diagnosticsDir: "/tmp/test-run/diagnostics" },
    stopLocalNetwork: async (options) => {
      stopped.push(options);
    },
  });

  lifecycle.markNetworkStarted(makeSession({ withPds2: true }));
  await lifecycle.finalizeRun({
    results: [{ result: { failed: 1 } }],
    fatalError: null,
    collectDiagnostics: async () => {
      diagnostics++;
    },
  });

  assertEquals(diagnostics, 1);
  assertEquals(stopped.length, 1);
  assertEquals(stopped[0].withPds2, true);
});

Deno.test("process lifecycle keep-running skips teardown", async () => {
  let stopped = 0;
  const lifecycle = createProcessLifecycle({
    args: { binary: false, keepRunning: true, teardown: true, noSetup: false },
    context: { runId: "test-run", diagnosticsDir: "/tmp/test-run/diagnostics" },
    stopLocalNetwork: async () => {
      stopped++;
    },
  });

  lifecycle.registerNetworkSession(makeSession());
  await lifecycle.stopIfNeeded(true);

  assertEquals(stopped, 0);
});

Deno.test("process lifecycle no-setup without session never tears down", async () => {
  let stopped = 0;
  const lifecycle = createProcessLifecycle({
    args: { binary: false, keepRunning: false, teardown: false, noSetup: true },
    context: { runId: "test-run", diagnosticsDir: "/tmp/test-run/diagnostics" },
    stopLocalNetwork: async () => {
      stopped++;
    },
  });

  await lifecycle.finalizeRun({
    results: [],
    fatalError: null,
    collectDiagnostics: async () => {},
  });

  assertEquals(stopped, 0);
});
