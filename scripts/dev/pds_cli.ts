#!/usr/bin/env -S deno run -A

let jsonOutput = ["1", "true", "yes"].includes((Deno.env.get("PDS_CLI_JSON") || "").toLowerCase());
let noColor = false;
let useColor = false;

const pdsUrl = Deno.env.get("PDS_URL") || "http://localhost:2583";
const repoRoot = await (async () => {
  const output = await new Deno.Command("git", {
    args: ["rev-parse", "--show-toplevel"],
    stdout: "piped",
    stderr: "null",
  }).output();
  return new TextDecoder().decode(output.stdout).trim() ||
    new URL("../..", import.meta.url).pathname;
})();
const dataDir = Deno.env.get("PDS_DATA_DIR") || `${repoRoot}/data`;
const binPath = Deno.env.get("PDS_BIN") || `${repoRoot}/build/bin/kaszlak`;

function stripWrapperFlags(argv: string[]): string[] {
  const copy = [...argv];
  while (copy.length > 0) {
    if (copy[0] === "--json" || copy[0] === "-j") {
      jsonOutput = true;
      copy.shift();
    } else if (copy[0] === "--no-color") {
      noColor = true;
      copy.shift();
    } else {
      break;
    }
  }
  return copy;
}

function configureOutput() {
  useColor = !Deno.env.get("NO_COLOR") && !noColor && !jsonOutput && Deno.stdout.isTerminal();
}

const colors = {
  green: "\x1b[92m",
  blue: "\x1b[94m",
  red: "\x1b[91m",
  reset: "\x1b[0m",
};

function printJson(kind: string, message: string, extra: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ kind, message, ...extra }));
}

function printSuccess(message: string) {
  if (jsonOutput) return printJson("ok", message);
  console.log(useColor ? `${colors.green}OK: ${message}${colors.reset}` : `OK: ${message}`);
}

function printInfo(message: string) {
  if (jsonOutput) return printJson("info", message);
  console.log(useColor ? `${colors.blue}${message}${colors.reset}` : message);
}

function printError(message: string, extra: Record<string, unknown> = {}) {
  if (jsonOutput) return printJson("error", message, extra);
  console.error(useColor ? `${colors.red}Error: ${message}${colors.reset}` : `Error: ${message}`);
}

function takeValue(argv: string[], index: number, flag: string): string {
  const value = argv[index + 1];
  if (!value) {
    printError(`${flag} requires a value`);
    Deno.exit(2);
  }
  return value;
}

