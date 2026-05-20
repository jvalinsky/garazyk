/**
 * CLI command for production PDS operations and DNS management.
 * @module ops_command
 */

import {
  errorExit,
  logError,
  logHeader,
  logInfo,
  logOk,
  logWarn,
} from "@garazyk/schemat";
import { basename, dirname, join } from "@std/path";
import { walk } from "@std/fs";

/** Valid DID format: did:plc:... or did:web:... */
const DID_PATTERN = /^did:(plc|web):[a-zA-Z0-9._:%-]+$/;

/** Validate a DID string to prevent SQL injection via filename. */
function validateDid(did: string): boolean {
  return DID_PATTERN.test(did);
}

/** Sanitize a path for use in sqlite CLI commands. Rejects paths with quotes or shell metacharacters. */
function sanitizePathForSqlite(path: string): string | null {
  // Only allow alphanumeric, dots, slashes, underscores, and hyphens
  if (!/^[a-zA-Z0-9./_-]+$/.test(path)) {
    return null;
  }
  return path;
}

export interface BackupOptions {
  dataDir?: string;
  backupDir?: string;
  retention?: string;
}

export interface BackfillOptions {
  dataDir?: string;
}

export interface ValidateConfigOptions {
  configPath: string;
}

export interface SetupPdsOptions {
  email: string;
  handle: string;
  password?: string;
  cfToken: string;
  cfZoneId: string;
  dataDir?: string;
  cfTarget?: string;
}

export interface DnsAddOptions {
  cfToken: string;
  cfZoneId: string;
  handle: string;
  cfTarget: string;
}

export async function runBackup(options: BackupOptions): Promise<void> {
  const dataDir = options.dataDir || "/var/lib/atprotopds/data";
  const backupDir = options.backupDir || "/var/backups/atprotopds";
  const retentionDays = parseInt(options.retention || "14");
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const backupDest = join(backupDir, timestamp);

  logHeader("=== ATProto PDS Backup ===");
  logInfo(`Timestamp:     ${timestamp}`);
  logInfo(`Data dir:      ${dataDir}`);
  logInfo(`Backup dest:   ${backupDest}`);
  logInfo(`Retention:     ${retentionDays} days`);

  await Deno.mkdir(backupDest, { recursive: true });

  let errors = 0;
  let dbCount = 0;

  async function backupDb(src: string, dest: string, label: string) {
    try {
      await Deno.stat(src);
    } catch {
      logWarn(`  SKIP: ${label} (not found)`);
      return;
    }
    const safeSrc = sanitizePathForSqlite(src);
    const safeDest = sanitizePathForSqlite(dest);
    if (!safeSrc || !safeDest) {
      errors++;
      logError(`    FAILED: Invalid characters in path for ${label}`);
      return;
    }
    await Deno.mkdir(dirname(dest), { recursive: true });
    logInfo(`  Backing up ${label}...`);
    const proc = new Deno.Command("sqlite3", {
      args: [safeSrc, `.backup ${safeDest}`],
    });
    const { code, stderr } = await proc.output();
    if (code === 0) {
      dbCount++;
      logOk(`    OK`);
    } else {
      errors++;
      logError(`    FAILED: ${new TextDecoder().decode(stderr)}`);
    }
  }

  await backupDb(
    join(dataDir, "service", "service.db"),
    join(backupDest, "service", "service.db"),
    "service/service.db",
  );
  await backupDb(
    join(dataDir, "sequencer", "service.db"),
    join(backupDest, "sequencer", "service.db"),
    "sequencer/service.db",
  );
  await backupDb(
    join(dataDir, "did_cache", "service.db"),
    join(backupDest, "did_cache", "service.db"),
    "did_cache/service.db",
  );

  for await (const entry of walk(dataDir, { maxDepth: 4, includeDirs: false })) {
    if (basename(entry.path) === "data.sqlite") {
      const relPath = entry.path.slice(dataDir.length + 1);
      await backupDb(entry.path, join(backupDest, relPath), `user/${relPath}`);
    }
  }

  const configs = [
    join(dataDir, "..", "config.json"),
    join(dataDir, "..", "production.json"),
    "/etc/atprotopds/production.json",
  ];
  for (const config of configs) {
    try {
      await Deno.copyFile(config, join(backupDest, basename(config)));
      logInfo(`  Copied ${basename(config)}`);
    } catch { /* ignore */ }
  }

  logInfo("Compressing backup...");
  const archive = join(backupDir, `pds-backup-${timestamp}.tar.gz`);
  const tarProc = new Deno.Command("tar", {
    args: ["-czf", archive, "-C", backupDir, timestamp],
  });
  await tarProc.output();
  await Deno.remove(backupDest, { recursive: true });

  logHeader("\n=== Backup Complete ===");
  logInfo(`Archive: ${archive}`);
  if (errors > 0) {
    logWarn(`WARNING: ${errors} database(s) failed to backup`);
  } else {
    logOk(`Status: All ${dbCount} databases backed up successfully`);
  }
}

