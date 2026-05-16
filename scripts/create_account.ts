#!/usr/bin/env -S deno run -A

const INVITE_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

interface Args {
  pdsUrl: string;
  sshHost: string;
  dbPath: string;
  handle: string;
  email?: string;
  password?: string;
  displayName?: string;
  description?: string;
  posts: string[];
  requestCrawl: boolean;
  relayUrl: string;
  inviteCodeDid: string;
  reuseInviteCode: boolean;
}

function usage(): never {
  console.log(`Usage: scripts/create_account.ts --handle HANDLE [options]

Options:
  --pds-url URL             PDS base URL (default: PDS_URL or https://pds.garazyk.xyz)
  --ssh-host HOST           SSH host for invite-code DB access
  --db-path PATH            Remote service.db path
  --email EMAIL             Account email (default: <handle-prefix>@garazyk.xyz)
  --password PASSWORD       Password (default: generated)
  --display-name NAME       Profile display name
  --description TEXT        Profile description
  --post TEXT               Post to create; can be repeated
  --request-crawl           Request relay crawl after account creation
  --relay-url URL           Relay URL (default: RELAY_URL or https://bsky.network)
  --invite-code-did DID     DID associated with generated invite code
  --reuse-invite-code       Reuse an existing unused invite code if available
`);
  Deno.exit(2);
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
    pdsUrl: Deno.env.get("PDS_URL") || "https://pds.garazyk.xyz",
    sshHost: Deno.env.get("SSH_HOST") || "",
    dbPath: Deno.env.get("PDS_DB_PATH") || "~/pds-data/service/service.db",
    handle: "",
    posts: [],
    requestCrawl: false,
    relayUrl: Deno.env.get("RELAY_URL") || "https://bsky.network",
    inviteCodeDid: "did:plc:system",
    reuseInviteCode: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--help":
      case "-h":
        usage();
      case "--pds-url":
        args.pdsUrl = takeValue(argv, i++, arg);
        break;
      case "--ssh-host":
        args.sshHost = takeValue(argv, i++, arg);
        break;
      case "--db-path":
        args.dbPath = takeValue(argv, i++, arg);
        break;
      case "--handle":
        args.handle = takeValue(argv, i++, arg);
        break;
      case "--email":
        args.email = takeValue(argv, i++, arg);
        break;
      case "--password":
        args.password = takeValue(argv, i++, arg);
        break;
      case "--display-name":
        args.displayName = takeValue(argv, i++, arg);
        break;
      case "--description":
        args.description = takeValue(argv, i++, arg);
        break;
      case "--post":
        args.posts.push(takeValue(argv, i++, arg));
        break;
      case "--request-crawl":
        args.requestCrawl = true;
        break;
      case "--relay-url":
        args.relayUrl = takeValue(argv, i++, arg);
        break;
      case "--invite-code-did":
        args.inviteCodeDid = takeValue(argv, i++, arg);
        break;
      case "--reuse-invite-code":
        args.reuseInviteCode = true;
        break;
      default:
        console.error(`Unknown option: ${arg}`);
        Deno.exit(2);
    }
  }

  if (!args.handle) {
    console.error("--handle is required");
    Deno.exit(2);
  }
  return args;
}

function randomString(alphabet: string, length: number): string {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return [...bytes].map((byte) => alphabet[byte % alphabet.length]).join("");
}

function generateInviteCode(groups = 4, length = 5): string {
  return Array.from({ length: groups }, () => randomString(INVITE_ALPHABET, length)).join("-");
}

function generatePassword(length = 24): string {
  return randomString("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", length);
}

