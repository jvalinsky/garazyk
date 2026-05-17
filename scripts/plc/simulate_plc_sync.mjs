#!/usr/bin/env node
/**
 * PLC Sync Pipeline Simulator
 *
 * Simulates the PLCSyncEngine against the real plc.directory export,
 * verifying each operation's signature and prev-link chain integrity.
 * Supports both sequential (correct) and concurrent (buggy) processing
 * modes to demonstrate the concurrent validation bug.
 *
 * Usage:
 *   node simulate_plc_sync.mjs [options]
 *
 * Dependencies: npm install (from scripts/plc/)
 */

import { option, parseArgs, printHelpAndExit } from "./lib/args.mjs";
import {
  DIDStore,
  fetchExportBatch,
  getRotationKeys,
  verifyOperationSignature,
  verifyOperationSignatureWithPrev,
} from "./lib/plc.mjs";

// ── Option definitions ────────────────────────────────────────────

const OPTIONS = [
  option({
    name: "mode",
    flag: "--mode",
    type: "string",
    default: "sequential",
    env: "PLC_SYNC_MODE",
    description: "Processing mode: sequential or concurrent",
  }),
  option({
    name: "after",
    flag: "--after",
    type: "string",
    default: null,
    env: "PLC_AFTER",
    description: "Start from this export cursor (ISO timestamp)",
  }),
  option({
    name: "count",
    flag: "--count",
    type: "int",
    default: 1000,
    env: "PLC_COUNT",
    description: "Total operations to process",
  }),
  option({
    name: "batchSize",
    flag: "--batch-size",
    type: "int",
    default: 100,
    env: "PLC_BATCH_SIZE",
    description: "Operations per batch",
  }),
  option({
    name: "server",
    flag: "--server",
    type: "string",
    default: "https://plc.directory",
    env: "PLC_SERVER",
    description: "PLC directory URL",
  }),
  option({
    name: "verbose",
    flag: "--verbose",
    short: "-v",
    type: "boolean",
    default: false,
    description: "Print per-batch details",
  }),
];

// ── Operation verification ────────────────────────────────────────

async function verifyOp(op, history) {
  // Genesis branch: no prior history for this DID
  if (history.length === 0) {
    if (op.prev !== null && op.prev !== undefined) {
      return { valid: false, reason: "non-genesis-without-predecessor" };
    }

    const result = await verifyOperationSignature(op);
    if (result.valid) return { valid: true };
    return { valid: false, reason: "signature-failed" };
  }

  // Non-genesis branch: must have prev link
  if (op.prev === null || op.prev === undefined) {
    return { valid: false, reason: "genesis-with-existing-history" };
  }

  // Find predecessor by CID
  const prevOp = history.find((h) => h.cid === op.prev);
  if (!prevOp) {
    return { valid: false, reason: "prev-cid-not-found" };
  }

  // Verify signature against predecessor's rotation keys
  const result = await verifyOperationSignatureWithPrev(op, prevOp);
  if (result.valid) return { valid: true };
  return { valid: false, reason: "signature-failed" };
}

// ── Simulation modes ──────────────────────────────────────────────

async function simulateSequential(entries, store) {
  let passed = 0, failed = 0;
  const reasons = {};

  for (const entry of entries) {
    const history = store.getHistory(entry.did);
    const result = await verifyOp(entry.operation, history);

    if (result.valid) {
      store.append(entry.operation, entry.did, entry.cid);
      passed++;
    } else {
      failed++;
      reasons[result.reason] = (reasons[result.reason] || 0) + 1;
    }
  }

  return { passed, failed, reasons };
}

async function simulateConcurrent(entries, store) {
  let passed = 0, failed = 0;
  const reasons = {};

  // Phase 1: Validate all operations against store state BEFORE this batch
  const validEntries = [];
  for (const entry of entries) {
    const history = store.getHistory(entry.did);
    const result = await verifyOp(entry.operation, history);

    if (result.valid) {
      validEntries.push(entry);
    } else {
      failed++;
      reasons[result.reason] = (reasons[result.reason] || 0) + 1;
    }
  }

  // Phase 2: Ingest valid operations
  for (const entry of validEntries) {
    store.append(entry.operation, entry.did, entry.cid);
    passed++;
  }

  return { passed, failed, reasons };
}

