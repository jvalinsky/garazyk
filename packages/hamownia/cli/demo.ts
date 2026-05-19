import { Command } from "@cliffy/command";
import { join } from "@std/path";
import { initRunDir, repoRoot } from "@garazyk/schemat/runtime";
import { initLogger, logError, logHeader, logInfo, logOk } from "@garazyk/schemat";
import {
  addRelayUpstream,
  startBinaryServices,
  stopBinaryServices,
} from "../binary_services.ts";
import { collectDiagnostics } from "../run_diagnostics.ts";
import type { E2ERunContext } from "../run_diagnostics.ts";

function generateHex(bytes = 32): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf).map((b) => b.toString(16).padStart(2, "0")).join("");
}

interface DemoOptions {
  skipSeed?: boolean;
  keepRunning?: boolean;
  stop?: boolean;
  runId?: string;
  collectDiagnostics?: boolean;
  diagnosticsDir?: string;
  verbose?: boolean;
  quiet?: boolean;
}

function toE2ERunContext(
  ctx: ReturnType<typeof initRunDir>,
  overrides: { diagnosticsDir?: string },
): E2ERunContext {
  return {
    runId: ctx.runId,
    runDir: ctx.runDir,
    logsDir: ctx.logDir,
    reportsDir: join(ctx.runDir, "reports"),
    diagnosticsDir: overrides.diagnosticsDir ?? ctx.diagnosticsDir,
    pidFile: ctx.pidFile,
    composeProject: ctx.composeProject,
  };
}

