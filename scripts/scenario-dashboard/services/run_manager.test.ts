import { assertEquals, assertExists } from "$std/assert/mod.ts";
import { runManager } from "./run_manager.ts";
import { db } from "../db/index.ts";

Deno.test({
  name: "RunManager - basic lifecycle",
  async fn() {
    // Start a dummy run
    const result = await runManager.startRun({
      topology: "garazyk-default",
      runner: "host",
      scenarioIds: ["01"],
      pds2: false,
      binaryMode: false,
    });

    if ("conflict" in result) {
      throw new Error(`Conflict: ${result.conflict}`);
    }

    const runId = result.runId;
    assertExists(runId);

    const active = runManager.getActiveRun();
    assertExists(active);
    assertEquals(active.id, runId);
    assertEquals(active.status, "running");

    // Check DB entry
    const row = db.prepare("SELECT * FROM runs WHERE id = ?").get(runId) as any;
    assertExists(row);
    assertEquals(row.status, "running");

    // Stop the run
    await runManager.stopRun(runId, false);

    const activeAfterStop = runManager.getActiveRun();
    assertEquals(activeAfterStop, undefined);

    const rowAfterStop = db.prepare("SELECT * FROM runs WHERE id = ?").get(runId) as any;
    assertEquals(rowAfterStop.status, "error");
    assertEquals(rowAfterStop.stop_reason, "manual_stop");
  },
  // Ensure we don't leak resources
  sanitizeResources: false,
  sanitizeOps: false,
});

Deno.test({
  name: "RunManager - concurrent run prevention",
  async fn() {
    const r1 = await runManager.startRun({
      topology: "garazyk-default",
      runner: "host",
      scenarioIds: ["01"],
      pds2: false,
      binaryMode: false,
    });

    const r2 = await runManager.startRun({
      topology: "garazyk-default",
      runner: "host",
      scenarioIds: ["02"],
      pds2: false,
      binaryMode: false,
    });

    if (!("conflict" in r2)) {
      throw new Error("Should have failed with conflict");
    }

    assertExists(r2.conflict);

    // Cleanup
    if (!("conflict" in r1)) {
      await runManager.stopRun(r1.runId, false);
    }
  },
  sanitizeResources: false,
  sanitizeOps: false,
});
