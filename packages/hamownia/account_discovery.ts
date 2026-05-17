/** Account discovery helpers for Garazyk PDS maintenance tooling. */
import { XrpcClient } from "@garazyk/gruszka";

/** A resolved account target used by chat and account-creation tooling. */
export interface TargetIdentity {
  input: string;
  did: string;
  handle?: string;
}

/** Options controlling target resolution. */
export interface ResolveTargetsOptions {
  sshHost?: string;
  dbPath?: string;
  limit?: number;
}

type JsonRecord = Record<string, unknown>;

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" ? value as JsonRecord : {};
}

function normalizeLimit(limit?: number): number {
  if (typeof limit === "number" && Number.isFinite(limit)) {
    return Math.max(1, Math.min(100, Math.trunc(limit)));
  }
  return 10;
}

async function fileExists(path: string): Promise<boolean> {
  try {
    const stat = await Deno.stat(path);
    return stat.isFile;
  } catch {
    return false;
  }
}

function normalizeTargetRow(row: unknown): TargetIdentity | null {
  const record = asRecord(row);
  const did = String(record.did || "");
  if (!did) return null;

  const rawHandle = record.handle;
  const handle = typeof rawHandle === "string"
    ? rawHandle
    : rawHandle && typeof rawHandle === "object"
    ? String((rawHandle as JsonRecord).handle || "")
    : "";

  return {
    input: handle || did,
    did,
    handle: handle || undefined,
  };
}

function normalizeTargets(rows: unknown[]): TargetIdentity[] {
  return rows
    .map(normalizeTargetRow)
    .filter((row): row is TargetIdentity => Boolean(row))
    .filter((row) => row.did.startsWith("did:plc:"));
}

async function runSqliteJson(dbPath: string, sql: string): Promise<unknown[]> {
  const command = new Deno.Command("sqlite3", {
    args: ["-json", dbPath, sql],
    stdout: "piped",
    stderr: "piped",
  });
  const output = await command.output();
  if (!output.success) {
    const stderr = new TextDecoder().decode(output.stderr).trim();
    throw new Error(`Failed to query ${dbPath}: ${stderr || "sqlite3 failed"}`);
  }

  const stdout = new TextDecoder().decode(output.stdout).trim();
  if (!stdout) return [];
  return JSON.parse(stdout) as unknown[];
}

async function runCommandWithInput(
  command: string,
  args: string[],
  input: string,
): Promise<{ code: number; stdout: string; stderr: string }> {
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

/** Discover local PLC DIDs from the service SQLite database. */
export async function discoverLocalDidTargets(
  dbPath: string,
  limit?: number,
): Promise<TargetIdentity[]> {
  if (!(await fileExists(dbPath))) return [];

  const normalizedLimit = normalizeLimit(limit);
  const sql =
    `SELECT did, handle FROM accounts WHERE did LIKE 'did:plc:%' ORDER BY created_at DESC LIMIT ${normalizedLimit};`;
  const rows = await runSqliteJson(dbPath, sql);
  return normalizeTargets(rows);
}

/** Discover PLC accounts by querying the remote PDS database over SSH. */
export async function discoverRemoteAccountsViaSsh(
  sshHost: string,
  dbPath: string,
  limit?: number,
): Promise<TargetIdentity[]> {
  const normalizedLimit = normalizeLimit(limit);
  const sql =
    `SELECT did, handle FROM accounts WHERE did LIKE 'did:plc:%' ORDER BY created_at DESC LIMIT ${normalizedLimit};`;
  const result = await runCommandWithInput("ssh", [
    "-T",
    sshHost,
    "sqlite3",
    "-json",
    dbPath,
  ], sql);
  if (result.code !== 0) {
    throw new Error(
      `SSH discovery failed: ${result.stderr.trim() || "ssh command failed"}`,
    );
  }

  const stdout = result.stdout.trim();
  if (!stdout) return [];
  return normalizeTargets(JSON.parse(stdout) as unknown[]);
}

/** Discover PLC accounts via the admin API fallback. */
export async function discoverRemoteAccountsViaAdminApi(
  pdsUrl: string,
  accessJwt: string,
  limit?: number,
): Promise<TargetIdentity[]> {
  const client = new XrpcClient(pdsUrl);
  const response = await client.query(
    "com.atproto.admin.getAccounts",
    { limit: normalizeLimit(limit) },
    accessJwt,
  );
  const accounts = Array.isArray(asRecord(response).accounts)
    ? asRecord(response).accounts as unknown[]
    : [];
  return normalizeTargets(accounts);
}

/** Find the first locally configured PDS SQLite database path. */
export async function firstExistingServiceDbPath(): Promise<
  string | undefined
> {
  const explicit = Deno.env.get("PDS_SERVICE_DB");
  const dataDir = Deno.env.get("PDS_DATA_DIR");
  const candidates = [
    explicit,
    dataDir ? `${dataDir.replace(/\/$/, "")}/service/service.db` : undefined,
    "/var/lib/atprotopds/service/service.db",
  ].filter((path): path is string => Boolean(path));

  for (const candidate of candidates) {
    if (await fileExists(candidate)) return candidate;
  }
  return undefined;
}

/** Resolve PLC accounts using SSH, admin API, or local database discovery. */
export async function resolveTargets(
  pdsUrl: string,
  selfDid: string,
  accessJwt?: string,
  options: ResolveTargetsOptions = {},
): Promise<TargetIdentity[]> {
  const normalizedLimit = normalizeLimit(options.limit);
  const targets: TargetIdentity[] = [];

  if (options.sshHost) {
    const remoteDbPath = options.dbPath ||
      "/var/lib/atprotopds/service/service.db";
    try {
      targets.push(
        ...await discoverRemoteAccountsViaSsh(
          options.sshHost,
          remoteDbPath,
          normalizedLimit,
        ),
      );
    } catch (error) {
      if (accessJwt) {
        console.error(
          `  SSH discovery unavailable: ${
            error instanceof Error ? error.message : error
          }`,
        );
        console.error("  Falling back to admin API discovery...");
      } else {
        throw error;
      }
    }
  }

  if (targets.length === 0 && accessJwt) {
    try {
      targets.push(
        ...await discoverRemoteAccountsViaAdminApi(
          pdsUrl,
          accessJwt,
          normalizedLimit,
        ),
      );
    } catch (error) {
      console.error(
        `  Admin API unavailable: ${
          error instanceof Error ? error.message : error
        }`,
      );
      console.error("  Falling back to local DB discovery...");
    }
  }

  if (targets.length === 0) {
    const dbPath = options.dbPath || await firstExistingServiceDbPath();
    if (dbPath) {
      targets.push(...await discoverLocalDidTargets(dbPath, normalizedLimit));
    }
  }

  const unique = new Map<string, TargetIdentity>();
  for (const target of targets) {
    if (!target.did.startsWith("did:plc:")) {
      throw new Error(
        `Target ${target.input} resolved to ${target.did}; expected a did:plc account`,
      );
    }
    if (target.did === selfDid) continue;
    unique.set(target.did, target);
  }

  if (unique.size === 0) {
    throw new Error(
      "No target did:plc accounts found. Provide a database path, SSH host, or admin access token.",
    );
  }

  return [...unique.values()];
}
