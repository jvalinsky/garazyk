#!/usr/bin/env -S deno run -A
/**
 * Migrates XRPC route pack files from registerMethod:@"nsid" string literals
 * to generated NSID constants.
 *
 * Pattern: [dispatcher registerMethod:@"com.atproto.server.describeServer"
 *       →  [dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_describeServer
 *
 * Dry-run: deno run -A scripts/migrate_nsid_strings.ts --dry-run
 * Apply:   deno run -A scripts/migrate_nsid_strings.ts
 */

const GENERATED_HEADER = "Garazyk/Sources/Network/Generated/GZXrpcNSID.h";
const IMPORT_LINE = '#import "Network/Generated/GZXrpcNSID.h"';

// All source dirs with XRPC route pack files
const SOURCE_DIRS = [
  "Garazyk/Sources/Network",
  "Garazyk/Sources/Germ/Server",
  "Garazyk/Sources/Video",
];

/**
 * Parse NSID constants from the generated header.
 * Returns Map<nsid_string, constant_name>
 * e.g., "com.atproto.server.describeServer" → "kGZXrpcNSID_com_atproto_server_describeServer"
 */
function parseConstants(headerPath: string): Map<string, string> {
  const content = Deno.readTextFileSync(headerPath);
  const lines = content.split("\n");
  const map = new Map<string, string>();

  for (const line of lines) {
    const m = line.match(
      /^extern\s+NSString\s+\*\s+const\s+(kGZXrpcNSID_(\S+));/
    );
    if (!m) continue;
    const constantName = m[1];
    const nsid = m[2].replace(/_/g, ".");
    map.set(nsid, constantName);
  }

  return map;
}

/**
 * Replace registerMethod:@"nsid" with registerMethod:kConstantName in content.
 */
function migrateStringLiterals(
  content: string,
  nsidToConstant: Map<string, string>
): { content: string; changes: number } {
  let changes = 0;
  let migrated = content;

  // Sort NSIDs by length descending so longer matches are tried first
  // (e.g., "app.bsky.unspecced.getSomethingLong" before "app.bsky.unspecced.getSomething")
  const sortedNsids = [...nsidToConstant.keys()].sort((a, b) => b.length - a.length);

  for (const nsid of sortedNsids) {
    const constant = nsidToConstant.get(nsid)!;
    // Escape the NSID for regex
    const escapedNsid = nsid.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    // Match: registerMethod:@"NSID"
    const pattern = new RegExp(
      `(registerMethod:)@"${escapedNsid}"`,
      "g"
    );

    let count = 0;
    migrated = migrated.replace(pattern, (_full, prefix) => {
      count++;
      return `${prefix}${constant}`;
    });
    changes += count;
  }

  return { content: migrated, changes };
}

/**
 * Ensure the file imports the generated header.
 */
function ensureImport(content: string): string {
  if (content.includes(IMPORT_LINE)) return content;

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

const nsidToConstant = parseConstants(GENERATED_HEADER);
console.log(`Parsed ${nsidToConstant.size} NSID constants from ${GENERATED_HEADER}`);

// Find all route pack files and any other .m files with registerMethod
const allFiles: string[] = [];
for (const dir of SOURCE_DIRS) {
  try {
    for (const entry of Deno.readDirSync(dir)) {
      if (entry.isFile && entry.name.endsWith(".m")) {
        allFiles.push(`${dir}/${entry.name}`);
      }
    }
  } catch {
    // Directory may not exist
  }
}
allFiles.sort();

let totalChanges = 0;
let totalFiles = 0;

for (const filePath of allFiles) {
  const original = Deno.readTextFileSync(filePath);

  // Skip files that don't have registerMethod calls
  if (!original.includes("registerMethod:@")) continue;

  let content = original;
  content = ensureImport(content);

  const { content: migrated, changes } = migrateStringLiterals(content, nsidToConstant);

  if (changes > 0) {
    totalChanges += changes;
    totalFiles++;

    if (dryRun) {
      console.log(`[DRY-RUN] ${filePath}: ${changes} replacement(s)`);
    } else {
      Deno.writeTextFileSync(filePath, migrated);
      console.log(`[MIGRATED] ${filePath}: ${changes} replacement(s)`);
    }
  }
}

const mode = dryRun ? "dry-run" : "migrated";
console.log(`\nDone (${mode}): ${totalFiles} file(s), ${totalChanges} total replacement(s)`);

if (dryRun) {
  console.log("Run without --dry-run to apply changes.");
}
