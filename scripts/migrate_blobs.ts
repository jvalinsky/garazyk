#!/usr/bin/env -S deno run -A

/**
 * Migrate blob bytes after a repo CAR import (ADR 0035 B5).
 *
 * Repo CAR files never contain blob binary data: com.atproto.repo.importRepo
 * writes blocks, records, and blob *references* only. After importing a CAR
 * into the target PDS, this script completes the migration by driving the
 * upstream protocol loop:
 *
 *   1. com.atproto.repo.listMissingBlobs on the TARGET PDS (paginated)
 *      -> blobs: [{ cid, recordUri }] referenced by imported records whose
 *         bytes are not present on the target;
 *   2. com.atproto.sync.getBlob on the SOURCE PDS (public, no auth) to fetch
 *      the bytes;
 *   3. com.atproto.repo.uploadBlob on the TARGET PDS (authed) to re-upload
 *      them, verifying the returned blob ref matches the expected CID.
 *
 * Auth on the target accepts either an --access-jwt, a --refresh-jwt (the
 * BYO-DID createAccount migration tokens refresh even while the account is
 * deactivated, per ADR 0035), or --identifier/--password via createSession
 * (active accounts only — deactivated migration accounts get a 401 from
 * createSession by design).
 */

interface Args {
  did: string;
  sourcePds?: string;
  plcUrl: string;
  targetPds: string;
  accessJwt?: string;
  refreshJwt?: string;
  identifier?: string;
  password?: string;
  limit: number;
  dryRun: boolean;
}

function usage(): never {
  console.log(`Usage: scripts/migrate_blobs.ts --did DID [options]

Migrates blob bytes from the source PDS to the target PDS after a repo CAR
import. Blobs are discovered via com.atproto.repo.listMissingBlobs on the
target, fetched from the source, and re-uploaded to the target.

Options:
  --did DID                 Repo DID being migrated (required)
  --source-pds URL          Fetch blobs from this PDS directly (default:
                            resolved from the DID document, like import_repo_car.ts)
  --plc-url URL             PLC directory used to resolve did:plc DIDs
                              (default: PLC_URL or https://plc.directory)
  --target-pds URL          PDS the repo was imported into
                              (default: PDS_URL or https://pds.garazyk.xyz)
  --access-jwt JWT          Target access token (e.g. from BYO-DID createAccount)
  --refresh-jwt JWT         Target refresh token; refreshed via refreshSession
  --identifier STRING       Target login identifier (createSession; active accounts only)
  --password STRING         Target login password (default: PDS_PASSWORD env)
  --limit N                 listMissingBlobs page size (default: 500, max 1000)
  --dry-run                 List missing blobs without uploading
  -h, --help                Show this help

Examples:
  scripts/migrate_blobs.ts --did did:plc:vc7f4oafdgxsihk4cry2xpze \\
      --refresh-jwt eyJ... --target-pds https://pds.garazyk.xyz
  scripts/migrate_blobs.ts --did did:plc:abc --password hunter2 --dry-run
`);
  Deno.exit(0);
}

function takeValue(argv: string[], index: number, flag: string): string {
  const value = argv[index + 1];
  if (!value) {
    console.error(`${flag} requires a value`);
    Deno.exit(2);
  }
  return value;
}

function parseArgs(argv: string[]): Args {
  const args: Args = {
    did: "",
    plcUrl: Deno.env.get("PLC_URL") || "https://plc.directory",
    targetPds: Deno.env.get("PDS_URL") || "https://pds.garazyk.xyz",
    password: Deno.env.get("PDS_PASSWORD") || undefined,
    limit: 500,
    dryRun: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--help":
      case "-h":
        usage();
        break;
      case "--did":
        args.did = takeValue(argv, i++, arg);
        break;
      case "--source-pds":
        args.sourcePds = takeValue(argv, i++, arg);
        break;
      case "--plc-url":
        args.plcUrl = takeValue(argv, i++, arg);
        break;
      case "--target-pds":
        args.targetPds = takeValue(argv, i++, arg);
        break;
      case "--access-jwt":
        args.accessJwt = takeValue(argv, i++, arg);
        break;
      case "--refresh-jwt":
        args.refreshJwt = takeValue(argv, i++, arg);
        break;
      case "--identifier":
        args.identifier = takeValue(argv, i++, arg);
        break;
      case "--password":
        args.password = takeValue(argv, i++, arg);
        break;
      case "--limit": {
        const value = takeValue(argv, i++, arg);
        const parsed = Number.parseInt(value, 10);
        if (!Number.isInteger(parsed) || parsed < 1 || parsed > 1000) {
          console.error("--limit must be an integer between 1 and 1000");
          Deno.exit(2);
        }
        args.limit = parsed;
        break;
      }
      case "--dry-run":
        args.dryRun = true;
        break;
      default:
        console.error(`Unknown option: ${arg}`);
        Deno.exit(2);
    }
  }

  if (!args.did) {
    console.error("--did is required");
    Deno.exit(2);
  }
  if (
    !args.dryRun && !args.accessJwt && !args.refreshJwt && !args.password
  ) {
    console.error(
      "--access-jwt, --refresh-jwt, or --password (or PDS_PASSWORD) is required unless --dry-run is set",
    );
    Deno.exit(2);
  }
  return args;
}

