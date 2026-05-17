#!/usr/bin/env -S deno run -A
import { XrpcClient } from "@garazyk/gruszka";
import {
  generateInviteCode,
  generatePassword,
} from "@garazyk/gruszka/account-ops";
import {
  getExistingInviteCodeViaSsh,
  insertInviteCodeViaSsh,
} from "@garazyk/hamownia/invite-code";

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
        break;
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

async function main() {
  const args = parseArgs(Deno.args);
  const handlePrefix = args.handle.split(".")[0];
  const email = args.email || `${handlePrefix}@garazyk.xyz`;
  const password = args.password || generatePassword();
  const displayName = args.displayName ||
    `${handlePrefix.charAt(0).toUpperCase()}${handlePrefix.slice(1)}`;

  const client = new XrpcClient(args.pdsUrl);

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
    await insertInviteCodeViaSsh(
      args.sshHost,
      args.dbPath,
      inviteCode,
      args.inviteCodeDid,
    );
    console.log(`  Generated invite code: ${inviteCode}`);
  }

  console.log("\n[2/5] Creating account");
  const result = await client.api.com.atproto.server.createAccount({
    email,
    handle: args.handle,
    password,
    inviteCode,
  });
  const did = result.did;
  let accessJwt = result.accessJwt;

  console.log(`  DID:  ${did}`);
  console.log(`  Handle: ${args.handle}`);

  if (!accessJwt) {
    console.log("\n[2.5/5] Creating session (no JWT from createAccount)");
    const session = await client.api.com.atproto.server.createSession({
      identifier: args.handle,
      password,
    });
    accessJwt = session.accessJwt;
  }

  console.log("\n[3/5] Setting profile");
  await client.api.com.atproto.repo.createRecord({
    repo: did,
    collection: "app.bsky.actor.profile",
    rkey: "self",
    record: {
      "$type": "app.bsky.actor.profile",
      displayName,
      description: args.description,
      createdAt: new Date().toISOString(),
    },
  }, accessJwt);
  console.log(`  Profile set: ${displayName}`);

  if (args.posts.length > 0) {
    console.log(`\n[4/5] Creating ${args.posts.length} post(s)`);
    for (const text of args.posts) {
      await client.api.com.atproto.repo.createRecord({
        repo: did,
        collection: "app.bsky.feed.post",
        record: {
          "$type": "app.bsky.feed.post",
          text,
          createdAt: new Date().toISOString(),
        },
      }, accessJwt);
      console.log(`  Post: ${text.slice(0, 50)}...`);
    }
  }

  if (args.requestCrawl) {
    console.log("\n[5/5] Requesting relay crawl");
    const relayClient = new XrpcClient(args.relayUrl);
    await relayClient.api.com.atproto.sync.requestCrawl({
      hostname: new URL(args.pdsUrl).hostname,
    });
  }

  console.log(`\nAccount created successfully!`);
}

if (import.meta.main) {
  await main();
}
