import { Command } from "@cliffy/command";
import { join } from "@std/path";
import {
  initRunDir,
  loadRunResourceManifest,
  mockProviderUrlsFromResourceManifest,
  repoRoot,
  serviceUrlsFromResourceManifest,
} from "@garazyk/schemat/runtime";
import {
  initLogger,
  logError,
  logHeader,
  logInfo,
  logOk,
  resolveTopology,
} from "@garazyk/schemat";
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

function portFromUrl(url: string): string {
  return new URL(url).port;
}

function toWebSocketUrl(url: string): string {
  return url.replace(/^http:\/\//, "ws://").replace(/^https:\/\//, "wss://")
    .replace(/\/$/, "");
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
    resourceManifestFile: ctx.resourceManifestFile,
    composeProject: ctx.composeProject,
  };
}

export const demoCommand = new Command()
  .description(
    "Start a full ATProto stack demo with seed data.\n\n" +
      "Starts PLC, PDS, Relay, AppView, Chat, Video, and the Admin UI. " +
      "By default seeds demo accounts and content.",
  )
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
    const topology = resolveTopology(
      Deno.env.get("ATPROTO_WEB_CLIENT") ?? undefined,
      Deno.env.get("ATPROTO_TOPOLOGY") ?? undefined,
    );
    const topologyServiceUrls = topology.serviceUrls;
    const pdsUrl = topologyServiceUrls.pds;
    const plcUrl = topologyServiceUrls.plc;
    const relayUrl = topologyServiceUrls.relay;
    const appviewUrl = topologyServiceUrls.appview;
    const chatUrl = topologyServiceUrls.chat;
    const videoUrl = topologyServiceUrls.video;
    const uiUrl = topologyServiceUrls.ui;
    const pdsPort = portFromUrl(pdsUrl);
    const uiPort = portFromUrl(uiUrl);
    const relaySubscribeUrl =
      `${toWebSocketUrl(relayUrl)}/xrpc/com.atproto.sync.subscribeRepos`;

    const PDS_MASTER_SECRET = Deno.env.get("PDS_MASTER_SECRET") ??
      generateHex();
    const PDS_ADMIN_PASSWORD = Deno.env.get("PDS_ADMIN_PASSWORD") ??
      generateHex(8);
    const APPVIEW_ADMIN_SECRET = Deno.env.get("APPVIEW_ADMIN_SECRET") ??
      generateHex(8);
    const CHAT_ADMIN_SECRET = Deno.env.get("CHAT_ADMIN_SECRET") ??
      generateHex(8);
    const VIDEO_ADMIN_SECRET = Deno.env.get("VIDEO_ADMIN_SECRET") ??
      generateHex(8);
    const UI_ADMIN_PASSWORD = Deno.env.get("UI_ADMIN_PASSWORD") ??
      generateHex(8);

    async function writePdsConfig(): Promise<string> {
      const config = {
        server: {
          host: "127.0.0.1",
          port: pdsPort,
          data_dir: join(ctx.runDir, "data", "pds"),
          issuer: pdsUrl,
          available_user_domains: ["test"],
        },
        appview: {
          url: appviewUrl,
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
        relays: [relayUrl],
        plc: {
          url: plcUrl,
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
      const services = [
        "plc",
        "pds",
        "relay",
        "appview",
        "chat",
        "video",
      ] as const;
      await stopBinaryServices(ctx, [...services]);
      logOk("Demo services stopped.");
      return;
    }

    if (flags.collectDiagnostics && !flags.stop) {
      await collectDiagnostics(
        toE2ERunContext(ctx, { diagnosticsDir: flags.diagnosticsDir }),
        { label: "full-suite-demo" },
      );
      return;
    }

    logHeader("Starting full ATProto suite demo...");

    const pdsConfigPath = await writePdsConfig();

    const services: Array<
      "plc" | "pds" | "relay" | "appview" | "chat" | "video"
    > = [
      "plc",
      "pds",
      "relay",
      "appview",
      "chat",
      "video",
    ];

    await startBinaryServices(ctx, {
      services,
      env: {
        pds: {
          PDS_PLC_URL: plcUrl,
          PDS_ISSUER: pdsUrl,
          PDS_MASTER_SECRET,
          PDS_ADMIN_PASSWORD,
          PDS_ALLOW_HTTP: "1",
          PDS_USE_BIOMETRIC_PROTECTION: "false",
          PDS_USE_KEYCHAIN: "false",
          PDS_PLC_KEYS_DIR: join(ctx.runDir, "data", "pds", "keys"),
        },
        relay: { RELAY_ADMIN_PASSWORD: APPVIEW_ADMIN_SECRET },
        appview: {
          APPVIEW_RELAY_URLS: relaySubscribeUrl,
          APPVIEW_ADMIN_SECRET,
          APPVIEW_MASTER_SECRET: PDS_MASTER_SECRET,
          APPVIEW_PLC_URL: plcUrl,
        },
        chat: {
          PDS_URL: pdsUrl,
          CHAT_ADMIN_SECRET,
        },
        video: {
          JELCZ_ADMIN_SECRET: VIDEO_ADMIN_SECRET,
          JELCZ_PDS_URL: pdsUrl,
        },
      },
      args: {
        pds: [
          "serve",
          "--config",
          pdsConfigPath,
          "--port",
          pdsPort,
          "--data-dir",
          join(ctx.runDir, "data", "pds"),
          "--foreground",
        ],
      },
    });

    const buildBin = Deno.env.get("BUILD_DIR") || join(root, "build/bin");
    const uiProc = new Deno.Command(join(buildBin, "garazyk-ui"), {
      args: ["serve", "--port", uiPort],
      env: {
        GARAZYK_UI_PDS_URL: pdsUrl,
        GARAZYK_UI_PLC_URL: plcUrl,
        GARAZYK_UI_RELAY_URL: relayUrl,
        GARAZYK_UI_APPVIEW_URL: appviewUrl,
        GARAZYK_UI_CHAT_URL: chatUrl,
        GARAZYK_UI_VIDEO_URL: videoUrl,
        GARAZYK_UI_PORT: uiPort,
        GARAZYK_UI_ADMIN_PASSWORD: UI_ADMIN_PASSWORD,
      },
    });
    const uiChild = uiProc.spawn();

    await addRelayUpstream(
      relayUrl,
      pdsUrl,
      APPVIEW_ADMIN_SECRET,
    );

    if (!flags.skipSeed) {
      logInfo("Seeding demo data...");
      const seedProc = new Deno.Command("deno", {
        args: ["run", "-A", join(root, "scripts", "seed_full_suite.ts")],
        env: {
          PDS_URL: pdsUrl,
          CHAT_URL: chatUrl,
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
    const runManifest = loadRunResourceManifest(ctx.resourceManifestFile);
    const runtimeServiceUrls = serviceUrlsFromResourceManifest(runManifest);
    const mockServiceUrls = mockProviderUrlsFromResourceManifest(runManifest);
    const serviceUrls: Record<string, string> = {
      pds: runtimeServiceUrls.pds ?? pdsUrl,
      plc: runtimeServiceUrls.plc ?? plcUrl,
      relay: runtimeServiceUrls.relay ?? relayUrl,
      appview: runtimeServiceUrls.appview ?? appviewUrl,
      chat: runtimeServiceUrls.chat ?? chatUrl,
      video: runtimeServiceUrls.video ?? videoUrl,
      ui: runtimeServiceUrls.ui ?? uiUrl,
    };
    if (mockServiceUrls.twilio) {
      serviceUrls["mock-twilio"] = mockServiceUrls.twilio;
    }
    const serviceLabels: Record<string, string> = {
      pds: "PDS",
      plc: "PLC",
      relay: "Relay",
      appview: "AppView",
      chat: "Chat",
      video: "Video",
      ui: "Admin UI",
      "mock-twilio": "Smoke",
    };
    for (const [name, url] of Object.entries(serviceUrls)) {
      const label = serviceLabels[name] || name;
      logInfo(`  ${label.padEnd(9)} ${url}`);
    }
    console.log("");

    if (flags.collectDiagnostics) {
      await collectDiagnostics(
        toE2ERunContext(ctx, { diagnosticsDir: flags.diagnosticsDir }),
        { label: "full-suite-demo" },
      );
    }

    if (!flags.keepRunning) {
      await stopBinaryServices(ctx, [...services]);
      uiChild.kill("SIGTERM");
    }
  });
