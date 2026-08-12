#!/usr/bin/env -S deno run -A

/**
 * Download a repo's CAR file from its source PDS (resolved via the DID
 * document) and import it into a garazyk PDS via com.atproto.repo.importRepo.
 */

interface Args {
  did: string;
  sourcePds?: string;
  plcUrl: string;
  targetPds: string;
  identifier?: string;
  password?: string;
  accessJwt?: string;
  out?: string;
  dryRun: boolean;
}

function usage(): never {
  console.log(`Usage: scripts/import_repo_car.ts --did DID [options]

Downloads the CAR file for a repo from its source PDS (resolved from the
DID document) and uploads it to a target garazyk PDS via
com.atproto.repo.importRepo.

Options:
  --did DID                 Repo DID to fetch and import (required)
  --source-pds URL          Skip DID resolution, fetch the CAR from this PDS directly
  --plc-url URL             PLC directory used to resolve did:plc DIDs
                              (default: PLC_URL or https://plc.directory)
  --target-pds URL          PDS to import into (default: PDS_URL or https://pds.garazyk.xyz)
  --identifier STRING       Login identifier on the target PDS (default: the DID itself)
  --password STRING         Login password on the target PDS (default: PDS_PASSWORD env)
  --access-jwt JWT          Use an existing access token instead of logging in
  --out PATH                Also save the downloaded CAR bytes to this path
  --dry-run                 Download (and optionally save) the CAR but skip the import
  -h, --help                Show this help

Examples:
  scripts/import_repo_car.ts --did did:plc:vc7f4oafdgxsihk4cry2xpze --password hunter2
  scripts/import_repo_car.ts --did did:plc:vc7f4oafdgxsihk4cry2xpze --out repo.car --dry-run
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
      case "--identifier":
        args.identifier = takeValue(argv, i++, arg);
        break;
      case "--password":
        args.password = takeValue(argv, i++, arg);
        break;
      case "--access-jwt":
        args.accessJwt = takeValue(argv, i++, arg);
        break;
      case "--out":
        args.out = takeValue(argv, i++, arg);
        break;
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
  if (!args.dryRun && !args.accessJwt && !args.password) {
    console.error(
      "--password (or PDS_PASSWORD) or --access-jwt is required unless --dry-run is set",
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

async function resolveDidDocument(
  did: string,
  plcUrl: string,
): Promise<DidDocument> {
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
  return await response.json();
}

async function resolvePdsEndpoint(
  did: string,
  plcUrl: string,
): Promise<string> {
  const doc = await resolveDidDocument(did, plcUrl);
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

async function downloadRepoCar(
  sourcePds: string,
  did: string,
): Promise<Uint8Array> {
  const url = `${
    sourcePds.replace(/\/$/, "")
  }/xrpc/com.atproto.sync.getRepo?did=${encodeURIComponent(did)}`;
  const response = await fetch(url);
  if (!response.ok) {
    console.error(
      `ERROR: getRepo from ${sourcePds} returned ${response.status}: ${await response
        .text()}`,
    );
    Deno.exit(1);
  }
  return new Uint8Array(await response.arrayBuffer());
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

async function importRepoCar(
  targetPds: string,
  accessJwt: string,
  carBytes: Uint8Array,
): Promise<unknown> {
  const response = await fetch(
    `${targetPds.replace(/\/$/, "")}/xrpc/com.atproto.repo.importRepo`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/vnd.ipld.car",
        "Content-Length": String(carBytes.byteLength),
        Authorization: `Bearer ${accessJwt}`,
      },
      body: carBytes,
    },
  );
  const text = await response.text();
  if (!response.ok) {
    console.error(
      `ERROR: importRepo on ${targetPds} returned ${response.status}: ${text}`,
    );
    Deno.exit(1);
  }
  return text ? JSON.parse(text) : {};
}

async function main() {
  const args = parseArgs(Deno.args);

  console.log(`[1/3] Resolving source PDS for ${args.did}`);
  const sourcePds = args.sourcePds ||
    await resolvePdsEndpoint(args.did, args.plcUrl);
  console.log(`  Source PDS: ${sourcePds}`);

  console.log(`\n[2/3] Downloading repo CAR`);
  const carBytes = await downloadRepoCar(sourcePds, args.did);
  console.log(`  Downloaded ${carBytes.byteLength} bytes`);

  if (args.out) {
    await Deno.writeFile(args.out, carBytes);
    console.log(`  Saved to ${args.out}`);
  }

  if (args.dryRun) {
    console.log("\n[3/3] Skipping import (--dry-run)");
    return;
  }

  console.log(`\n[3/3] Importing into ${args.targetPds}`);
  const accessJwt = args.accessJwt ||
    await createSession(
      args.targetPds,
      args.identifier || args.did,
      args.password!,
    );
  const result = await importRepoCar(args.targetPds, accessJwt, carBytes);
  console.log(`  Import result: ${JSON.stringify(result, null, 2)}`);
}

if (import.meta.main) {
  await main();
}
