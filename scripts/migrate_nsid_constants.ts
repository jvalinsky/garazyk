#!/usr/bin/env -S deno run -A
/**
 * Migrates XRPC route pack files from convenience methods to generated NSID constants.
 *
 * Pattern: [dispatcher registerComAtprotoServerDescribeServer:^{...}]
 *       → [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_describeServer handler:^{...}]
 *
 * Dry-run: deno run -A scripts/migrate_nsid_constants.ts --dry-run
 * Apply:   deno run -A scripts/migrate_nsid_constants.ts
 */

const GENERATED_HEADER = "Garazyk/Sources/Network/Generated/GZXrpcNSID.h";
const IMPORT_LINE = '#import "Network/Generated/GZXrpcNSID.h"';
const ROUTE_PACK_DIR = "Garazyk/Sources/Network";

interface Mapping {
  /** e.g. "registerComAtprotoServerDescribeServer" */
  convenienceName: string;
  /** e.g. "com.atproto.server.describeServer" */
  nsid: string;
  /** e.g. "kGZXrpcNSID_com_atproto_server_describeServer" */
  constantName: string;
}

/**
 * Parse the generated header to extract all NSID constants.
 * Each looks like: extern NSString * const kGZXrpcNSID_app_bsky_actor_getProfile;
 */
function parseConstants(headerPath: string): Map<string, Mapping> {
  const content = Deno.readTextFileSync(headerPath);
  const lines = content.split("\n");

  const map = new Map<string, Mapping>();

  for (const line of lines) {
    // Match: extern NSString * const kGZXrpcNSID_com_atproto_server_describeServer;
    const m = line.match(
      /^extern\s+NSString\s+\*\s+const\s+(kGZXrpcNSID_\S+);/
    );
    if (!m) continue;

    const constantName = m[1];
    // Derive NSID from constant: kGZXrpcNSID_com_atproto_server_describeServer → com.atproto.server.describeServer
    const nsid = constantName.slice("kGZXrpcNSID_".length).replace(/_/g, ".");

    // Derive convenience method name from NSID
    const segments = nsid.split(".");
    const camelSegments = segments.map((s) => s[0].toUpperCase() + s.slice(1));
    const convenienceName = "register" + camelSegments.join("");

    map.set(convenienceName, { convenienceName, nsid, constantName });
  }

  return map;
}

/**
 * Replace all convenience method calls in a file's content.
 */
function migrateContent(
  content: string,
  map: Map<string, Mapping>
): { content: string; changes: number } {
  let changes = 0;
  let migrated = content;

  for (const [convenienceName, mapping] of map) {
    // Match: [dispatcher registerXxx:HANDLER]
    // The HANDLER can be ^(params) { ... } or a variable name like upsertRecordHandler
    // We need to replace "registerXxx:" with "registerMethod:kConstantName handler:"
    const pattern = new RegExp(
      `\\b${escapeRegExp(convenienceName)}:`,
      "g"
    );

    let count = 0;
    migrated = migrated.replace(pattern, () => {
      count++;
      return `registerMethod:${mapping.constantName} handler:`;
    });
    changes += count;
  }

  return { content: migrated, changes };
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Ensure the file imports the generated header.
 */
function ensureImport(content: string, filePath: string): string {
  if (content.includes(IMPORT_LINE)) return content;

  // Find the last #import line and add after it
  const lines = content.split("\n");
  let lastImportIdx = -1;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim().startsWith("#import ")) {
      lastImportIdx = i;
    }
  }

  if (lastImportIdx >= 0) {
    lines.splice(lastImportIdx + 1, 0, IMPORT_LINE);
  } else {
    // No imports? Insert after SPDX header if present
    let insertIdx = 0;
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith("// SPDX")) insertIdx = i + 1;
    }
    lines.splice(insertIdx + 1, 0, IMPORT_LINE);
  }

  return lines.join("\n");
}

// ─── Main ───────────────────────────────────────────────────────────────────

const args = Deno.args;
const dryRun = args.includes("--dry-run");

const map = parseConstants(GENERATED_HEADER);
console.log(`Parsed ${map.size} NSID constants from ${GENERATED_HEADER}`);

// Find all route pack files
const routePackFiles: string[] = [];
for (const entry of Deno.readDirSync(ROUTE_PACK_DIR)) {
  if (entry.isFile && entry.name.match(/^Xrpc.*Pack\.m$/)) {
    routePackFiles.push(`${ROUTE_PACK_DIR}/${entry.name}`);
  }
}
routePackFiles.sort();

let totalChanges = 0;
let totalFiles = 0;

for (const filePath of routePackFiles) {
  const original = Deno.readTextFileSync(filePath);
  let content = original;

  // Ensure import
  content = ensureImport(content, filePath);

  // Migrate convenience methods
  const { content: migrated, changes } = migrateContent(content, map);

  if (changes > 0 || migrated !== original) {
    totalChanges += changes;
    totalFiles++;

    if (dryRun) {
      console.log(
        `[DRY-RUN] ${filePath}: would make ${changes} replacement(s)`
      );
    } else {
      Deno.writeTextFileSync(filePath, migrated);
      console.log(`[MIGRATED] ${filePath}: ${changes} replacement(s)`);
    }
  }
}

const mode = dryRun ? "dry-run" : "migrated";
console.log(
  `\nDone (${mode}): ${totalFiles} file(s), ${totalChanges} total replacement(s)`
);

if (dryRun) {
  console.log("Run without --dry-run to apply changes.");
}