async function runKaszlak(args: string[]): Promise<number> {
  if (args.length === 0) {
    printError("Internal error: empty kaszlak argv");
    return 1;
  }
  try {
    await Deno.stat(binPath);
  } catch {
    printError(`Binary not found at: ${binPath}`);
    printInfo("Build the project first or set PDS_BIN.");
    return 1;
  }

  const [subcommand, ...tail] = args;
  const cmd = [
    subcommand,
    "--verbose",
    "--data-dir",
    dataDir,
    "--config",
    "/tmp/missing_cli_config.json",
    ...tail,
  ];
  const output = await new Deno.Command(binPath, {
    args: cmd,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const stdout = new TextDecoder().decode(output.stdout);
  const stderr = new TextDecoder().decode(output.stderr);
  if (output.code !== 0) {
    printError("kaszlak command failed", {
      command: [binPath, ...cmd].join(" "),
      stderr: stderr.trim(),
      exit_code: output.code,
    });
    if (!jsonOutput && stdout) console.log(stdout);
    return output.code;
  }
  if (stdout) console.log(stdout.trimEnd());
  return 0;
}

async function xrpcPost(method: string, body: Record<string, unknown>, token?: string) {
  const response = await fetch(`${pdsUrl}/xrpc/${method}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok) {
    printError(`XRPC ${method} failed: ${text}`, { status_code: response.status });
    return null;
  }
  return payload;
}

async function login(handle: string, password: string) {
  printInfo(`Logging in as ${handle}...`);
  try {
    return await xrpcPost("com.atproto.server.createSession", { identifier: handle, password });
  } catch {
    printError(`Could not connect to PDS at ${pdsUrl}`);
    return null;
  }
}

async function createRecord(
  session: Record<string, string>,
  collection: string,
  record: Record<string, unknown>,
) {
  return await xrpcPost("com.atproto.repo.createRecord", {
    repo: session.did,
    collection,
    record,
  }, session.accessJwt);
}

async function handleAccountCreate(argv: string[]): Promise<number> {
  const handle = argv[0];
  const email = argv[1];
  let password = Deno.env.get("PDS_CREATE_ACCOUNT_PASSWORD") || "";
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--password") password = takeValue(argv, i++, argv[i]);
    else {
      printError(`Unexpected argument: ${argv[i]}`);
      return 2;
    }
  }
  if (!handle || !email) {
    printError("Usage: account create HANDLE EMAIL [--password PASSWORD]");
    return 2;
  }
  if (!password) {
    printError("Missing password: use --password or set PDS_CREATE_ACCOUNT_PASSWORD.");
    return 2;
  }
  printInfo(`Creating account for ${handle}...`);
  const rc = await runKaszlak([
    "account",
    "create",
    "--email",
    email,
    "--handle",
    handle,
    "--password",
    password,
  ]);
  if (rc === 0) printSuccess(`Account ${handle} created successfully.`);
  else printError("Failed to create account.", { exit_code: rc });
  return rc;
}

async function handlePostCreate(argv: string[]): Promise<number> {
  const handle = argv[0];
  const text = argv[1];
  let password = Deno.env.get("PDS_POST_PASSWORD") || "";
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--password") password = takeValue(argv, i++, argv[i]);
    else {
      printError(`Unexpected argument: ${argv[i]}`);
      return 2;
    }
  }
  if (!handle || !text) {
    printError("Usage: post create HANDLE TEXT [--password PASSWORD]");
    return 2;
  }
  if (!password) {
    printError("Missing password: use --password or set PDS_POST_PASSWORD.");
    return 2;
  }
  const session = await login(handle, password);
  if (!session) return 1;
  const result = await createRecord(session, "app.bsky.feed.post", {
    "$type": "app.bsky.feed.post",
    text,
    createdAt: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
  });
  if (!result) return 1;
  printSuccess(`Post created! URI: ${result.uri}`);
  if (jsonOutput) printJson("result", "post", { uri: result.uri, cid: result.cid });
  else console.log(`CID: ${result.cid}`);
  return 0;
}

async function handleProfileUpdate(argv: string[]): Promise<number> {
  const handle = argv[0];
  let name = "";
  let description = "";
  let password = Deno.env.get("PDS_POST_PASSWORD") || "";
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === "--name") name = takeValue(argv, i++, argv[i]);
    else if (argv[i] === "--description") description = takeValue(argv, i++, argv[i]);
    else if (argv[i] === "--password") password = takeValue(argv, i++, argv[i]);
    else {
      printError(`Unexpected argument: ${argv[i]}`);
      return 2;
    }
  }
  if (!handle || !name || !description) {
    printError("Usage: profile update HANDLE --name NAME --description TEXT [--password PASSWORD]");
    return 2;
  }
  if (!password) {
    printError("Missing password: use --password or set PDS_POST_PASSWORD.");
    return 2;
  }
  const session = await login(handle, password);
  if (!session) return 1;
  const result = await createRecord(session, "app.bsky.actor.profile", {
    "$type": "app.bsky.actor.profile",
    displayName: name,
    description,
  });
  if (!result) return 1;
  printSuccess("Profile updated!");
  return 0;
}

function help(): number {
  console.log(`Usage:
  scripts/dev/pds_cli.ts [--json] account create HANDLE EMAIL [--password PASSWORD]
  scripts/dev/pds_cli.ts [--json] post create HANDLE TEXT [--password PASSWORD]
  scripts/dev/pds_cli.ts [--json] profile update HANDLE --name NAME --description TEXT [--password PASSWORD]
`);
  return 2;
}

async function main(): Promise<number> {
  const argv = stripWrapperFlags(Deno.args);
  configureOutput();
  const [command, subcommand, ...rest] = argv;
  if (command === "account" && subcommand === "create") return await handleAccountCreate(rest);
  if (command === "post" && subcommand === "create") return await handlePostCreate(rest);
  if (command === "profile" && subcommand === "update") return await handleProfileUpdate(rest);
  return help();
}

if (import.meta.main) {
  Deno.exit(await main());
}
