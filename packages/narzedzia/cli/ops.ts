import { Command, SecretType } from "@cliffy/command";
import {
  runBackup,
  runBackfill,
  runValidateConfig,
  runSetupPds,
  runDnsAdd,
} from "../ops_command.ts";

const secret = new SecretType();

const backupCmd = new Command()
  .description("Run PDS backup.\n\n" +
    "Backs up service databases, user databases, and config files, " +
    "then compresses into a timestamped archive.")
  .option("--data-dir <dir:string>", "PDS data directory.", {
    required: true,
  })
  .option("--backup-dir <dir:string>", "Directory to store backups.", {
    required: true,
  })
  .option("--retention <days:string>", "Days to keep backups.", {
    default: "14",
  })
  .action(async (options) => {
    const { dataDir, backupDir, retention } = options as {
      dataDir: string;
      backupDir: string;
      retention?: string;
    };
    await runBackup({ dataDir, backupDir, retention });
  });

const backfillCmd = new Command()
  .description("Backfill account_usage table in actor stores.")
  .option("--data-dir <dir:string>", "PDS data directory.", {
    required: true,
  })
  .action(async (options) => {
    const { dataDir } = options as { dataDir: string };
    await runBackfill({ dataDir });
  });

const validateConfigCmd = new Command()
  .description(
    "Validate PDS configuration for security standards.\n\n" +
    "Checks invite_code_required, plc.url, rate_limit.enabled, and debug flags.",
  )
  .arguments("<config-path:string>")
  .action(async (_, configPath) => {
    await runValidateConfig({ configPath });
  });

const setupPdsCmd = new Command()
  .description("Initialize a production PDS instance.\n\n" +
    "Creates an admin account, verifies DID registration, and sets up DNS records.")
  .option("--email <email:string>", "Admin email.", { required: true })
  .option("--handle <handle:string>", "Admin handle (e.g. alice.garazyk.xyz).", {
    required: true,
  })
  .option("--password <password:secret>", "Account password (generated if omitted).")
  .option("--cf-token <token:secret>", "Cloudflare API token.", {
    required: true,
  })
  .option("--cf-zone-id <id:string>", "Cloudflare Zone ID.", { required: true })
  .option("--data-dir <dir:string>", "PDS data directory.")
  .option("--cf-target <target:string>", "CNAME target.")
  .type("secret", secret)
  .action(async (options) => {
    const {
      email, handle, password, cfToken, cfZoneId, dataDir, cfTarget,
    } = options as {
      email: string;
      handle: string;
      password?: string;
      cfToken: string;
      cfZoneId: string;
      dataDir?: string;
      cfTarget?: string;
    };
    await runSetupPds({ email, handle, password, cfToken, cfZoneId, dataDir, cfTarget });
  });

const dnsAddCmd = new Command()
  .description("Add CNAME record to Cloudflare.")
  .option("--cf-token <token:secret>", "Cloudflare API token.", {
    required: true,
  })
  .option("--cf-zone-id <id:string>", "Cloudflare Zone ID.", {
    required: true,
  })
  .option("--handle <handle:string>", "Handle to add DNS for.", {
    required: true,
  })
  .option("--cf-target <target:string>", "CNAME target.", { required: true })
  .type("secret", secret)
  .action(async (options) => {
    const { cfToken, cfZoneId, handle, cfTarget } = options as {
      cfToken: string;
      cfZoneId: string;
      handle: string;
      cfTarget: string;
    };
    await runDnsAdd({ cfToken, cfZoneId, handle, cfTarget });
  });

export const opsCommand = new Command()
  .description("Production PDS operations.\n\n" +
    "Backup, backfill, config validation, setup, and DNS management " +
    "for production ATProto PDS instances.\n\n" +
    "WARNING: These commands affect production systems. " +
    "Use --dry-run where available to preview changes.")
  .command("backup", backupCmd)
  .command("backfill", backfillCmd)
  .command("validate-config", validateConfigCmd)
  .command("setup-pds", setupPdsCmd)
  .command("dns-add", dnsAddCmd);