export async function runBackfill(options: BackfillOptions): Promise<void> {
  const dataDir = options.dataDir || "/var/lib/atprotopds/data";
  const actorsDir = join(dataDir, "actors");

  try {
    await Deno.stat(actorsDir);
  } catch {
    errorExit(`Actors directory not found: ${actorsDir}`);
  }

  logHeader(`Scanning actor databases in ${actorsDir}...`);

  let actorCount = 0;
  let totalRecords = 0;
  let totalBlobs = 0;

  for await (const entry of Deno.readDir(actorsDir)) {
    if (entry.isFile && entry.name.endsWith(".db")) {
      const dbPath = join(actorsDir, entry.name);
      const did = entry.name.replace(/\.db$/, "");

      if (!validateDid(did)) {
        logWarn(`  SKIP: ${did} (invalid DID format)`);
        continue;
      }

      logInfo(`Processing ${did}...`);

      const runSql = async (sql: string) => {
        const proc = new Deno.Command("sqlite3", { args: [dbPath, sql] });
        const { stdout, code } = await proc.output();
        return { text: new TextDecoder().decode(stdout).trim(), code };
      };

      await runSql(`
        CREATE TABLE IF NOT EXISTS account_usage (
            did TEXT PRIMARY KEY,
            blob_bytes INTEGER NOT NULL DEFAULT 0,
            blob_count INTEGER NOT NULL DEFAULT 0,
            repo_bytes INTEGER NOT NULL DEFAULT 0,
            record_count INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
        );
      `);

      const { text: recordCount } = await runSql("SELECT COUNT(*) FROM records;");
      const { text: repoBytes } = await runSql("SELECT COALESCE(SUM(size), 0) FROM ipld_blocks;");

      let blobBytes = "0";
      let blobCount = "0";
      const { text: hasBlobs } = await runSql(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='blobs';",
      );
      if (hasBlobs) {
        const { text: bb } = await runSql("SELECT COALESCE(SUM(size), 0) FROM blobs;");
        const { text: bc } = await runSql("SELECT COUNT(*) FROM blobs;");
        blobBytes = bb;
        blobCount = bc;
      }

      const safeBlobBytes = /^\d+$/.test(blobBytes) ? blobBytes : "0";
      const safeBlobCount = /^\d+$/.test(blobCount) ? blobCount : "0";
      const safeRepoBytes = /^\d+$/.test(repoBytes) ? repoBytes : "0";
      const safeRecordCount = /^\d+$/.test(recordCount) ? recordCount : "0";

      await runSql(`
        INSERT OR REPLACE INTO account_usage (did, blob_bytes, blob_count, repo_bytes, record_count)
        VALUES ('${did}', ${safeBlobBytes}, ${safeBlobCount}, ${safeRepoBytes}, ${safeRecordCount});
      `);

      actorCount++;
      totalRecords += parseInt(recordCount || "0");
      totalBlobs += parseInt(blobCount || "0");
    }
  }

  logOk("\nBackfill complete.");
  logInfo(`  Actors processed: ${actorCount}`);
  logInfo(`  Total records:    ${totalRecords}`);
  logInfo(`  Total blobs:      ${totalBlobs}`);
}

