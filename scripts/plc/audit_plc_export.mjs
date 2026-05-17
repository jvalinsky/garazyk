#!/usr/bin/env node
/**
 * PLC Export Structure Analyzer
 *
 * Analyzes the structure and composition of the plc.directory export:
 * operation types, key types (secp256k1 vs P-256), field presence,
 * batch composition, and temporal distribution.
 *
 * Usage:
 *   node audit_plc_export.mjs [options]
 *
 * Dependencies: npm install (from scripts/plc/)
 */

import { option, parseArgs, printHelpAndExit } from "./lib/args.mjs";
import { classifyDidKey, fetchExportBatch, getRotationKeys, validateFields } from "./lib/plc.mjs";

// ── Option definitions ────────────────────────────────────────────

const OPTIONS = [
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
    description: "Total operations to analyze",
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
];

// ── Main ──────────────────────────────────────────────────────────

async function main() {
  const { args, helpRequested } = parseArgs(process.argv, OPTIONS);

  if (helpRequested) {
    printHelpAndExit(
      "PLC Export Structure Analyzer",
      "node audit_plc_export.mjs [options]",
      OPTIONS,
      `  # Analyze 1000 operations from the beginning
  node audit_plc_export.mjs

  # Analyze from a specific timestamp
  node audit_plc_export.mjs --after '2024-06-01T00:00:00.000Z' --count 2000

  # Larger batch size for fewer HTTP requests
  node audit_plc_export.mjs --count 5000 --batch-size 500

  # Using environment variables
  PLC_SERVER=http://localhost:2582 PLC_COUNT=2000 node audit_plc_export.mjs`,
    );
  }

  // Accumulators
  let totalOps = 0;
  const typeCounts = {};
  const keyTypeCounts = {};
  let genesisCount = 0;
  let nonGenesisCount = 0;
  let nullifiedCount = 0;
  const missingFields = [];
  const batchStats = [];

  let cursor = args.after;
  let batchNum = 0;

  console.log("PLC Export Structure Audit");
  console.log(`  Server:  ${args.server}`);
  console.log(`  Count:   ${args.count}`);
  console.log(`  Batch:   ${args.batchSize}`);
  console.log(`  After:   ${cursor || "(beginning)"}`);
  console.log("");

  while (totalOps < args.count) {
    const remaining = args.count - totalOps;
    const batchSize = Math.min(args.batchSize, remaining);
    let entries;

    try {
      entries = await fetchExportBatch(args.server, cursor, batchSize);
    } catch (err) {
      console.error(`Fetch error at batch ${batchNum}: ${err.message}`);
      break;
    }

    if (entries.length === 0) break;

    let batchGenesis = 0, batchNonGenesis = 0;
    const batchTypes = {};

    for (const entry of entries) {
      const op = entry.operation;
      totalOps++;

      // Operation type
      typeCounts[op.type] = (typeCounts[op.type] || 0) + 1;
      batchTypes[op.type] = (batchTypes[op.type] || 0) + 1;

      // Genesis vs non-genesis
      if (op.prev === null || op.prev === undefined) {
        genesisCount++;
        batchGenesis++;
      } else {
        nonGenesisCount++;
        batchNonGenesis++;
      }

      // Nullified
      if (entry.nullified) nullifiedCount++;

      // Key type analysis (uses shared getRotationKeys + classifyDidKey)
      const keys = getRotationKeys(op);
      for (const key of keys) {
        const kt = classifyDidKey(key);
        keyTypeCounts[kt] = (keyTypeCounts[kt] || 0) + 1;
      }

      // Field presence (uses shared validateFields)
      const missing = validateFields(op);
      if (missing.length > 0) {
        missingFields.push({ did: entry.did, type: op.type, missing });
      }
    }

    batchStats.push({
      batch: batchNum,
      genesis: batchGenesis,
      nonGenesis: batchNonGenesis,
      types: batchTypes,
      cursor: entries[entries.length - 1].createdAt,
    });

    cursor = entries[entries.length - 1].createdAt;
    batchNum++;
  }

  // ── Report ───────────────────────────────────────────────────────

  console.log(`\n${"=".repeat(60)}`);
  console.log("AUDIT RESULTS");
  console.log("=".repeat(60));

  console.log(`\nTotal operations: ${totalOps}`);
  console.log(
    `Genesis (prev=null): ${genesisCount} (${(genesisCount / totalOps * 100).toFixed(1)}%)`,
  );
  console.log(
    `Non-genesis:         ${nonGenesisCount} (${(nonGenesisCount / totalOps * 100).toFixed(1)}%)`,
  );
  console.log(`Nullified:           ${nullifiedCount}`);

  console.log("\nOperation types:");
  for (const [type, count] of Object.entries(typeCounts).sort((a, b) => b[1] - a[1])) {
    console.log(
      `  ${String(count).padStart(6)}x  ${type} (${(count / totalOps * 100).toFixed(1)}%)`,
    );
  }

  console.log("\nKey types (across all rotation/signing/recovery keys):");
  for (const [kt, count] of Object.entries(keyTypeCounts).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${String(count).padStart(6)}x  ${kt}`);
  }

  if (missingFields.length > 0) {
    console.log(`\nMissing required fields (${missingFields.length} operations):`);
    for (const { did, type, missing } of missingFields.slice(0, 20)) {
      console.log(`  ${did} (${type}): missing ${missing.join(", ")}`);
    }
    if (missingFields.length > 20) {
      console.log(`  ... and ${missingFields.length - 20} more`);
    }
  } else {
    console.log("\nAll operations have required fields present.");
  }

  // Batch composition summary
  if (batchStats.length > 1) {
    console.log("\nBatch composition (first/last/summary):");
    const first = batchStats[0];
    const last = batchStats[batchStats.length - 1];
    console.log(
      `  Batch 0:    ${first.genesis} genesis, ${first.nonGenesis} non-genesis  cursor=${first.cursor}`,
    );
    if (batchStats.length > 2) {
      console.log("  ...");
    }
    console.log(
      `  Batch ${
        batchStats.length - 1
      }:  ${last.genesis} genesis, ${last.nonGenesis} non-genesis  cursor=${last.cursor}`,
    );

    const avgGenesis = batchStats.reduce((s, b) => s + b.genesis, 0) / batchStats.length;
    const avgNonGenesis = batchStats.reduce((s, b) => s + b.nonGenesis, 0) / batchStats.length;
    console.log(
      `  Average:    ${avgGenesis.toFixed(1)} genesis, ${
        avgNonGenesis.toFixed(1)
      } non-genesis per batch`,
    );
  }
}

main().catch((err) => {
  console.error(`Fatal: ${err.message}`);
  process.exit(2);
});
