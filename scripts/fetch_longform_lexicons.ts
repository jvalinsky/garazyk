#!/usr/bin/env -S deno run -A
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * fetch_longform_lexicons.ts
 *
 * Fetch com.atproto.lexicon.schema records from the four longform
 * publishers and write them to NSID-shaped paths under
 * Garazyk/Resources/lexicons/.
 *
 * Re-runnable: against an unchanged network, produces no diff.
 *
 * Publishers:
 *   site.standard.*  did:plc:re3ebnp5v7ffagz6rb6xfei4
 *   pub.leaflet.*     did:plc:btxrwcaeyodrap5mnjw2fvmz
 *   blog.pckt.*       did:plc:revjuqmkvrw6fnkxppqtszpv
 *   app.offprint.*    did:plc:pgjkomf37an4czloay5zeth6
 *
 * Usage:
 *   deno run -A scripts/fetch_longform_lexicons.ts [--dry-run] [--verbose]
 */

import { join, dirname } from "@std/path";
import { ensureDir } from "@std/fs";
import { parseArgs } from "@std/cli";

const args = parseArgs(Deno.args, {
  boolean: ["dry-run", "verbose"],
});

const scriptDir = new URL(".", import.meta.url);
const repoRoot = join(scriptDir.pathname, "..");
const lexiconsDir = join(repoRoot, "Garazyk", "Resources", "lexicons");

const PLC_URL = "https://plc.directory";

interface Publisher {
  name: string;
  did: string;
}

const publishers: Publisher[] = [
  { name: "site.standard", did: "did:plc:re3ebnp5v7ffagz6rb6xfei4" },
  { name: "pub.leaflet", did: "did:plc:btxrwcaeyodrap5mnjw2fvmz" },
  { name: "blog.pckt", did: "did:plc:revjuqmkvrw6fnkxppqtszpv" },
  { name: "app.offprint", did: "did:plc:pgjkomf37an4czloay5zeth6" },
];

/** Resolve a DID to its PDS endpoint via PLC directory. */
async function resolvePdsEndpoint(did: string): Promise<string> {
  const resp = await fetch(`${PLC_URL}/${did}`);
  if (!resp.ok) {
    throw new Error(`PLC resolution failed for ${did}: ${resp.status} ${resp.statusText}`);
  }
  const doc = await resp.json();
  const service = doc.service?.find((s: { id: string; type: string; serviceEndpoint: string }) =>
    s.id === "#atproto_pds" || s.type === "AtprotoPersonalDataServer"
  );
  if (!service) {
    throw new Error(`No PDS service found in DID document for ${did}`);
  }
  return service.serviceEndpoint;
}

/** Fetch all lexicon schema records from a publisher's PDS. */
async function fetchLexiconRecords(
  pdsEndpoint: string,
  did: string,
): Promise<{ nsid: string; value: Record<string, unknown> }[]> {
  const url = new URL(`${pdsEndpoint}/xrpc/com.atproto.repo.listRecords`);
  url.searchParams.set("repo", did);
  url.searchParams.set("collection", "com.atproto.lexicon.schema");
  url.searchParams.set("limit", "100");

  const resp = await fetch(url.toString());
  if (!resp.ok) {
    throw new Error(
      `listRecords failed for ${did} at ${pdsEndpoint}: ${resp.status} ${resp.statusText}`,
    );
  }
  const body = await resp.json();
  const records = body.records ?? [];

  return records
    .filter((r: { value?: { id?: string } }) => r.value?.id)
    .map((r: { value: Record<string, unknown> }) => ({
      nsid: r.value.id as string,
      value: r.value,
    }));
}

/** Convert an NSID to a filesystem path: site.standard.document -> site/standard/document.json */
function nsidToPath(nsid: string): string {
  const parts = nsid.split(".");
  const filename = parts.pop()! + ".json";
  return join(lexiconsDir, ...parts, filename);
}

/** Strip wrapper fields that belong to the schema record, not the schema itself. */
function stripWrapperFields(value: Record<string, unknown>): Record<string, unknown> {
  const cleaned = { ...value };
  delete cleaned["$type"];
  delete cleaned["revision"];
  return cleaned;
}

/** Check whether an NSID should be skipped (permission-set / auth records). */
function shouldSkip(nsid: string): boolean {
  return nsid.includes(".auth");
}

/** Write a lexicon JSON file with stable formatting. */
async function writeLexiconFile(
  filePath: string,
  value: Record<string, unknown>,
): Promise<boolean> {
  const json = JSON.stringify(value, null, 2) + "\n";

  // Check if file exists with identical content
  try {
    const existing = await Deno.readTextFile(filePath);
    if (existing === json) {
      return false; // no change
    }
  } catch {
    // file doesn't exist, will write
  }

  if (!args.dryRun) {
    await ensureDir(dirname(filePath));
    await Deno.writeTextFile(filePath, json);
  }
  return true;
}

// --- Main ---

console.log(`Fetching longform lexicons to ${lexiconsDir}`);
if (args.dryRun) console.log("(dry-run: no files will be written)");
console.log();

let totalWritten = 0;
let totalUnchanged = 0;
let totalSkipped = 0;
const skipped: string[] = [];
const errors: string[] = [];

for (const pub of publishers) {
  console.log(`[${pub.name}] ${pub.did}`);

  let pdsEndpoint: string;
  try {
    pdsEndpoint = await resolvePdsEndpoint(pub.did);
    if (args.verbose) console.log(`  PDS: ${pdsEndpoint}`);
  } catch (e) {
    const msg = `  ERROR resolving PDS: ${(e as Error).message}`;
    console.error(msg);
    errors.push(`[${pub.name}] ${msg}`);
    continue;
  }

  let records: { nsid: string; value: Record<string, unknown> }[];
  try {
    records = await fetchLexiconRecords(pdsEndpoint, pub.did);
  } catch (e) {
    const msg = `  ERROR fetching records: ${(e as Error).message}`;
    console.error(msg);
    errors.push(`[${pub.name}] ${msg}`);
    continue;
  }

  console.log(`  ${records.length} schema records found`);

  for (const rec of records) {
    if (shouldSkip(rec.nsid)) {
      totalSkipped++;
      skipped.push(rec.nsid);
      if (args.verbose) console.log(`  SKIP ${rec.nsid}`);
      continue;
    }

    const cleaned = stripWrapperFields(rec.value);
    const filePath = nsidToPath(rec.nsid);

    try {
      const changed = await writeLexiconFile(filePath, cleaned);
      if (changed) {
        totalWritten++;
        if (args.verbose) console.log(`  WRITE ${rec.nsid}`);
      } else {
        totalUnchanged++;
        if (args.verbose) console.log(`  OK   ${rec.nsid}`);
      }
    } catch (e) {
      const msg = `  ERROR writing ${rec.nsid}: ${(e as Error).message}`;
      console.error(msg);
      errors.push(`[${pub.name}] ${msg}`);
    }
  }
  console.log();
}

console.log("--- Summary ---");
console.log(`Written/changed: ${totalWritten}`);
console.log(`Unchanged:       ${totalUnchanged}`);
console.log(`Skipped (auth):   ${totalSkipped}`);
console.log(`Errors:           ${errors.length}`);

if (skipped.length > 0) {
  console.log(`\nSkipped NSIDs:`);
  for (const nsid of skipped) console.log(`  ${nsid}`);
}

if (errors.length > 0) {
  console.log(`\nErrors:`);
  for (const e of errors) console.log(`  ${e}`);
  Deno.exit(1);
}
