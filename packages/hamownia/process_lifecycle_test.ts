/**
 * Tests for createProcessLifecycle — dependency-injected stopLocalNetwork
 * makes all lifecycle logic directly testable without spawning processes.
 *
 * @module process_lifecycle_test
 */

import { assertEquals } from "@std/assert";
import {
  createProcessLifecycle,
  type ProcessLifecycleOptions,
} from "./process_lifecycle.ts";

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

interface LifecycleFixture {
  lifecycle: ReturnType<typeof createProcessLifecycle>;
  callCount(): number;
  lastOpts(): Record<string, unknown> | undefined;
}

function makeLifecycle(
  overrides: Partial<ProcessLifecycleOptions["args"]> = {},
  stopFn?: (opts: Record<string, unknown>) => Promise<void>,
): LifecycleFixture {
  let calls = 0;
  let lastOpts: Record<string, unknown> | undefined;

  const stopLocalNetwork = stopFn ?? (async (opts) => {
    calls++;
    lastOpts = opts as Record<string, unknown>;
  });

  const lifecycle = createProcessLifecycle({
    args: {
      binary: false,
      keepRunning: false,
      teardown: false,
      noSetup: false,
      ...overrides,
    },
    context: {
      runId: "test-run-001",
      diagnosticsDir: "/tmp/diag",
    },
    stopLocalNetwork,
  });

  return {
    lifecycle,
    callCount: () => calls,
    lastOpts: () => lastOpts,
  };
}

// ---------------------------------------------------------------------------
// stopIfNeeded — gating behavior
// ---------------------------------------------------------------------------

Deno.test("createProcessLifecycle: stopIfNeeded is no-op before markNetworkStarted", async () => {
  const { lifecycle, callCount } = makeLifecycle();
  await lifecycle.stopIfNeeded();
  assertEquals(callCount(), 0);
});

Deno.test("createProcessLifecycle: stopIfNeeded calls stopLocalNetwork after markNetworkStarted", async () => {
  const { lifecycle, callCount } = makeLifecycle();
  lifecycle.markNetworkStarted();
  await lifecycle.stopIfNeeded();
  assertEquals(callCount(), 1);
});

Deno.test("createProcessLifecycle: stopIfNeeded is no-op when keepRunning is true", async () => {
  const { lifecycle, callCount } = makeLifecycle({ keepRunning: true });
  lifecycle.markNetworkStarted();
  await lifecycle.stopIfNeeded();
  assertEquals(callCount(), 0);
});

Deno.test("createProcessLifecycle: stopIfNeeded swallows errors from stopLocalNetwork", async () => {
  let threw = false;
  const lifecycle = createProcessLifecycle({
    args: { binary: false, keepRunning: false, teardown: false, noSetup: false },
    context: { runId: "r", diagnosticsDir: "/d" },
    stopLocalNetwork: async () => {
      throw new Error("network error");
    },
  });
  lifecycle.markNetworkStarted();
  try {
    await lifecycle.stopIfNeeded();
  } catch {
    threw = true;
  }
  assertEquals(threw, false);
});

Deno.test("createProcessLifecycle: stopIfNeeded resets networkStarted — second call is no-op", async () => {
  const { lifecycle, callCount } = makeLifecycle();
  lifecycle.markNetworkStarted();
  await lifecycle.stopIfNeeded();
  await lifecycle.stopIfNeeded(); // second call: networkStarted is false again
  assertEquals(callCount(), 1);
});

// ---------------------------------------------------------------------------
// finalizeRun — diagnostic collection
// ---------------------------------------------------------------------------

Deno.test("createProcessLifecycle: finalizeRun collects diagnostics when there are failures", async () => {
  const { lifecycle } = makeLifecycle();
  let collected = false;
  await lifecycle.finalizeRun({
    results: [{ result: { failed: 1 } }],
    fatalError: null,
    collectDiagnostics: async () => {
      collected = true;
    },
  });
  assertEquals(collected, true);
});

Deno.test("createProcessLifecycle: finalizeRun skips diagnostics when all pass and no fatalError", async () => {
  const { lifecycle } = makeLifecycle();
  let collected = false;
  await lifecycle.finalizeRun({
    results: [{ result: { failed: 0 } }],
    fatalError: null,
    collectDiagnostics: async () => {
      collected = true;
    },
  });
  assertEquals(collected, false);
});

Deno.test("createProcessLifecycle: finalizeRun collects diagnostics when fatalError is set", async () => {
  const { lifecycle } = makeLifecycle();
  let collected = false;
  await lifecycle.finalizeRun({
    results: [{ result: { failed: 0 } }],
    fatalError: new Error("fatal"),
    collectDiagnostics: async () => {
      collected = true;
    },
  });
  assertEquals(collected, true);
});

// ---------------------------------------------------------------------------
// finalizeRun — teardown paths
// ---------------------------------------------------------------------------

Deno.test("createProcessLifecycle: finalizeRun stops network when teardown is true", async () => {
  const { lifecycle, callCount } = makeLifecycle({ teardown: true });
  lifecycle.markNetworkStarted();
  await lifecycle.finalizeRun({
    results: [],
    fatalError: null,
    collectDiagnostics: async () => {},
  });
  assertEquals(callCount(), 1);
});

Deno.test("createProcessLifecycle: finalizeRun stops network when noSetup=false and keepRunning=false", async () => {
  const { lifecycle, callCount } = makeLifecycle({ noSetup: false, keepRunning: false });
  lifecycle.markNetworkStarted();
  await lifecycle.finalizeRun({
    results: [],
    fatalError: null,
    collectDiagnostics: async () => {},
  });
  assertEquals(callCount(), 1);
});

Deno.test("createProcessLifecycle: finalizeRun does not stop when noSetup=true and teardown=false", async () => {
  const { lifecycle, callCount } = makeLifecycle({ noSetup: true, teardown: false });
  lifecycle.markNetworkStarted();
  await lifecycle.finalizeRun({
    results: [],
    fatalError: null,
    collectDiagnostics: async () => {},
  });
  assertEquals(callCount(), 0);
});

Deno.test("createProcessLifecycle: finalizeRun does not stop when keepRunning=true", async () => {
  const { lifecycle, callCount } = makeLifecycle({ keepRunning: true, teardown: false });
  lifecycle.markNetworkStarted();
  await lifecycle.finalizeRun({
    results: [],
    fatalError: null,
    collectDiagnostics: async () => {},
  });
  assertEquals(callCount(), 0);
});

// ---------------------------------------------------------------------------
// scheduleDrainTimeout
// ---------------------------------------------------------------------------

Deno.test("createProcessLifecycle: scheduleDrainTimeout returns a numeric timer id", () => {
  const { lifecycle } = makeLifecycle();
  const id = lifecycle.scheduleDrainTimeout(60000);
  assertEquals(typeof id, "number");
  clearTimeout(id);
});