interface DidServiceEntry {
  id?: string;
  type?: string;
  serviceEndpoint?: string;
}

interface DidDocument {
  service?: DidServiceEntry[];
}

async function resolvePdsEndpoint(
  did: string,
  plcUrl: string,
): Promise<string> {
  let url: string;
  if (did.startsWith("did:plc:")) {
    url = `${plcUrl.replace(/\/$/, "")}/${did}`;
  } else if (did.startsWith("did:web:")) {
    const domain = decodeURIComponent(did.slice("did:web:".length)).replace(
      /:/g,
      "/",
    );
    url = `https://${domain}/.well-known/did.json`;
  } else {
    console.error(`ERROR: Unsupported DID method: ${did}`);
    Deno.exit(1);
  }

  const response = await fetch(url);
  if (!response.ok) {
    console.error(
      `ERROR: Failed to resolve ${did} via ${url}: ${response.status} ${await response
        .text()}`,
    );
    Deno.exit(1);
  }
  const doc: DidDocument = await response.json();
  const pdsService = doc.service?.find((s) =>
    s.id === "#atproto_pds" || s.type === "AtprotoPersonalDataServer"
  );
  if (!pdsService?.serviceEndpoint) {
    console.error(
      `ERROR: No AtprotoPersonalDataServer service found in DID document for ${did}`,
    );
    Deno.exit(1);
  }
  return pdsService.serviceEndpoint;
}

async function createSession(
  pdsUrl: string,
  identifier: string,
  password: string,
): Promise<string> {
  const response = await fetch(
    `${pdsUrl.replace(/\/$/, "")}/xrpc/com.atproto.server.createSession`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ identifier, password }),
    },
  );
  const text = await response.text();
  if (!response.ok) {
    console.error(
      `ERROR: createSession on ${pdsUrl} returned ${response.status}: ${text}`,
    );
    Deno.exit(1);
  }
  const session = JSON.parse(text);
  if (!session.accessJwt) {
    console.error(`ERROR: No accessJwt in createSession response: ${text}`);
    Deno.exit(1);
  }
  return session.accessJwt;
}

async function refreshSession(
  pdsUrl: string,
  refreshJwt: string,
): Promise<{ accessJwt: string; refreshJwt: string }> {
  const response = await fetch(
    `${pdsUrl.replace(/\/$/, "")}/xrpc/com.atproto.server.refreshSession`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${refreshJwt}` },
    },
  );
  const text = await response.text();
  if (!response.ok) {
    console.error(
      `ERROR: refreshSession on ${pdsUrl} returned ${response.status}: ${text}`,
    );
    Deno.exit(1);
  }
  const session = JSON.parse(text);
  if (!session.accessJwt) {
    console.error(`ERROR: No accessJwt in refreshSession response: ${text}`);
    Deno.exit(1);
  }
  return {
    accessJwt: session.accessJwt,
    refreshJwt: session.refreshJwt ?? refreshJwt,
  };
}

interface MissingBlob {
  cid: string;
  recordUri: string;
}

async function listMissingBlobs(
  targetPds: string,
  accessJwt: string,
  did: string,
  limit: number,
  cursor?: string,
): Promise<{ blobs: MissingBlob[]; cursor?: string }> {
  const params = new URLSearchParams({ limit: String(limit) });
  if (cursor) params.set("cursor", cursor);
  const response = await fetch(
    `${targetPds.replace(/\/$/, "")}/xrpc/com.atproto.repo.listMissingBlobs?${
      params.toString()
    }`,
    { headers: { Authorization: `Bearer ${accessJwt}` } },
  );
  const text = await response.text();
  if (!response.ok) {
    console.error(
      `ERROR: listMissingBlobs on ${targetPds} returned ${response.status}: ${text}`,
    );
    Deno.exit(1);
  }
  const body = JSON.parse(text);
  const blobs: MissingBlob[] = (body.blobs ?? []).filter(
    (b: unknown): b is MissingBlob =>
      typeof (b as MissingBlob).cid === "string" &&
      typeof (b as MissingBlob).recordUri === "string",
  );
  return { blobs, cursor: body.cursor };
}

async function fetchBlob(
  sourcePds: string,
  did: string,
  cid: string,
): Promise<{ bytes: Uint8Array; contentType: string }> {
  const url = `${sourcePds.replace(/\/$/, "")}/xrpc/com.atproto.sync.getBlob?did=${
    encodeURIComponent(did)
  }&cid=${encodeURIComponent(cid)}`;
  const response = await fetch(url);
  if (!response.ok) {
    console.error(
      `ERROR: getBlob ${cid} from ${sourcePds} returned ${response.status}: ${await response
        .text()}`,
    );
    return { bytes: new Uint8Array(0), contentType: "application/octet-stream" };
  }
  return {
    bytes: new Uint8Array(await response.arrayBuffer()),
    contentType: response.headers.get("content-type") ||
      "application/octet-stream",
  };
}

async function uploadBlob(
  targetPds: string,
  accessJwt: string,
  bytes: Uint8Array,
  contentType: string,
): Promise<string> {
  const response = await fetch(
    `${targetPds.replace(/\/$/, "")}/xrpc/com.atproto.repo.uploadBlob`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessJwt}`,
        "Content-Type": contentType,
      },
      body: bytes,
    },
  );
  const text = await response.text();
  if (!response.ok) {
    console.error(
      `ERROR: uploadBlob on ${targetPds} returned ${response.status}: ${text}`,
    );
    return "";
  }
  const body = JSON.parse(text);
  return body?.blob?.ref?.$link ?? "";
}

