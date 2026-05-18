/**
 * CLI command for launching the full ATProto stack demo.
 * @module demo_command
 */

import { parseArgs } from "@std/cli/parse-args";
import { initRunDir, repoRoot } from "@garazyk/schemat/runtime";
import {
  initLogger,
  logError,
  logInfo,
  logOk,
  logHeader,
} from "@garazyk/schemat";
import {
  startBinaryServices,
  stopBinaryServices,
  addRelayUpstream,
  type BinaryServiceName,
} from "./binary_services.ts";
import { collectDiagnostics } from "./run_diagnostics.ts";
import { join } from "@std/path";

/** Entry point for the full-suite demo CLI. */
export async function demoCommandMain(argv: string[]) {
  const flags = parseArgs(argv, {
    boolean: ["skip-seed", "stop", "keep-running", "collect-diagnostics", "verbose", "quiet", "help"],
    string: ["run-id", "diagnostics-dir"],
    alias: { h: "help", v: "verbose", q: "quiet" },
  });

  if (flags.help) {
    console.log(`Usage: scripts/demo.ts [options]

Options:
  --skip-seed            Start services without seeding data
  --keep-running         Keep services running after smoke checks
  --stop                 Stop services for this run id
  --collect-diagnostics  Capture health responses and service logs
  --run-id ID            Reuse or name the shared e2e run directory
  --diagnostics-dir DIR  Write diagnostics to DIR
  -v, --verbose        Enable verbose logging
  -q, --quiet          Suppress non-error output
  --help               Show this help
`);
    return;
  }

  initLogger({ verbose: flags.verbose, quiet: flags.quiet });

  const root = await repoRoot();
  const ctx = initRunDir(flags["run-id"]);

  if (flags.stop) {
    await stopBinaryServices(ctx);
    logOk("All services stopped");
    return;
  }

  if (flags["collect-diagnostics"]) {
    await collectDiagnostics(ctx, { label: "full-suite-demo" });
    return;
  }

  const PDS_MASTER_SECRET = Deno.env.get("PDS_MASTER_SECRET") || "test-master-secret-123";
  const PDS_ADMIN_PASSWORD = Deno.env.get("PDS_ADMIN_PASSWORD") || "localdevadmin";
  const APPVIEW_ADMIN_SECRET = Deno.env.get("APPVIEW_ADMIN_SECRET") || "localdevadmin";
  const CHAT_ADMIN_SECRET = Deno.env.get("CHAT_ADMIN_SECRET") || "localdevadmin";
  const VIDEO_ADMIN_SECRET = Deno.env.get("VIDEO_ADMIN_SECRET") || "localdevadmin";
  const UI_ADMIN_PASSWORD = Deno.env.get("UI_ADMIN_PASSWORD") || "localdev";

  async function writePdsConfig() {
    const config = {
      server: {
        host: "127.0.0.1",
        port: 2583,
        data_dir: join(ctx.runDir, "data", "pds"),
        issuer: "http://127.0.0.1:2583",
        available_user_domains: ["test"]
      },
      appview: {
        url: "http://127.0.0.1:3200",
        did: "did:web:localhost"
      },
      database: { service_pool_max_size: 10, user_pool_max_size: 50 },
      logging: { format: "text", level: "info" },
      session: {
        access_token_ttl_seconds: 1800,
        refresh_token_ttl_seconds: 2592000,
        invite_code_required: false
      },
      registration: {
        invite_code_required: false,
        phone_verification_required: false,
        captcha_required: false,
        oauth_only_registration: false
      },
      relays: ["http://127.0.0.1:2584"],
      plc: { url: "http://127.0.0.1:2582", retry_count: 3, retry_delay_ms: 500 },
      cors: {
        allowed_origins: ["*"],
        allowed_methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"],
        allowed_headers: ["DPoP", "Authorization", "Content-Type", "*"],
        max_age: 86400
      },
      auth: { master_secret: PDS_MASTER_SECRET }
    };
    const configPath = join(ctx.runDir, "data", "config", "pds-config.json");
    await Deno.mkdir(join(ctx.runDir, "data", "config"), { recursive: true });
    await Deno.writeTextFile(configPath, JSON.stringify(config, null, 2));
    return configPath;
  }

  logHeader("Starting full ATProto suite demo...");
  
  const pdsConfigPath = await writePdsConfig();

  const services: BinaryServiceName[] = ["plc", "pds", "relay", "appview", "chat", "video"];
  
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
      }
    },
    args: {
      pds: [
        "serve",
        "--config", pdsConfigPath,
        "--port", "2583",
        "--data-dir", join(ctx.runDir, "data", "pds"),
        "--foreground"
      ]
    }
  });

  // Start UI
  logInfo("Starting Admin UI (garazyk-ui)...");
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

  // Wiring
  await addRelayUpstream("http://127.0.0.1:2584", "http://127.0.0.1:2583", APPVIEW_ADMIN_SECRET);

  // Seeding
  if (!flags["skip-seed"]) {
    logInfo("Seeding demo data...");
    const seedProc = new Deno.Command("deno", {
      args: ["run", "-A", join(root, "scripts", "seed_full_suite.ts")],
      env: {
        PDS_URL: "http://127.0.0.1:2583",
        CHAT_URL: "http://127.0.0.1:2585",
      }
    });
    const { code } = await seedProc.output();
    if (code === 0) {
      logOk("Seeding completed");
    } else {
      logError("Seeding failed");
    }
  }

  logHeader("\nFull ATProto Suite Demo is Ready!");
  logInfo(`PLC:      http://127.0.0.1:2582`);
  logInfo(`PDS:      http://127.0.0.1:2583`);
  logInfo(`Relay:    http://127.0.0.1:2584`);
  logInfo(`AppView:  http://127.0.0.1:3200`);
  logInfo(`Chat:     http://127.0.0.1:2585`);
  logInfo(`Video:    http://127.0.0.1:2586`);
  logInfo(`Admin UI: http://127.0.0.1:2590/admin`);

  if (flags["keep-running"]) {
    logInfo("Keeping services running. Press Ctrl+C to stop.");
    await new Promise(() => {}); 
  } else {
    logInfo("Smoke completed; cleaning up now. Use --keep-running to leave services up.");
    await stopBinaryServices(ctx);
    try { uiChild.kill(); } catch { /* ignore */ }
  }
}