export async function runValidateConfig(options: ValidateConfigOptions): Promise<void> {
  const configPath = options.configPath;

  try {
    const text = await Deno.readTextFile(configPath);
    const data = JSON.parse(text.replace(/\/\*[\s\S]*?\*\//g, ""));

    logHeader(`Validating PDS config: ${configPath}`);
    let ret = 0;

    const check = (path: string, expected: string | number | boolean) => {
      const parts = path.split(".");
      let val = data;
      for (const p of parts) val = val?.[p];
      if (String(val) === String(expected)) {
        logOk(`PASS: ${path} is '${val}'`);
      } else {
        logError(`FAIL: ${path} expected '${expected}', got '${val}'`);
        ret = 1;
      }
    };

    check("session.invite_code_required", true);
    check("plc.url", "https://plc.directory");
    check("rate_limit.enabled", true);

    if (JSON.stringify(data.debug || {}).includes("true")) {
      logError(`FAIL: Debug flags enabled in config`);
      ret = 1;
    }

    if (ret === 0) {
      logOk("Config validation SUCCESS");
    } else {
      errorExit("Config validation FAILED");
    }
  } catch (err) {
    errorExit(`Failed to validate config: ${err}`);
  }
}

export async function runSetupPds(options: SetupPdsOptions): Promise<void> {
  const { email, handle, cfToken, cfZoneId } = options;
  if (!email || !handle || !cfToken || !cfZoneId) {
    errorExit("--email, --handle, --cf-token, and --cf-zone-id are required for setup");
  }
  const password = options.password || crypto.randomUUID().replace(/-/g, "").slice(0, 24);

  logHeader("=== PDS Production Setup ===");

  const dataDir = options.dataDir || join(Deno.env.get("HOME") || ".", "pds-data");
  await Deno.mkdir(dataDir, { recursive: true, mode: 0o750 });
  await Deno.mkdir(join(dataDir, "keys"), { recursive: true, mode: 0o700 });
  logOk(`Directories created at ${dataDir}`);

  logInfo(`Creating admin account: ${handle} (${email})...`);
  const buildBin = join(Deno.cwd(), "build-linux", "bin", "kaszlak");
  const configPath = join(Deno.cwd(), "config", "production.json");

  const proc = new Deno.Command(buildBin, {
    args: [
      "account", "create",
      "--email", email,
      "--handle", handle,
      "--password", password,
      "--config", configPath,
      "--verbose",
    ],
  });
  const { code, stdout, stderr } = await proc.output();
  const decoder = new TextDecoder();
  const output = `${decoder.decode(stdout)}${decoder.decode(stderr)}`;
  console.log(output);

  if (code !== 0) errorExit("Failed to create admin account");

  const didMatch = output.match(/did:plc:[a-z2-7]{24}/);
  const did = didMatch ? didMatch[0] : null;
  if (did) {
    logOk(`Account created with DID: ${did}`);
    logInfo("Verifying DID registration...");
    for (let i = 0; i < 10; i++) {
      const resp = await fetch(`https://plc.directory/${did}`);
      if (resp.ok) {
        logOk("DID verified at plc.directory");
        break;
      }
      logWarn(`Attempt ${i + 1}/10: DID not yet visible...`);
      await new Promise((r) => setTimeout(r, 2000));
    }
  }

  const cf = new CloudflareClient(cfToken, cfZoneId);
  const target = options.cfTarget || Deno.env.get("DEPLOY_HOST");
  if (!target) {
    errorExit("--cf-target or DEPLOY_HOST env var is required for DNS");
  }

  await cf.addCname(handle, target);
  await cf.addCname(`pds.${handle.split(".").slice(1).join(".")}`, target);

  logHeader("\nSetup Complete!");
  logInfo(`Admin Handle: ${handle}`);
  logInfo(`Password:     ${password}`);
  logInfo("Next steps: Install Nginx config and systemd unit from config/ folder.");
}

export async function runDnsAdd(options: DnsAddOptions): Promise<void> {
  const { cfToken, cfZoneId, handle, cfTarget } = options;
  if (!cfToken || !cfZoneId || !handle || !cfTarget) {
    errorExit("--cf-token, --cf-zone-id, --handle, and --cf-target are required");
  }

  const cf = new CloudflareClient(cfToken, cfZoneId);
  await cf.addCname(handle, cfTarget);
}

export class CloudflareClient {
  constructor(private token: string, private zoneId: string) {}

  async addCname(name: string, content: string): Promise<boolean> {
    logInfo(`Checking if CNAME for '${name}' already exists...`);
    const params = new URLSearchParams({
      type: "CNAME",
      name: name,
    });
    try {
      const listResp = await fetch(
        `https://api.cloudflare.com/client/v4/zones/${this.zoneId}/dns_records?${params.toString()}`,
        {
          headers: {
            "Authorization": `Bearer ${this.token}`,
            "Content-Type": "application/json",
          },
        },
      );
      const listData = await listResp.json();
      if (listData.result?.length > 0) {
        logWarn(
          `CNAME record for '${name}' already exists — skipping creation`,
        );
        return true;
      }

      logInfo(`Creating CNAME: ${name} → ${content} (DNS Only)...`);
      const createResp = await fetch(
        `https://api.cloudflare.com/client/v4/zones/${this.zoneId}/dns_records`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${this.token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            type: "CNAME",
            name,
            content,
            ttl: 1,
            proxied: false,
            comment: `AT Protocol handle for ${name}`,
          }),
        },
      );

      const result = await createResp.json();
      if (result.success) {
        logOk(`CNAME record created successfully: ${name} → ${content}`);
        return true;
      } else {
        logError(
          `Failed to create CNAME record: ${JSON.stringify(result.errors)}`,
        );
        return false;
      }
    } catch (err) {
      logError(`Cloudflare API error: ${err}`);
      return false;
    }
  }
}