async function main() {
  const args = parseArgs(Deno.args);
  const targetPds = args.targetPds.replace(/\/$/, "");

  console.log(`[1/4] Resolving source PDS for ${args.did}`);
  const sourcePds = args.sourcePds ||
    await resolvePdsEndpoint(args.did, args.plcUrl);
  console.log(`  Source PDS: ${sourcePds}`);
  console.log(`  Target PDS: ${targetPds}`);

  console.log("\n[2/4] Authenticating to target PDS");
  let accessJwt = args.accessJwt ?? "";
  let refreshJwt = args.refreshJwt ?? "";
  if (!accessJwt && refreshJwt) {
    const refreshed = await refreshSession(targetPds, refreshJwt);
    accessJwt = refreshed.accessJwt;
    refreshJwt = refreshed.refreshJwt;
    console.log("  Refreshed access token from --refresh-jwt");
  } else if (!accessJwt && args.password) {
    accessJwt = await createSession(
      targetPds,
      args.identifier || args.did,
      args.password,
    );
    console.log("  createSession succeeded");
  } else if (!accessJwt) {
    console.log("  Using --access-jwt");
  }

  let totalMissing = 0;
  let uploaded = 0;
  let failed = 0;
  let cursor: string | undefined;
  let page = 0;

  console.log("\n[3/4] Enumerating missing blobs");
  do {
    page++;
    const { blobs, cursor: nextCursor } = await listMissingBlobs(
      targetPds,
      accessJwt,
      args.did,
      args.limit,
      cursor,
    );
    cursor = nextCursor;
    if (page === 1 && blobs.length === 0) {
      console.log("  No missing blobs reported by the target");
    } else if (blobs.length > 0) {
      console.log(
        `  Page ${page}: ${blobs.length} missing blob(s)` +
          (cursor ? " (more pages follow)" : ""),
      );
    }
    totalMissing += blobs.length;

    for (const blob of blobs) {
      if (args.dryRun) {
        console.log(`  [dry-run] would migrate ${blob.cid} (${blob.recordUri})`);
        continue;
      }
      const { bytes, contentType } = await fetchBlob(sourcePds, args.did, blob.cid);
      if (bytes.byteLength === 0) {
        failed++;
        continue;
      }
      const gotCid = await uploadBlob(targetPds, accessJwt, bytes, contentType);
      if (gotCid === blob.cid) {
        uploaded++;
        console.log(`  uploaded ${blob.cid} (${bytes.byteLength} bytes)`);
      } else {
        failed++;
        console.error(
          `  FAIL ${blob.cid}: target returned ${gotCid || "(no ref)"} (expected ${blob.cid})`,
        );
      }
    }
  } while (cursor);

  console.log("\n[4/4] Summary");
  if (args.dryRun) {
    console.log(`  ${totalMissing} missing blob(s) would be migrated (--dry-run)`);
    return;
  }
  console.log(`  missing: ${totalMissing}, uploaded: ${uploaded}, failed: ${failed}`);
  if (failed > 0) {
    console.error(`WARNING: ${failed} blob(s) failed to migrate`);
    Deno.exit(1);
  }
  if (totalMissing === 0) {
    console.log("  Nothing to do — the import left no missing blob references.");
  }
}

if (import.meta.main) {
  await main();
}