export const demoCommand = new Command()
  .description("Start a full ATProto stack demo with seed data.\n\n" +
    "Starts PLC, PDS, Relay, AppView, Chat, Video, and the Admin UI. " +
    "By default seeds demo accounts and content.")
  .option("--skip-seed", "Start services without seeding demo data.")
  .option("--keep-running", "Keep services running after demo setup.")
  .option("--stop", "Stop services for the current run.")
  .option("--run-id <id:string>", "Reuse or name the run directory.")
  .option("--collect-diagnostics", "Capture diagnostic logs after setup.")
  .option("--diagnostics-dir <path:string>", "Diagnostics output directory.")
  .action(async (options: DemoOptions) => {
    const flags = options;
    initLogger({ verbose: flags.verbose, quiet: flags.quiet });
    const ctx = initRunDir();
    const root = await repoRoot();

    const PDS_MASTER_SECRET = Deno.env.get("PDS_MASTER_SECRET") ?? generateHex();
    const PDS_ADMIN_PASSWORD = Deno.env.get("PDS_ADMIN_PASSWORD") ?? generateHex(8);
    const APPVIEW_ADMIN_SECRET = Deno.env.get("APPVIEW_ADMIN_SECRET") ?? generateHex(8);
    const CHAT_ADMIN_SECRET = Deno.env.get("CHAT_ADMIN_SECRET") ?? generateHex(8);
    const VIDEO_ADMIN_SECRET = Deno.env.get("VIDEO_ADMIN_SECRET") ?? generateHex(8);
    const UI_ADMIN_PASSWORD = Deno.env.get("UI_ADMIN_PASSWORD") ?? generateHex(8);

    async function writePdsConfig(): Promise<string> {
      const config = {
        server: {
          host: "127.0.0.1",
          port: 2583,
          data_dir: join(ctx.runDir, "data", "pds"),
          issuer: "http://127.0.0.1:2583",
          available_user_domains: ["test"],
        },
        appview: {
          url: "http://127.0.0.1:3200",
          did: "did:web:localhost",
        },
        database: { service_pool_max_size: 10, user_pool_max_size: 50 },
        logging: { format: "text", level: "info" },
        session: {
          access_token_ttl_seconds: 1800,
          refresh_token_ttl_seconds: 2592000,
          invite_code_required: false,
        },
        registration: {
          invite_code_required: false,
          phone_verification_required: false,
          captcha_required: false,
          oauth_only_registration: false,
        },
        relays: ["http://127.0.0.1:2584"],
        plc: {
          url: "http://127.0.0.1:2582",
          retry_count: 3,
          retry_delay_ms: 500,
        },
        cors: {
          allowed_origins: ["*"],
          allowed_methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"],
          allowed_headers: ["DPoP", "Authorization", "Content-Type", "*"],
          max_age: 86400,
        },
        auth: { master_secret: PDS_MASTER_SECRET },
      };
      const configPath = join(ctx.runDir, "data", "config", "pds-config.json");
      await Deno.mkdir(join(ctx.runDir, "data", "config"), { recursive: true });
      await Deno.writeTextFile(configPath, JSON.stringify(config, null, 2));
      return configPath;
    }

    if (flags.stop) {
      logHeader("Stopping full ATProto suite demo...");
      const services = ["plc", "pds", "relay", "appview", "chat", "video"] as const;
      await stopBinaryServices(ctx, [...services]);
      logOk("Demo services stopped.");
      return;
    }

    if (flags.collectDiagnostics && !flags.stop) {
      await collectDiagnostics(toE2ERunContext(ctx, { diagnosticsDir: flags.diagnosticsDir }), { label: "full-suite-demo" });
      return;
    }

    logHeader("Starting full ATProto suite demo...");

    const pdsConfigPath = await writePdsConfig();

    const services: Array<"plc" | "pds" | "relay" | "appview" | "chat" | "video"> = [
      "plc", "pds", "relay", "appview", "chat", "video",
    ];

    await startBinaryServices(ctx, {
      services,
      env: {
        pds: {
          PDS_PLC_URL: "http://127.0.0.1:2582",
          PDS_ISSUER: "http://127.0.0.1:2583",
          PDS_MASTER_SECRET,
          PDS_ADMIN_PASSWORD,
          PDS_ALLOW_HTTP: "1",
          PDS_USE_BIOMETRIC_PROTECTION: "false",
          PDS_USE_KEYCHAIN: "false",
          PDS_PLC_KEYS_DIR: join(ctx.runDir, "data", "pds", "keys"),
        },
        relay: { RELAY_ADMIN_PASSWORD: APPVIEW_ADMIN_SECRET },
        appview: {
          APPVIEW_RELAY_URLS: "ws://127.0.0.1:2584/xrpc/com.atproto.sync.subscribeRepos",
          APPVIEW_ADMIN_SECRET,
          APPVIEW_MASTER_SECRET: PDS_MASTER_SECRET,
          APPVIEW_PLC_URL: "http://127.0.0.1:2582",
        },
        chat: {
          PDS_URL: "http://127.0.0.1:2583",
          CHAT_ADMIN_SECRET,
        },
        video: {
          JELCZ_ADMIN_SECRET: VIDEO_ADMIN_SECRET,
          JELCZ_PDS_URL: "http://127.0.0.1:2583",
        },
      },
      args: {
        pds: [
          "serve",
          "--config",
          pdsConfigPath,
          "--port",
          "2583",
          "--data-dir",
          join(ctx.runDir, "data", "pds"),
          "--foreground",
        ],
      },
    });

    const buildBin = Deno.env.get("BUILD_DIR") || join(root, "build/bin");
    const uiProc = new Deno.Command(join(buildBin, "garazyk-ui"), {
      args: ["serve", "--port", "2590"],
      env: {
        GARAZYK_UI_PDS_URL: "http://127.0.0.1:2583",
        GARAZYK_UI_PLC_URL: "http://127.0.0.1:2582",
        GARAZYK_UI_RELAY_URL: "http://127.0.0.1:2584",
        GARAZYK_UI_APPVIEW_URL: "http://127.0.0.1:3200",
        GARAZYK_UI_CHAT_URL: "http://127.0.0.1:2585",
        GARAZYK_UI_VIDEO_URL: "http://127.0.0.1:2586",
        GARAZYK_UI_PORT: "2590",
        GARAZYK_UI_ADMIN_PASSWORD: UI_ADMIN_PASSWORD,
      },
    });
    const uiChild = uiProc.spawn();

    await addRelayUpstream(
      "http://127.0.0.1:2584",
      "http://127.0.0.1:2583",
      APPVIEW_ADMIN_SECRET,
    );

    if (!flags.skipSeed) {
      logInfo("Seeding demo data...");
      const seedProc = new Deno.Command("deno", {
        args: ["run", "-A", join(root, "scripts", "seed_full_suite.ts")],
        env: {
          PDS_URL: "http://127.0.0.1:2583",
          CHAT_URL: "http://127.0.0.1:2585",
        },
      });
      const { code } = await seedProc.output();
      if (code === 0) {
        logOk("Seeding completed");
      } else {
        logError("Seeding failed");
      }
    }

    logHeader("\nFull ATProto Suite Demo is Ready!");
    logInfo("  PDS:      http://localhost:2583");
    logInfo("  PLC:      http://localhost:2582");
    logInfo("  Relay:    http://localhost:2584");
    logInfo("  AppView:  http://localhost:3200");
    logInfo("  Chat:     http://localhost:2585");
    logInfo("  Video:    http://localhost:2586");
    logInfo("  Admin UI: http://localhost:2590");
    logInfo("  Smoke:    http://localhost:8081");
    console.log("");

    if (flags.collectDiagnostics) {
      await collectDiagnostics(toE2ERunContext(ctx, { diagnosticsDir: flags.diagnosticsDir }), { label: "full-suite-demo" });
    }

    if (!flags.keepRunning) {
      await stopBinaryServices(ctx, [...services]);
      uiChild.kill("SIGTERM");
    }
  });
