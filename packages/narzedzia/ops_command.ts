/**
 * CLI command for production PDS operations and DNS management.
 * @module ops_command
 */

import { parseArgs } from "@std/cli/parse-args";
import {
  errorExit,
  initLogger,
  logError,
  logHeader,
  logInfo,
  logOk,
  logWarn,
} from "@garazyk/schemat";
import { basename, dirname, join } from "@std/path";
import { walk } from "@std/fs";

/** Entry point for the operations CLI. */
export async function opsCommandMain(argv: string[]): Promise<void> {
  const flags = parseArgs(argv, {
    string: [
      "data-dir",
      "backup-dir",
      "retention",
      "email",
      "handle",
      "password",
      "cf-token",
      "cf-zone-id",
      "cf-target",
    ],
    boolean: ["verbose", "quiet", "help"],
    alias: { h: "help", v: "verbose", q: "quiet" },
  });

  if (flags.help) {
    console.log(`Usage: scripts/ops.ts <command> [options]

Commands:
  backup    Run PDS backup
  backfill  Backfill account_usage table in actor stores
  validate-config  Validate PDS configuration for security standards
  setup-pds  Initialize a production PDS instance
  add-account  Create production account and set up DNS
  dns-add    Add CNAME record to Cloudflare
  restore   Restore PDS from backup (stub)
  install   Install PDS on current system (stub)

Options:
  --data-dir DIR     PDS data directory
  --backup-dir DIR   Directory to store backups
  --retention DAYS   Number of days to keep backups (default: 14)
  --email EMAIL      Admin email for setup/account
  --handle HANDLE    Admin handle (e.g. alice.garazyk.xyz)
  --password PASS    Account password (generated if omitted)
  --cf-token TOKEN   Cloudflare API token
  --cf-zone-id ID    Cloudflare Zone ID
  --cf-target TARGET CNAME target (e.g. pds.garazyk.xyz)
  -v, --verbose      Enable verbose logging
  -q, --quiet         Suppress non-error output
  --help             Show this help
`);
    return;
  }

  initLogger({ verbose: flags.verbose, quiet: flags.quiet });

  const command = flags._[0] as string;

  async function runBackup() {
    const dataDir = flags["data-dir"] || "/var/lib/atprotopds/data";
    const backupDir = flags["backup-dir"] || "/var/backups/atprotopds";
    const retentionDays = parseInt(flags.retention || "14");
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(
      0,
      19,
    );
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

      await Deno.mkdir(dirname(dest), { recursive: true });
      logInfo(`  Backing up ${label}...`);

      const proc = new Deno.Command("sqlite3", {
        args: [src, `.backup '${dest}'`],
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

    // 1. Service databases
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

    // 2. User databases
    for await (
      const entry of walk(dataDir, { maxDepth: 4, includeDirs: false })
    ) {
      if (basename(entry.path) === "data.sqlite") {
        const relPath = entry.path.slice(dataDir.length + 1);
        await backupDb(
          entry.path,
          join(backupDest, relPath),
          `user/${relPath}`,
        );
      }
    }

    // 3. Config
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

    // 4. Compress
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

  async function runBackfill() {
    const dataDir = flags["data-dir"] || "/var/lib/atprotopds/data";
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

        const { text: recordCount } = await runSql(
          "SELECT COUNT(*) FROM records;",
        );
        const { text: repoBytes } = await runSql(
          "SELECT COALESCE(SUM(size), 0) FROM ipld_blocks;",
        );

        let blobBytes = "0";
        let blobCount = "0";
        const { text: hasBlobs } = await runSql(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='blobs';",
        );
        if (hasBlobs) {
          const { text: bb } = await runSql(
            "SELECT COALESCE(SUM(size), 0) FROM blobs;",
          );
          const { text: bc } = await runSql("SELECT COUNT(*) FROM blobs;");
          blobBytes = bb;
          blobCount = bc;
        }

        await runSql(`
          INSERT OR REPLACE INTO account_usage (did, blob_bytes, blob_count, repo_bytes, record_count)
          VALUES ('${did}', ${blobBytes}, ${blobCount}, ${repoBytes}, ${recordCount});
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

  async function runValidateConfig() {
    const configPath = flags._[1] as string || "docker/pds/config.json";

    try {
      const text = await Deno.readTextFile(configPath);
      // Strip comments
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

  async function runSetupPds() {
    const email = flags.email;
    const handle = flags.handle;
    const password = flags.password ||
      crypto.randomUUID().replace(/-/g, "").slice(0, 24);
    const cfToken = flags["cf-token"];
    const cfZoneId = flags["cf-zone-id"];

    if (!email || !handle || !cfToken || !cfZoneId) {
      errorExit(
        "--email, --handle, --cf-token, and --cf-zone-id are required for setup",
      );
    }

    logHeader("=== PDS Production Setup ===");

    const dataDir = flags["data-dir"] ||
      join(Deno.env.get("HOME") || ".", "pds-data");
    await Deno.mkdir(dataDir, { recursive: true, mode: 0o750 });
    await Deno.mkdir(join(dataDir, "keys"), { recursive: true, mode: 0o700 });
    logOk(`Directories created at ${dataDir}`);

    logInfo(`Creating admin account: ${handle} (${email})...`);
    const buildBin = join(Deno.cwd(), "build-linux", "bin", "kaszlak");
    const configPath = join(Deno.cwd(), "config", "production.json");

    const proc = new Deno.Command(buildBin, {
      args: [
        "account",
        "create",
        "--email",
        email,
        "--handle",
        handle,
        "--password",
        password,
        "--config",
        configPath,
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
    const target = flags["cf-target"] || Deno.env.get("DEPLOY_HOST");
    if (!target) {
      errorExit("--cf-target or DEPLOY_HOST env var is required for DNS");
    }

    await cf.addCname(handle, target);
    await cf.addCname(`pds.${handle.split(".").slice(1).join(".")}`, target);

    logHeader("\nSetup Complete!");
    logInfo(`Admin Handle: ${handle}`);
    logInfo(`Password:     ${password}`);
    logInfo(
      "Next steps: Install Nginx config and systemd unit from config/ folder.",
    );
  }

  async function runDnsAdd() {
    const token = flags["cf-token"];
    const zoneId = flags["cf-zone-id"];
    const handle = flags.handle;
    const target = flags["cf-target"] || Deno.env.get("DEPLOY_HOST");

    if (!token || !zoneId || !handle || !target) {
      errorExit(
        "--cf-token, --cf-zone-id, --handle, and --cf-target are required",
      );
    }

    const cf = new CloudflareClient(token, zoneId);
    await cf.addCname(handle, target);
  }

  switch (command) {
    case "backup":
      await runBackup();
      break;
    case "backfill":
      await runBackfill();
      break;
    case "validate-config":
      await runValidateConfig();
      break;
    case "setup-pds":
      await runSetupPds();
      break;
    case "dns-add":
      await runDnsAdd();
      break;
    case "add-account":
      await runSetupPds(); // shared logic
      break;
    default:
      logError(`Unknown command: ${command}`);
      Deno.exit(1);
  }
}

class CloudflareClient {
  constructor(private token: string, private zoneId: string) {}

  async addCname(name: string, content: string) {
    logInfo(`Checking if CNAME for '${name}' already exists...`);
    try {
      const listResp = await fetch(
        `https://api.cloudflare.com/client/v4/zones/${this.zoneId}/dns_records?type=CNAME&name=${name}`,
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
