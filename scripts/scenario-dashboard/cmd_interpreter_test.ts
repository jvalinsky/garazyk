/**
 * Tests for the shared cmd_interpreter module.
 *
 * Verifies that constructMsg and constructErrorMsg produce the correct Msg
 * variants for all shared branches, and that the extra-branches extension
 * mechanism works for TUI-specific cases.
 */
import { assertEquals, assertThrows } from "@std/assert";
import {
  constructMsg,
  constructErrorMsg,
  isRecord,
  isRunProgress,
  isTopologyPreview,
} from "./cmd_interpreter.ts";
import type { ExtraMsgBranch, ExtraErrorMsgBranch } from "./cmd_interpreter.ts";
import type { Msg } from "./dashboard_state.ts";

// ---------------------------------------------------------------------------
// Type guard tests
// ---------------------------------------------------------------------------

Deno.test("isRecord: returns true for plain objects", () => {
  assertEquals(isRecord({}), true);
  assertEquals(isRecord({ a: 1 }), true);
});

Deno.test("isRecord: returns false for null, arrays, primitives", () => {
  assertEquals(isRecord(null), false);
  assertEquals(isRecord([]), false);
  assertEquals(isRecord("string"), false);
  assertEquals(isRecord(42), false);
  assertEquals(isRecord(undefined), false);
});

Deno.test("isRunProgress: returns true for valid RunProgress", () => {
  const valid = {
    exists: true,
    runId: "run-1",
    total: 10,
    completed: 5,
    currentScenario: null,
    currentScenarioId: null,
    elapsedMs: 1000,
    updatedAt: Date.now(),
    now: Date.now(),
    running: true,
  };
  assertEquals(isRunProgress(valid), true);
});

Deno.test("isRunProgress: returns false for missing fields", () => {
  assertEquals(isRunProgress({ exists: true, runId: "x" }), false);
  assertEquals(isRunProgress(null), false);
  assertEquals(isRunProgress({}), false);
});

Deno.test("isTopologyPreview: returns true for valid preview", () => {
  const valid = { name: "default", roles: ["pds"], capabilities: ["feed"] };
  assertEquals(isTopologyPreview(valid), true);
});

Deno.test("isTopologyPreview: returns false for missing fields", () => {
  assertEquals(isTopologyPreview({ name: "x" }), false);
  assertEquals(isTopologyPreview({ roles: [] }), false);
  assertEquals(isTopologyPreview(null), false);
});

// ---------------------------------------------------------------------------
// constructMsg — shared branches
// ---------------------------------------------------------------------------

Deno.test("constructMsg: network/healthReceived with valid data", () => {
  const msg = constructMsg("network/healthReceived", { services: [{ name: "pds" }] });
  assertEquals(msg.type, "network/healthReceived");
  if (msg.type === "network/healthReceived") {
    assertEquals((msg as { services: unknown }).services, [{ name: "pds" }]);
  }
});

Deno.test("constructMsg: network/healthReceived with malformed data falls back to healthFailed", () => {
  const msg = constructMsg("network/healthReceived", "not an object");
  assertEquals(msg.type, "network/healthFailed");
});

Deno.test("constructMsg: network/healthReceived preserves token from meta", () => {
  const msg = constructMsg("network/healthReceived", { services: [] }, { token: 42 });
  if (msg.type === "network/healthReceived") {
    assertEquals(msg.token, 42);
  }
});

Deno.test("constructMsg: runs/activeReceived with valid data", () => {
  const msg = constructMsg("runs/activeReceived", { activeRun: { id: "r1" } });
  assertEquals(msg.type, "runs/activeReceived");
});

Deno.test("constructMsg: runs/activeReceived with null activeRun", () => {
  const msg = constructMsg("runs/activeReceived", { activeRun: null });
  assertEquals(msg.type, "runs/activeReceived");
  if (msg.type === "runs/activeReceived") {
    assertEquals(msg.run, null);
  }
});

Deno.test("constructMsg: runs/activeReceived with malformed data", () => {
  const msg = constructMsg("runs/activeReceived", "bad");
  assertEquals(msg.type, "runs/activeFailed");
});