// ── Main ──────────────────────────────────────────────────────────

async function main() {
  const { args, helpRequested } = parseArgs(process.argv, OPTIONS);

  if (helpRequested) {
    printHelpAndExit(
      "PLC Sync Pipeline Simulator",
      "node simulate_plc_sync.mjs [options]",
      OPTIONS,
      `  # Sequential mode (correct, matches fixed sync engine)
  node simulate_plc_sync.mjs --count 2000 --batch-size 100

  # Concurrent mode (demonstrates the old validation bug)
  node simulate_plc_sync.mjs --mode concurrent --count 2000

  # Start from a specific timestamp
  node simulate_plc_sync.mjs --after '2024-06-01T00:00:00.000Z' --count 500

  # Using environment variables
  PLC_SERVER=http://localhost:2582 PLC_COUNT=500 node simulate_plc_sync.mjs`,
    );
  }

  if (args.mode !== "sequential" && args.mode !== "concurrent") {
    console.error('Error: --mode must be "sequential" or "concurrent"');
    process.exit(2);
  }

  const store = new DIDStore();
  let totalPassed = 0, totalFailed = 0, totalOps = 0;
  const totalReasons = {};
  let cursor = args.after;
  let batchNum = 0;

  console.log("PLC Sync Simulation");
  console.log(`  Mode:      ${args.mode}`);
  console.log(`  Server:    ${args.server}`);
  console.log(`  Count:     ${args.count}`);
  console.log(`  Batch:     ${args.batchSize}`);
  console.log(`  After:     ${cursor || "(beginning)"}`);
  console.log("");

  while (totalOps < args.count) {
    const remaining = args.count - totalOps;
    const batchSize = Math.min(args.batchSize, remaining);
    let entries;

    try {
      entries = await fetchExportBatch(args.server, cursor, batchSize);
    } catch (err) {
      console.error(`\nFetch error at batch ${batchNum}: ${err.message}`);
      break;
    }

    if (entries.length === 0) break;

    const result = args.mode === "sequential"
      ? await simulateSequential(entries, store)
      : await simulateConcurrent(entries, store);

    totalPassed += result.passed;
    totalFailed += result.failed;
    totalOps += entries.length;

    for (const [reason, count] of Object.entries(result.reasons)) {
      totalReasons[reason] = (totalReasons[reason] || 0) + count;
    }

    cursor = entries[entries.length - 1].createdAt;

    if (args.verbose || result.failed > 0) {
      const failStr = result.failed > 0
        ? ` ${result.failed} failed (${
          Object.entries(result.reasons).map(([r, c]) => `${c}x ${r}`).join(", ")
        })`
        : "";
      console.log(
        `  Batch ${
          String(batchNum).padStart(4)
        }: ${result.passed} passed${failStr}  cursor=${cursor}`,
      );
    }

    batchNum++;
  }

  // ── Summary ─────────────────────────────────────────────────────

  const pct = totalOps > 0 ? (totalFailed / totalOps * 100).toFixed(1) : "0.0";
  console.log("");
  console.log(`Results (${args.mode} mode, ${totalOps} operations):`);
  console.log(`  Passed:  ${totalPassed}`);
  console.log(`  Failed:  ${totalFailed} (${pct}%)`);
  console.log(`  DIDs:    ${store.didCount}`);

  if (Object.keys(totalReasons).length > 0) {
    console.log("");
    console.log("Failure breakdown:");
    const sorted = Object.entries(totalReasons).sort((a, b) => b[1] - a[1]);
    for (const [reason, count] of sorted) {
      console.log(`  ${String(count).padStart(6)}x  ${reason}`);
    }
  }

  process.exit(totalFailed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(`Fatal: ${err.message}`);
  process.exit(2);
});