async function commandWithInput(command: string, args: string[], input: string) {
  const child = new Deno.Command(command, {
    args,
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(input));
  await writer.close();
  const output = await child.output();
  return {
    code: output.code,
    stdout: new TextDecoder().decode(output.stdout),
    stderr: new TextDecoder().decode(output.stderr),
  };
}

async function insertInviteCodeViaSsh(
  sshHost: string,
  dbPath: string,
  code: string,
  accountDid: string,
  maxUses = 1,
): Promise<void> {
  const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const id = crypto.randomUUID();
  const sql =
    `INSERT INTO invite_codes (id, code, account_did, created_at, uses, max_uses, disabled) VALUES ('${id}', '${code}', '${accountDid}', '${now}', 0, ${maxUses}, 0);`;
  const result = await commandWithInput("ssh", ["-T", sshHost, "sqlite3", dbPath], sql);
  if (result.code !== 0) {
    console.error(`ERROR: Failed to insert invite code via SSH: ${result.stderr.trim()}`);
    Deno.exit(1);
  }
}

async function getExistingInviteCodeViaSsh(
  sshHost: string,
  dbPath: string,
): Promise<string | null> {
  const sql = "SELECT code FROM invite_codes WHERE disabled = 0 AND uses < max_uses LIMIT 1;";
  const result = await commandWithInput("ssh", ["-T", sshHost, "sqlite3", dbPath], sql);
  if (result.code !== 0) {
    console.error(`ERROR: Failed to query invite codes via SSH: ${result.stderr.trim()}`);
    Deno.exit(1);
  }
  const code = result.stdout.trim();
  return code || null;
}

async function xrpcPost(
  baseUrl: string,
  method: string,
  body: Record<string, unknown>,
  authToken?: string,
) {
  const response = await fetch(`${baseUrl.replace(/\/$/, "")}/xrpc/${method}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok) {
    console.error(`ERROR: XRPC ${method} returned ${response.status}: ${text}`);
    Deno.exit(1);
  }
  return payload;
}

async function createAccount(args: Args, email: string, password: string, inviteCode: string) {
  return await xrpcPost(args.pdsUrl, "com.atproto.server.createAccount", {
    email,
    handle: args.handle,
    password,
    inviteCode,
  });
}

async function createSession(pdsUrl: string, identifier: string, password: string) {
  return await xrpcPost(pdsUrl, "com.atproto.server.createSession", { identifier, password });
}

async function updateProfile(
  pdsUrl: string,
  accessJwt: string,
  did: string,
  displayName: string,
  description?: string,
) {
  const record: Record<string, unknown> = {
    "$type": "app.bsky.actor.profile",
    displayName,
    createdAt: new Date().toISOString(),
  };
  if (description) record.description = description;
  return await xrpcPost(pdsUrl, "com.atproto.repo.createRecord", {
    repo: did,
    collection: "app.bsky.actor.profile",
    rkey: "self",
    record,
  }, accessJwt);
}

async function createPost(pdsUrl: string, accessJwt: string, did: string, text: string) {
  return await xrpcPost(pdsUrl, "com.atproto.repo.createRecord", {
    repo: did,
    collection: "app.bsky.feed.post",
    record: {
      "$type": "app.bsky.feed.post",
      text,
      createdAt: new Date().toISOString(),
    },
  }, accessJwt);
}

async function requestCrawl(relayUrl: string, hostname: string | null) {
  if (!hostname) return;
  try {
    await xrpcPost(relayUrl, "com.atproto.sync.requestCrawl", { hostname });
    console.log(`  Crawl requested from ${relayUrl}`);
  } catch {
    console.log("  WARNING: Crawl request failed (non-fatal)");
  }
}

async function main() {
  const args = parseArgs(Deno.args);
  const handlePrefix = args.handle.split(".")[0];
  const email = args.email || `${handlePrefix}@garazyk.xyz`;
  const password = args.password || generatePassword();
  const displayName = args.displayName ||
    `${handlePrefix.charAt(0).toUpperCase()}${handlePrefix.slice(1)}`;

  console.log("═══ Garazyk Account Creator ═══");
  console.log(`  PDS:        ${args.pdsUrl}`);
  console.log(`  SSH host:   ${args.sshHost}`);
  console.log(`  Handle:     ${args.handle}`);
  console.log(`  Email:      ${email}`);
  console.log(`  Display:    ${displayName}`);
  console.log();

  console.log("[1/5] Invite code");
  let inviteCode: string | null = null;
  if (args.reuseInviteCode) {
    inviteCode = await getExistingInviteCodeViaSsh(args.sshHost, args.dbPath);
    if (inviteCode) {
      console.log(`  Reusing existing invite code: ${inviteCode}`);
    } else {
      console.log("  No unused invite codes found, generating a new one");
    }
  }
  if (!inviteCode) {
    inviteCode = generateInviteCode();
    await insertInviteCodeViaSsh(args.sshHost, args.dbPath, inviteCode, args.inviteCodeDid);
    console.log(`  Generated invite code: ${inviteCode}`);
  }

  console.log("\n[2/5] Creating account");
  const result = await createAccount(args, email, password, inviteCode);
  const did = result.did;
  let accessJwt = result.accessJwt;
  if (!did) {
    console.error(`  ERROR: No DID returned from createAccount: ${JSON.stringify(result)}`);
    Deno.exit(1);
  }
  console.log(`  DID:  ${did}`);
  console.log(`  Handle: ${args.handle}`);
  console.log(accessJwt ? `  Access JWT: ${accessJwt.slice(0, 40)}...` : "  No access JWT");

  if (!accessJwt) {
    console.log("\n[2.5/5] Creating session (no JWT from createAccount)");
    const session = await createSession(args.pdsUrl, args.handle, password);
    accessJwt = session.accessJwt;
    if (!accessJwt) {
      console.error("  ERROR: No access JWT from createSession");
      Deno.exit(1);
    }
    console.log(`  Access JWT: ${accessJwt.slice(0, 40)}...`);
  }

  console.log("\n[3/5] Setting profile");
  await updateProfile(args.pdsUrl, accessJwt, did, displayName, args.description);
  console.log(`  Profile set: ${displayName}`);
  if (args.description) console.log(`  Bio: ${args.description.slice(0, 60)}...`);

  if (args.posts.length > 0) {
    console.log(`\n[4/5] Creating ${args.posts.length} post(s)`);
    for (let i = 0; i < args.posts.length; i++) {
      const text = args.posts[i];
      const postResult = await createPost(args.pdsUrl, accessJwt, did, text);
      console.log(`  Post ${i + 1}: ${text.slice(0, 50)}${text.length > 50 ? "..." : ""}`);
      console.log(`    URI: ${postResult.uri ?? "unknown"}`);
    }
  } else {
    console.log("\n[4/5] No posts to create (use --post to add posts)");
  }

  if (args.requestCrawl) {
    console.log("\n[5/5] Requesting relay crawl");
    await requestCrawl(args.relayUrl, new URL(args.pdsUrl).hostname);
  } else {
    console.log("\n[5/5] Skipping relay crawl (use --request-crawl to enable)");
  }

  console.log(`\n${"═".repeat(40)}`);
  console.log("  Account created successfully!");
  console.log(`  Handle:   ${args.handle}`);
  console.log(`  DID:      ${did}`);
  console.log(`  Email:    ${email}`);
  console.log(`  Password: ${password}`);
  console.log("═".repeat(40));
}

if (import.meta.main) {
  await main();
}