Deno.test("constructMsg: runs/startSucceeded with valid data", () => {
  const msg = constructMsg("runs/startSucceeded", { runId: "new-run" });
  assertEquals(msg.type, "runs/startSucceeded");
  if (msg.type === "runs/startSucceeded") {
    assertEquals(msg.runId, "new-run");
  }
});

Deno.test("constructMsg: runs/startSucceeded with malformed data", () => {
  const msg = constructMsg("runs/startSucceeded", {});
  assertEquals(msg.type, "runs/startFailed");
});

Deno.test("constructMsg: runs/progressReceived with valid data", () => {
  const progress = {
    exists: true,
    runId: "r1",
    total: 10,
    completed: 5,
    currentScenario: null,
    currentScenarioId: null,
    elapsedMs: 1000,
    updatedAt: 1000,
    now: 1000,
    running: true,
  };
  const msg = constructMsg("runs/progressReceived", progress, { runId: "r1", token: 7 });
  assertEquals(msg.type, "runs/progressReceived");
  if (msg.type === "runs/progressReceived") {
    assertEquals(msg.runId, "r1");
    assertEquals(msg.token, 7);
  }
});

Deno.test("constructMsg: runs/progressReceived with malformed data", () => {
  const msg = constructMsg("runs/progressReceived", {}, { runId: "r1" });
  assertEquals(msg.type, "runs/progressFailed");
});

Deno.test("constructMsg: scenarios/received with valid data", () => {
  const msg = constructMsg("scenarios/received", { scenarios: [{ id: "s1" }] });
  assertEquals(msg.type, "scenarios/received");
});

Deno.test("constructMsg: scenarios/received with malformed data", () => {
  const msg = constructMsg("scenarios/received", {});
  assertEquals(msg.type, "scenarios/failed");
});

Deno.test("constructMsg: topology/listReceived with valid data", () => {
  const msg = constructMsg("topology/listReceived", { topologies: [{ name: "default" }] });
  assertEquals(msg.type, "topology/listReceived");
});

Deno.test("constructMsg: topology/listReceived with malformed data", () => {
  const msg = constructMsg("topology/listReceived", {});
  assertEquals(msg.type, "topology/listFailed");
});

Deno.test("constructMsg: topology/previewReceived with valid data", () => {
  const preview = { name: "default", roles: ["pds"], capabilities: ["feed"] };
  const msg = constructMsg("topology/previewReceived", preview, { name: "default", token: 3 });
  assertEquals(msg.type, "topology/previewReceived");
  if (msg.type === "topology/previewReceived") {
    assertEquals(msg.name, "default");
    assertEquals(msg.token, 3);
  }
});

Deno.test("constructMsg: topology/previewReceived with malformed data", () => {
  const msg = constructMsg("topology/previewReceived", {}, { name: "x" });
  assertEquals(msg.type, "topology/previewFailed");
});

Deno.test("constructMsg: network/startSucceeded", () => {
  const msg = constructMsg("network/startSucceeded", {});
  assertEquals(msg.type, "network/startSucceeded");
});

Deno.test("constructMsg: network/stopSucceeded", () => {
  const msg = constructMsg("network/stopSucceeded", {});
  assertEquals(msg.type, "network/stopSucceeded");
});

Deno.test("constructMsg: runs/stopSucceeded", () => {
  const msg = constructMsg("runs/stopSucceeded", {});
  assertEquals(msg.type, "runs/stopSucceeded");
});

Deno.test("constructMsg: runs/restartSucceeded with valid data", () => {
  const msg = constructMsg("runs/restartSucceeded", { newRunId: "new" });
  assertEquals(msg.type, "runs/restartSucceeded");
  if (msg.type === "runs/restartSucceeded") {
    assertEquals(msg.newRunId, "new");
  }
});

Deno.test("constructMsg: runs/restartSucceeded with malformed data", () => {
  const msg = constructMsg("runs/restartSucceeded", {});
  assertEquals(msg.type, "runs/restartFailed");
});

Deno.test("constructMsg: logs/received with string data", () => {
  const msg = constructMsg("logs/received", "log text", { runId: "r1" });
  assertEquals(msg.type, "logs/received");
  if (msg.type === "logs/received") {
    assertEquals(msg.text, "log text");
    assertEquals(msg.runId, "r1");
  }
});

