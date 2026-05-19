#!/usr/bin/env -S deno run -A
/**
 * backfill_account_usage.ts
 *
 * Populate the account_usage table in each actor store from existing
 * blob, block, and record data.
 */

import { parseArgs } from "@std/cli";
import { join, basename } from "@std/path";
import { exists } from "@std/fs";

const args = parseArgs(Deno.args);
const dataDir = args._[0] as string;

if (!dataDir) {
  console.error("Usage: backfill_account_usage.ts <pds-data-dir>");
  Deno.exit(1);
}

const actorsDir = join(dataDir, "actors");

if (!await exists(actorsDir)) {
  console.error(`Error: actors directory not found at ${actorsDir}`);
  Deno.exit(1);
}

console.log(`Scanning actor databases in ${actorsDir}...`);

let actorCount = 0;
let totalRecords = 0;
let totalBlobs = 0;

async function runSql(dbPath: string, sql: string): Promise<string> {
  const proc = new Deno.Command("sqlite3", {
    args: [dbPath, sql],
    stdout: "piped",
    stderr: "piped",
  });
  const { code, stdout, stderr } = await proc.output();
  if (code !== 0) {
    const err = new TextDecoder().decode(stderr);
    console.warn(`Warning: failed to run SQL on ${dbPath}: ${err}`);
    return "";
  }
  return new TextDecoder().decode(stdout).trim();
}

for await (const entry of Deno.readDir(actorsDir)) {
  if (!entry.isFile || !entry.name.endsWith(".db")) continue;

  const dbPath = join(actorsDir, entry.name);
  const did = basename(entry.name, ".db");

  // Ensure table exists
  await runSql(dbPath, `
    CREATE TABLE IF NOT EXISTS account_usage (
        did TEXT PRIMARY KEY,
        blob_bytes INTEGER NOT NULL DEFAULT 0,
        blob_count INTEGER NOT NULL DEFAULT 0,
        repo_bytes INTEGER NOT NULL DEFAULT 0,
        record_count INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    );
  `);

  // Get stats
  const recordCountStr = await runSql(dbPath, "SELECT COUNT(*) FROM records;");
  const recordCount = parseInt(recordCountStr) || 0;

  const repoBytesStr = await runSql(dbPath, "SELECT COALESCE(SUM(size), 0) FROM ipld_blocks;");
  const repoBytes = parseInt(repoBytesStr) || 0;

  let blobBytes = 0;
  let blobCount = 0;
  const blobTableExists = await runSql(dbPath, "SELECT name FROM sqlite_master WHERE type='table' AND name='blobs';");
  
  if (blobTableExists === "blobs") {
    const bBytesStr = await runSql(dbPath, "SELECT COALESCE(SUM(size), 0) FROM blobs;");
    blobBytes = parseInt(bBytesStr) || 0;
    const bCountStr = await runSql(dbPath, "SELECT COUNT(*) FROM blobs;");
    blobCount = parseInt(bCountStr) || 0;
  }

  // Upsert
  await runSql(dbPath, `
    INSERT OR REPLACE INTO account_usage (did, blob_bytes, blob_count, repo_bytes, record_count)
    VALUES ('${did}', ${blobBytes}, ${blobCount}, ${repoBytes}, ${recordCount});
  `);

  actorCount++;
  totalRecords += recordCount;
  totalBlobs += blobCount;
}

console.log("Backfill complete.");
console.log(`  Actors processed: ${actorCount}`);
console.log(`  Total records:    ${totalRecords}`);
console.log(`  Total blobs:      ${totalBlobs}`);
