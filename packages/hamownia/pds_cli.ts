/** PDS CLI helpers used by Garazyk maintenance tooling. */
import { XrpcClient } from "@garazyk/gruszka";

/** Configuration for the PDS CLI helpers. */
export interface PdsCliConfig {
  pdsUrl: string;
  binPath: string;
  dataDir: string;
}

type JsonRecord = Record<string, unknown>;

interface Session {
  accessJwt: string;
  did: string;
  handle: string;
}

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" ? value as JsonRecord : {};
}

function takeValue(argv: string[], index: number, flag: string): string {
  const value = argv[index + 1];
  if (!value) {
    console.error(`${flag} requires a value`);
    Deno.exit(2);
  }
  return value;
}

function nowIsoTrimmed(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function printInfo(message: string): void {
  console.log(message);
}

function printSuccess(message: string): void {
  console.log(`OK: ${message}`);
}

function printError(message: string, extra?: Record<string, unknown>): void {
  console.error(`Error: ${message}`);
  if (extra && Object.keys(extra).length > 0) {
    console.error(JSON.stringify(extra));
  }
}

async function login(
  client: XrpcClient,
  pdsUrl: string,
  handle: string,
  password: string,
): Promise<Session | null> {
  printInfo(`Logging in as ${handle}...`);
  try {
    const accounts = client.accounts as {
      createSession(identifier: string, password: string): Promise<unknown>;
    };
    const response = await accounts.createSession(handle, password);
    const record = asRecord(response);
    const accessJwt = String(record.accessJwt || "");
    const did = String(record.did || "");
    const sessionHandle = String(record.handle || handle);
    if (!accessJwt || !did) {
      printError(
        `Login for ${handle} succeeded but response did not include accessJwt and did`,
      );
      return null;
    }
    return { accessJwt, did, handle: sessionHandle };
  } catch (error) {
    if (error instanceof Error && error.name === "TransportError") {
      printError(`Could not connect to PDS at ${pdsUrl}`);
    } else {
      printError(error instanceof Error ? error.message : String(error));
    }
    return null;
  }
}

/** Execute a kaszlak binary command with the standard PDS CLI arguments. */
export async function runKaszlak(
  binPath: string,
  dataDir: string,
  args: string[],
): Promise<number> {
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
  const commandArgs = [
    subcommand,
    "--verbose",
    "--data-dir",
    dataDir,
    "--config",
    "/tmp/missing_cli_config.json",
    ...tail,
  ];
  const output = await new Deno.Command(binPath, {
    args: commandArgs,
    stdout: "piped",
    stderr: "piped",
  }).output();
  const stdout = new TextDecoder().decode(output.stdout);
  const stderr = new TextDecoder().decode(output.stderr);

  if (output.code !== 0) {
    printError("kaszlak command failed", {
      command: [binPath, ...commandArgs].join(" "),
      stderr: stderr.trim(),
      exit_code: output.code,
    });
    if (stdout) console.log(stdout.trimEnd());
    return output.code;
  }

  if (stdout) console.log(stdout.trimEnd());
  return 0;
}

/** Create an account through the kaszlak binary. */
export async function handleAccountCreate(
  argv: string[],
  config: PdsCliConfig,
): Promise<number> {
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
    printError(
      "Missing password: use --password or set PDS_CREATE_ACCOUNT_PASSWORD.",
    );
    return 2;
  }

  printInfo(`Creating account for ${handle}...`);
  const rc = await runKaszlak(config.binPath, config.dataDir, [
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

/** Create a post through the PDS XRPC API. */
export async function handlePostCreate(
  argv: string[],
  config: PdsCliConfig,
): Promise<number> {
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

  const client = new XrpcClient(config.pdsUrl);
  const session = await login(client, config.pdsUrl, handle, password);
  if (!session) return 1;

  try {
    const records = client.records as {
      createRecord(
        repo: string,
        collection: string,
        record: Record<string, unknown>,
        token: string,
        options?: { rkey?: string; validate?: boolean },
      ): Promise<unknown>;
    };
    const result = await records.createRecord(
      session.did,
      "app.bsky.feed.post",
      {
        "$type": "app.bsky.feed.post",
        text,
        createdAt: nowIsoTrimmed(),
      },
      session.accessJwt,
    );
    printSuccess(
      `Post created! URI: ${(asRecord(result).uri as string) || "unknown"}`,
    );
    console.log(`CID: ${(asRecord(result).cid as string) || "unknown"}`);
    return 0;
  } catch (error) {
    printError(error instanceof Error ? error.message : String(error));
    return 1;
  }
}

/** Update a profile record through the PDS XRPC API. */
export async function handleProfileUpdate(
  argv: string[],
  config: PdsCliConfig,
): Promise<number> {
  const handle = argv[0];
  let name = "";
  let description = "";
  let password = Deno.env.get("PDS_POST_PASSWORD") || "";

  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === "--name") name = takeValue(argv, i++, argv[i]);
    else if (argv[i] === "--description") {
      description = takeValue(argv, i++, argv[i]);
    } else if (argv[i] === "--password") {
      password = takeValue(argv, i++, argv[i]);
    } else {
      printError(`Unexpected argument: ${argv[i]}`);
      return 2;
    }
  }

  if (!handle || !name || !description) {
    printError(
      "Usage: profile update HANDLE --name NAME --description TEXT [--password PASSWORD]",
    );
    return 2;
  }
  if (!password) {
    printError("Missing password: use --password or set PDS_POST_PASSWORD.");
    return 2;
  }

  const client = new XrpcClient(config.pdsUrl);
  const session = await login(client, config.pdsUrl, handle, password);
  if (!session) return 1;

  try {
    const records = client.records as {
      createRecord(
        repo: string,
        collection: string,
        record: Record<string, unknown>,
        token: string,
        options?: { rkey?: string; validate?: boolean },
      ): Promise<unknown>;
    };
    await records.createRecord(
      session.did,
      "app.bsky.actor.profile",
      {
        "$type": "app.bsky.actor.profile",
        displayName: name,
        description,
      },
      session.accessJwt,
      { rkey: "self" },
    );
    printSuccess("Profile updated!");
    return 0;
  } catch (error) {
    printError(error instanceof Error ? error.message : String(error));
    return 1;
  }
}