Deno.test("constructMsg: logs/received with non-string data", () => {
  const msg = constructMsg("logs/received", 42);
  assertEquals(msg.type, "logs/received");
  if (msg.type === "logs/received") {
    assertEquals(msg.text, "42");
  }
});

Deno.test("constructMsg: metrics/received with valid data", () => {
  const msg = constructMsg("metrics/received", { stats: { pds: { cpu: "10%", mem: "50mb" } } });
  assertEquals(msg.type, "metrics/received");
});

Deno.test("constructMsg: metrics/received with malformed data", () => {
  const msg = constructMsg("metrics/received", "bad");
  assertEquals(msg.type, "metrics/failed");
});

Deno.test("constructMsg: runs/detailResults with valid data", () => {
  const msg = constructMsg("runs/detailResults", { results: [{ scenarioId: "s1" }] });
  assertEquals(msg.type, "runs/detailResults");
});

Deno.test("constructMsg: runs/detailResults with malformed data closes overlay", () => {
  const msg = constructMsg("runs/detailResults", {});
  assertEquals(msg.type, "runs/closeDetail");
});

Deno.test("constructMsg: unknown onSuccess throws", () => {
  assertThrows(() => constructMsg("unknown/type", {}), Error, "Unknown success msg type");
});

// ---------------------------------------------------------------------------
// constructMsg — extra branches (TUI-specific)
// ---------------------------------------------------------------------------

Deno.test("constructMsg: extra branches — runs/recentReceived with valid data", () => {
  const tuiBranch: ExtraMsgBranch = (onSuccess, data, _meta, fields) => {
    const { tokenField } = fields;
    switch (onSuccess) {
      case "runs/recentReceived":
        if (!Array.isArray(data)) {
          return { type: "runs/recentFailed", error: "Malformed recent runs response", ...tokenField };
        }
        return { type: "runs/recentReceived", runs: data as never[], ...tokenField };
      default:
        return undefined;
    }
  };

  const msg = constructMsg("runs/recentReceived", [{ id: "r1" }], { token: 5 }, tuiBranch);
  assertEquals(msg.type, "runs/recentReceived");
  if (msg.type === "runs/recentReceived") {
    assertEquals(msg.token, 5);
  }
});

Deno.test("constructMsg: extra branches — runs/recentReceived with malformed data", () => {
  const tuiBranch: ExtraMsgBranch = (onSuccess, data, _meta, fields) => {
    const { tokenField } = fields;
    switch (onSuccess) {
      case "runs/recentReceived":
        if (!Array.isArray(data)) {
          return { type: "runs/recentFailed", error: "Malformed recent runs response", ...tokenField };
        }
        return { type: "runs/recentReceived", runs: data as never[], ...tokenField };
      default:
        return undefined;
    }
  };

  const msg = constructMsg("runs/recentReceived", "bad", {}, tuiBranch);
  assertEquals(msg.type, "runs/recentFailed");
});

Deno.test("constructMsg: extra branches returns undefined falls through to shared switch", () => {
  const tuiBranch: ExtraMsgBranch = () => undefined;
  const msg = constructMsg("network/startSucceeded", {}, {}, tuiBranch);
  assertEquals(msg.type, "network/startSucceeded");
});

// ---------------------------------------------------------------------------
// constructErrorMsg — shared branches
// ---------------------------------------------------------------------------

Deno.test("constructErrorMsg: network/healthFailed preserves token", () => {
  const msg = constructErrorMsg("network/healthFailed", "timeout", { token: 1 });
  assertEquals(msg.type, "network/healthFailed");
  if (msg.type === "network/healthFailed") {
    assertEquals(msg.error, "timeout");
    assertEquals(msg.token, 1);
  }
});

Deno.test("constructErrorMsg: runs/activeFailed", () => {
  const msg = constructErrorMsg("runs/activeFailed", "err", { token: 2 });
  assertEquals(msg.type, "runs/activeFailed");
  if (msg.type === "runs/activeFailed") {
    assertEquals(msg.token, 2);
  }
});

Deno.test("constructErrorMsg: runs/progressFailed preserves runId and token", () => {
  const msg = constructErrorMsg("runs/progressFailed", "err", { runId: "r1", token: 3 });
  assertEquals(msg.type, "runs/progressFailed");
  if (msg.type === "runs/progressFailed") {
    assertEquals(msg.runId, "r1");
    assertEquals(msg.token, 3);
  }
});

Deno.test("constructErrorMsg: runs/startFailed", () => {
  const msg = constructErrorMsg("runs/startFailed", "conflict");
  assertEquals(msg.type, "runs/startFailed");
});

Deno.test("constructErrorMsg: runs/stopFailed", () => {
  const msg = constructErrorMsg("runs/stopFailed", "err");
  assertEquals(msg.type, "runs/stopFailed");
});

Deno.test("constructErrorMsg: runs/restartFailed", () => {
  const msg = constructErrorMsg("runs/restartFailed", "err");
  assertEquals(msg.type, "runs/restartFailed");
});

Deno.test("constructErrorMsg: scenarios/failed", () => {
  const msg = constructErrorMsg("scenarios/failed", "err");
  assertEquals(msg.type, "scenarios/failed");
});

Deno.test("constructErrorMsg: topology/listFailed", () => {
  const msg = constructErrorMsg("topology/listFailed", "err");
  assertEquals(msg.type, "topology/listFailed");
});

Deno.test("constructErrorMsg: topology/previewFailed preserves name and token", () => {
  const msg = constructErrorMsg("topology/previewFailed", "err", { name: "default", token: 4 });
  assertEquals(msg.type, "topology/previewFailed");
  if (msg.type === "topology/previewFailed") {
    assertEquals(msg.name, "default");
    assertEquals(msg.token, 4);
  }
});

Deno.test("constructErrorMsg: network/startFailed", () => {
  const msg = constructErrorMsg("network/startFailed", "err");
  assertEquals(msg.type, "network/startFailed");
});

Deno.test("constructErrorMsg: network/stopFailed", () => {
  const msg = constructErrorMsg("network/stopFailed", "err");
  assertEquals(msg.type, "network/stopFailed");
});

Deno.test("constructErrorMsg: logs/failed preserves runId and token", () => {
  const msg = constructErrorMsg("logs/failed", "err", { runId: "r1", token: 5 });
  assertEquals(msg.type, "logs/failed");
  if (msg.type === "logs/failed") {
    assertEquals(msg.runId, "r1");
    assertEquals(msg.token, 5);
  }
});

Deno.test("constructErrorMsg: metrics/failed preserves token", () => {
  const msg = constructErrorMsg("metrics/failed", "err", { token: 6 });
  assertEquals(msg.type, "metrics/failed");
  if (msg.type === "metrics/failed") {
    assertEquals(msg.token, 6);
  }
});

Deno.test("constructErrorMsg: runs/closeDetail produces closeDetail msg", () => {
  const msg = constructErrorMsg("runs/closeDetail", "");
  assertEquals(msg.type, "runs/closeDetail");
});

Deno.test("constructErrorMsg: unknown onError throws", () => {
  assertThrows(() => constructErrorMsg("unknown/type", "err"), Error, "Unknown error msg type");
});

// ---------------------------------------------------------------------------
// constructErrorMsg — extra branches (TUI-specific)
// ---------------------------------------------------------------------------

Deno.test("constructErrorMsg: extra branches — runs/recentFailed", () => {
  const tuiBranch: ExtraErrorMsgBranch = (onError, error, _meta, fields) => {
    const { tokenField } = fields;
    switch (onError) {
      case "runs/recentFailed":
        return { type: "runs/recentFailed", error, ...tokenField };
      default:
        return undefined;
    }
  };

  const msg = constructErrorMsg("runs/recentFailed", "err", { token: 7 }, tuiBranch);
  assertEquals(msg.type, "runs/recentFailed");
  if (msg.type === "runs/recentFailed") {
    assertEquals(msg.error, "err");
    assertEquals(msg.token, 7);
  }
});

Deno.test("constructErrorMsg: extra branches returns undefined falls through", () => {
  const tuiBranch: ExtraErrorMsgBranch = () => undefined;
  const msg = constructErrorMsg("network/healthFailed", "err", {}, tuiBranch);
  assertEquals(msg.type, "network/healthFailed");
});
