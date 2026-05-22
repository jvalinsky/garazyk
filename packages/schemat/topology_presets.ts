import { fromFileUrl, resolve } from "@std/path";
import type { WebClientTopology } from "./topology_types.ts";
import {
  defineTopology,
  health as topologyHealth,
  port,
  role,
  serviceRef,
  source,
  volume,
} from "./topology_authoring.ts";
import type { RegisteredTopologyPreset } from "./topology_authoring.ts";
import { Cap, Role } from "./topology_registry.ts";

/** Absolute path to the repo root for sidecar bind mounts. */
const REPO_ROOT = resolve(
  fromFileUrl(new URL("../..", import.meta.url)),
);

/**
 * Central registry for ATProto network topologies.
 * Allows for embedded presets and runtime registration.
 */
export class TopologyRegistry {
  private static presets: Map<string, RegisteredTopologyPreset> = new Map();
  private static webClients: Map<string, WebClientTopology> = new Map();

  /** Register a topology preset programmatically. */
  static register(preset: RegisteredTopologyPreset): void {
    this.presets.set(preset.name, preset);
  }

  /** Register a web client preset programmatically. */
  static registerWebClient(client: WebClientTopology): void {
    this.webClients.set(client.name, client);
  }

  /** Get a preset by name. */
  static getPreset(name: string): RegisteredTopologyPreset | undefined {
    return this.presets.get(name);
  }

  /** Get a web client by name. */
  static getWebClient(name: string): WebClientTopology | undefined {
    return this.webClients.get(name);
  }

  /** List all registered preset names. */
  static listPresets(): string[] {
    return Array.from(this.presets.keys()).sort();
  }

  /** List all registered web client names. */
  static listWebClients(): string[] {
    return Array.from(this.webClients.keys()).sort();
  }
}

// ---------------------------------------------------------------------------
// Built-in Web Clients
// ---------------------------------------------------------------------------

interface RuntimeEnv {
  Deno?: {
    env?: {
      get(name: string): string | undefined;
    };
  };
}

function readEnv(name: string): string | undefined {
  try {
    return (globalThis as RuntimeEnv).Deno?.env?.get(name) || undefined;
  } catch {
    return undefined;
  }
}

const publicWebUrl = readEnv("WEB_CLIENT_URL") || "http://localhost:2591";
const internalWebUrl = readEnv("WEB_CLIENT_INTERNAL_URL") ||
  "http://web-client:2590";

function health(url: string) {
  return {
    url,
    intervalSeconds: 5,
    timeoutSeconds: 5,
    retries: 30,
    startPeriodSeconds: 20,
  };
}

const BUILTIN_WEB_CLIENTS: WebClientTopology[] = [
  {
    name: "garazyk-ui",
    source: "local://garazyk-ui",
    ref: readEnv("GARAZYK_WEB_CLIENT_REF") || "workspace",
    buildPreset: "garazyk-ui",
    serveCommand: ["garazyk-ui", "serve", "--port", "2590"],
    publicUrl: publicWebUrl,
    internalUrl: internalWebUrl,
    env: {
      GARAZYK_UI_PDS_URL: "http://local-pds:2583",
      GARAZYK_UI_PLC_URL: "http://local-plc:2582",
      GARAZYK_UI_RELAY_URL: "http://local-relay:2584",
      GARAZYK_UI_APPVIEW_URL: "http://local-appview:3200",
      GARAZYK_UI_ADMIN_PASSWORD: "changeme",
    },
    healthCheck: health(`${internalWebUrl}/lab`),
    oauthRedirects: [`${publicWebUrl}/lab/callback`],
    capabilities: ["smoke", "login", "oauth", "admin"],
    browserFlow: {
      smoke: "scripts/scenarios/browser/garazyk-ui_smoke.ts",
      login: "scripts/scenarios/browser/garazyk-ui_login.ts",
      deep: "scripts/scenarios/browser/garazyk-ui_deep.ts",
    },
  },
  {
    name: "skylab",
    source: "https://github.com/bluesky-social/social-app.git",
    ref: readEnv("SKYLAB_WEB_CLIENT_REF") || "main",
    buildPreset: "social-app",
    serveCommand: ["yarn", "web", "--host", "0.0.0.0", "--port", "2590"],
    publicUrl: publicWebUrl,
    internalUrl: internalWebUrl,
    env: {
      EXPO_PUBLIC_ENV: "test",
      EXPO_PUBLIC_BSKY_SERVICE: "http://local-appview:3200",
      EXPO_PUBLIC_PDS_SERVICE_URL: "http://local-pds:2583",
      EXPO_PUBLIC_PLC_URL: "http://local-plc:2582",
      ATPROTO_SERVICE_HOST: "local-appview:3200",
    },
    healthCheck: health(internalWebUrl),
    oauthRedirects: [`${publicWebUrl}/oauth/callback`, `${publicWebUrl}/`],
    capabilities: ["smoke", "login", "deep", "compose", "timeline", "profiles"],
    browserFlow: {
      smoke: "scripts/scenarios/browser/social-app_smoke.ts",
      login: "scripts/scenarios/browser/social-app_login.ts",
      deep: "scripts/scenarios/browser/social-app_deep.ts",
    },
  },
  {
    name: "bluesky-social/social-app",
    source: "https://github.com/bluesky-social/social-app.git",
    ref: readEnv("SOCIAL_APP_WEB_CLIENT_REF") || "main",
    buildPreset: "social-app",
    serveCommand: ["yarn", "web", "--host", "0.0.0.0", "--port", "2590"],
    publicUrl: publicWebUrl,
    internalUrl: internalWebUrl,
    env: {
      EXPO_PUBLIC_ENV: "test",
      EXPO_PUBLIC_BSKY_SERVICE: "http://local-appview:3200",
      EXPO_PUBLIC_PDS_SERVICE_URL: "http://local-pds:2583",
      EXPO_PUBLIC_PLC_URL: "http://local-plc:2582",
      ATPROTO_SERVICE_HOST: "local-appview:3200",
    },
    healthCheck: health(internalWebUrl),
    oauthRedirects: [`${publicWebUrl}/oauth/callback`, `${publicWebUrl}/`],
    capabilities: ["smoke", "login", "deep", "compose", "timeline", "profiles"],
    browserFlow: {
      smoke: "scripts/scenarios/browser/social-app_smoke.ts",
      login: "scripts/scenarios/browser/social-app_login.ts",
      deep: "scripts/scenarios/browser/social-app_deep.ts",
    },
  },
  {
    name: "jollywhoppers.com/witchsky.app",
    source: "https://tangled.org/jollywhoppers.com/witchsky.app",
    ref: readEnv("WITCHSKY_WEB_CLIENT_REF") || "main",
    buildPreset: "witchsky",
    serveCommand: ["yarn", "web", "--host", "0.0.0.0", "--port", "2590"],
    publicUrl: publicWebUrl,
    internalUrl: internalWebUrl,
    env: {
      EXPO_PUBLIC_ENV: "test",
      EXPO_PUBLIC_BSKY_SERVICE: "http://local-appview:3200",
      EXPO_PUBLIC_PDS_SERVICE_URL: "http://local-pds:2583",
      EXPO_PUBLIC_PLC_URL: "http://local-plc:2582",
      ATPROTO_SERVICE_HOST: "local-appview:3200",
      WITCHSKY_E2E_MODE: "1",
    },
    healthCheck: health(internalWebUrl),
    oauthRedirects: [`${publicWebUrl}/oauth/callback`, `${publicWebUrl}/`],
    capabilities: ["smoke", "login", "deep", "compose", "timeline", "profiles"],
    browserFlow: {
      smoke: "scripts/scenarios/browser/social-app_smoke.ts",
      login: "scripts/scenarios/browser/social-app_login.ts",
      deep: "scripts/scenarios/browser/witchsky_deep.ts",
    },
  },
];

for (const client of BUILTIN_WEB_CLIENTS) {
  TopologyRegistry.registerWebClient(client);
}

// ---------------------------------------------------------------------------
// Built-in Presets
// ---------------------------------------------------------------------------

const localBuild = source.localBuild({
  buildContext: "docker/local-network",
  dockerfile: "Dockerfile.local",
});

const plcCaps = [
  Cap.plc.createAccount,
  Cap.plc.didResolution,
  Cap.plc.operationLog,
  Cap.plc.handleRotation,
  Cap.plc.quotaEnforcement,
] as const;

const pdsCoreCaps = [
  Cap.pds.describeServer,
  Cap.pds.createAccount,
  Cap.pds.createSession,
  Cap.pds.getSession,
  Cap.pds.createRecord,
  Cap.pds.getRecord,
  Cap.pds.deleteRecord,
  Cap.pds.listRecords,
  Cap.pds.uploadBlob,
  Cap.pds.getBlob,
  Cap.pds.listBlobs,
  Cap.pds.resolveHandle,
  Cap.pds.updateHandle,
  Cap.pds.subscribeRepos,
  Cap.pds.getHead,
  Cap.pds.getRepo,
  Cap.pds.requestCrawl,
  Cap.pds.admin,
  Cap.pds.sync,
] as const;

const pdsFullCaps = [
  ...pdsCoreCaps,
  Cap.pds.repo,
  Cap.pds.identity,
  Cap.pds.blob,
] as const;

const pds2CoreCaps = [
  Cap.pds2.describeServer,
  Cap.pds2.createAccount,
  Cap.pds2.createSession,
  Cap.pds2.getSession,
  Cap.pds2.createRecord,
  Cap.pds2.getRecord,
  Cap.pds2.deleteRecord,
  Cap.pds2.listRecords,
  Cap.pds2.uploadBlob,
  Cap.pds2.getBlob,
  Cap.pds2.listBlobs,
  Cap.pds2.resolveHandle,
  Cap.pds2.updateHandle,
  Cap.pds2.subscribeRepos,
  Cap.pds2.getHead,
  Cap.pds2.getRepo,
  Cap.pds2.requestCrawl,
  Cap.pds2.admin,
  Cap.pds2.sync,
] as const;

const relayBasicCaps = [
  Cap.relay.subscribeRepos,
  Cap.relay.requestCrawl,
  Cap.relay.healthCheck,
] as const;

const appviewBasicCaps = [
  Cap.appview.getTimeline,
  Cap.appview.getProfile,
  Cap.appview.getFeed,
  Cap.appview.search,
  Cap.appview.backfill,
  Cap.appview.admin,
] as const;

const appviewSocialCaps = [
  Cap.appview.getTimeline,
  Cap.appview.getProfile,
  Cap.appview.getFeed,
  Cap.appview.search,
  Cap.appview.posts,
  Cap.appview.likes,
  Cap.appview.reposts,
  Cap.appview.follows,
  Cap.appview.blocks,
  Cap.appview.labels,
  Cap.appview.lists,
  Cap.appview.mutes,
  Cap.appview.notifications,
  Cap.appview.feeds,
] as const;

const uiBasicCaps = [
  Cap.ui.admin,
  Cap.ui.login,
  Cap.ui.oauth,
  Cap.ui.smoke,
] as const;

function pdsVolumes(name: string, config: string) {
  return [
    volume.named(`${name}_data`, "/var/lib/atprotopds"),
    volume.bind(config, "/var/lib/atprotopds/config.json", "ro"),
    volume.named(`${name}_keys`, "/var/lib/atprotopds/keys"),
  ];
}

function generateHex(bytes = 32): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const PDS_MASTER_SECRET = Deno.env.get("PDS_MASTER_SECRET") ??
  generateHex();
const PDS_ADMIN_PASSWORD = Deno.env.get("PDS_ADMIN_PASSWORD") ??
  "admin-localdev";
const APPVIEW_ADMIN_SECRET = Deno.env.get("APPVIEW_ADMIN_SECRET") ??
  "localdevadmin";
const UI_ADMIN_PASSWORD = Deno.env.get("GARAZYK_UI_ADMIN_PASSWORD") ??
  Deno.env.get("UI_ADMIN_PASSWORD") ??
  "admin-localdev";

function localPdsEnv() {
  return {
    TZ: "UTC",
    PDS_ALLOW_PRIVATE_SSRF: "1",
    PDS_ALLOW_HTTP: "1",
    PDS_LEXICON_PATH: "/usr/share/atprotopds/lexicons",
    HOME: "/var/lib/atprotopds",
    PDS_RATELIMIT_ENABLED: "false",
    PDS_MASTER_SECRET,
    PDS_ADMIN_PASSWORD,
    PDS_PHONE_VERIFICATION_PROVIDER: "twilio",
    TWILIO_ACCOUNT_SID: "AC00000000000000000000000000000000",
    TWILIO_AUTH_TOKEN: "SK00000000000000000000000000000000",
    TWILIO_VERIFY_SERVICE_SID: "VA00000000000000000000000000000000",
    TWILIO_API_BASE_URL: "http://local-mock-twilio:8081",
  };
}

const GARAZYK_DEFAULT = defineTopology({
  name: "garazyk-default",
  description:
    "Full Garazyk stack: PDS (kaszlak), Relay (zuk), PLC (campagnola), AppView (syrena), Chat (syrena-chat), Video (jelcz). Built from local source.",
  roles: {
    [Role.plc]: role.plc({
      name: "campagnola",
      source: localBuild,
      entrypoint: ["/usr/local/bin/campagnola"],
      command: [
        "serve",
        "--host",
        "0.0.0.0",
        "--port",
        "2582",
        "--database",
        "/var/lib/atprotopds/plc.db",
      ],
      env: {
        TZ: "UTC",
        PLC_HOURLY_LIMIT: "500",
        PLC_DAILY_LIMIT: "1000",
        PLC_WEEKLY_LIMIT: "5000",
      },
      ports: [port(2582)],
      volumes: [volume.named("local_plc_data", "/var/lib/atprotopds")],
      health: topologyHealth.http("/_health"),
      capabilities: plcCaps,
    }),
    [Role.pds]: role.pds({
      name: "kaszlak",
      source: localBuild,
      command: [
        "serve",
        "--config",
        "/var/lib/atprotopds/config.json",
        "--foreground",
      ],
      env: localPdsEnv(),
      ports: [port(2583)],
      volumes: pdsVolumes("local_pds", "./pds-config.json"),
      health: topologyHealth.http("/xrpc/com.atproto.server.describeServer"),
      capabilities: pdsCoreCaps,
      dependsOnRoles: [Role.plc],
      sidecars: {
        "local-mock-twilio": {
          source: source.image("denoland/deno:alpine"),
          entrypoint: [
            "deno",
            "run",
            "-A",
            "--config",
            "/workspace/deno.json",
          ],
          command: [
            "/workspace/packages/hamownia/mock_twilio_server.ts",
            "--port=8081",
          ],
          env: { DENO_DIR: "/deno-dir" },
          ports: [port(8081)],
          volumes: [
            volume.bind(REPO_ROOT, "/workspace", "ro"),
            volume.named("deno_cache", "/deno-dir"),
          ],
          health: topologyHealth.command([
            "CMD-SHELL",
            "wget -qO- http://127.0.0.1:8081/__control/health || exit 1",
          ]),
        },
      },
    }),
    [Role.pds2]: role.pds2({
      name: "kaszlak-pds2",
      source: localBuild,
      command: [
        "serve",
        "--config",
        "/var/lib/atprotopds/config.json",
        "--foreground",
      ],
      env: localPdsEnv(),
      ports: [port({ host: 2587, container: 2585 })],
      volumes: pdsVolumes("local_pds2", "./pds2-config.json"),
      health: topologyHealth.http("/xrpc/com.atproto.server.describeServer"),
      capabilities: pds2CoreCaps,
      dependsOnRoles: [Role.plc],
    }),
    [Role.relay]: role.relay({
      name: "zuk",
      source: localBuild,
      entrypoint: ["/usr/local/bin/zuk"],
      command: [
        "serve",
        "--upstream",
        "ws://local-pds:2583/xrpc/com.atproto.sync.subscribeRepos",
        "--port",
        "2584",
      ],
      env: {
        HOME: "/var/lib/atprotopds",
      },
      ports: [port(2584)],
      volumes: [volume.named("local_relay_data", "/var/lib/atprotopds")],
      health: topologyHealth.http("/api/relay/health"),
      capabilities: relayBasicCaps,
      dependsOnRoles: [Role.pds],
    }),
    [Role.appview]: role.appview({
      name: "syrena",
      source: localBuild,
      entrypoint: ["/usr/local/bin/syrena"],
      command: [
        "serve",
        "--relay",
        "ws://local-relay:2584",
        "--port",
        "3200",
        "--no-backfill",
      ],
      env: {
        APPVIEW_ADMIN_SECRET,
        APPVIEW_PLC_URL: "http://local-plc:2582",
        APPVIEW_PDS_URL: "http://local-pds:2583",
      },
      ports: [port(3200)],
      volumes: [volume.named("local_appview_data", "/var/lib/atprotopds")],
      health: topologyHealth.http({
        path: "/admin/backfill/status",
        headers: { Authorization: `Bearer ${APPVIEW_ADMIN_SECRET}` },
      }),
      capabilities: appviewBasicCaps,
      dependsOnRoles: [Role.relay],
    }),
    [Role.chat]: role.chat({
      name: "syrena-chat",
      source: localBuild,
      entrypoint: ["/usr/local/bin/syrena-chat"],
      command: ["serve", "--port", "2585"],
      ports: [port(2585)],
      volumes: [volume.named("local_chat_data", "/var/lib/atprotopds")],
      health: topologyHealth.http("/_health"),
      capabilities: [Cap.chat.dm, Cap.chat.chat],
      dependsOnRoles: [Role.pds],
    }),
    [Role.video]: role.video({
      name: "jelcz",
      source: localBuild,
      entrypoint: ["/usr/local/bin/jelcz"],
      command: ["serve", "--port", "2586"],
      ports: [port(2586)],
      volumes: [volume.named("local_video_data", "/var/lib/atprotopds")],
      health: topologyHealth.http("/_health"),
      capabilities: [Cap.video.uploadVideo, Cap.video.getVideoStatus],
      dependsOnRoles: [Role.pds],
    }),
    [Role.ui]: role.ui({
      name: "garazyk-ui",
      source: localBuild,
      entrypoint: ["/usr/local/bin/garazyk-ui"],
      command: [
        "serve",
        "--host",
        "0.0.0.0",
        "--port",
        "2590",
      ],
      env: {
        TZ: "UTC",
        GARAZYK_UI_PORT: "2590",
        GARAZYK_UI_ADMIN_PASSWORD: UI_ADMIN_PASSWORD,
        GARAZYK_UI_PDS_URL: "http://local-pds:2583",
        GARAZYK_UI_PDS_PASSWORD: PDS_ADMIN_PASSWORD,
        GARAZYK_UI_PLC_URL: "http://local-plc:2582",
        GARAZYK_UI_RELAY_URL: "http://local-relay:2584",
        GARAZYK_UI_APPVIEW_URL: "http://local-appview:3200",
        GARAZYK_UI_APPVIEW_TOKEN: APPVIEW_ADMIN_SECRET,
        GARAZYK_UI_CHAT_URL: "http://local-chat:2585",
        GARAZYK_UI_VIDEO_URL: "http://local-video:2586",
      },
      ports: [port(2590)],
      health: topologyHealth.http("/lab"),
      capabilities: uiBasicCaps,
      dependsOnRoles: [Role.pds, Role.appview],
      scenarioEnv: {
        GARAZYK_UI_ADMIN_PASSWORD: UI_ADMIN_PASSWORD,
      },
    }),
  },
  networkAliases: {
    "local-appview": ["bsky.app"],
  },
});

const REFERENCE_PDS = defineTopology({
  name: "reference-pds",
  description:
    "Bluesky reference PDS (TypeScript) with Garazyk Relay, PLC, and AppView.",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.pds({
      name: "reference-pds",
      source: source.git({
        repo: "https://github.com/bluesky-social/pds.git",
        ref: "v0.4.219",
      }),
      command: ["--port", "2583"],
      env: {
        PDS_HOSTNAME: "localhost",
        PDS_JETSTREAM_URL: "ws://local-relay:2584",
        PDS_BLOB_CACHE_LOC: "/tmp/pds-blob-cache",
        PDS_DIDPLC_URL: "http://local-plc:2582",
      },
      ports: [port(2583)],
      volumes: [volume.named("ref_pds_data", "/data")],
      health: topologyHealth.http("/xrpc/com.atproto.server.describeServer"),
      capabilities: pdsCoreCaps,
      dependsOnRoles: [Role.plc],
    }),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.inherit("garazyk-default"),
  },
});

const REFERENCE_PLC = defineTopology({
  name: "reference-plc",
  description:
    "Bluesky reference PLC directory server (TypeScript, did-method-plc) with Garazyk PDS, Relay, and AppView.",
  roles: {
    [Role.plc]: role.plc({
      name: "reference-plc",
      source: source.git({
        repo: "https://github.com/did-method-plc/did-method-plc.git",
        ref: "main",
        dockerfile: "packages/server/Dockerfile",
      }),
      command: ["node", "--enable-source-maps", "index.js"],
      env: {
        PORT: "2582",
        NODE_ENV: "production",
        DB_CREDS_JSON:
          '{"host":"local-plc-db","port":5432,"username":"plc","password":"plc","database":"plc"}',
        ENABLE_MIGRATIONS: "true",
        DB_MIGRATE_CREDS_JSON:
          '{"host":"local-plc-db","port":5432,"username":"plc","password":"plc","database":"plc"}',
        DEBUG_MODE: "1",
        LOG_ENABLED: "true",
        LOG_LEVEL: "debug",
      },
      ports: [port(2582)],
      health: topologyHealth.command([
        "CMD-SHELL",
        "wget -qO- http://localhost:2582/_health || exit 1",
      ]),
      capabilities: plcCaps,
      dependsOn: [serviceRef("local-plc-db")],
      sidecars: {
        "local-plc-db": {
          source: source.image("postgres:16-alpine"),
          env: {
            POSTGRES_USER: "plc",
            POSTGRES_PASSWORD: "plc",
            POSTGRES_DB: "plc",
          },
          volumes: [
            volume.named("ref_plc_pg_data", "/var/lib/postgresql/data"),
          ],
          health: topologyHealth.command(["CMD-SHELL", "pg_isready -U plc"]),
        },
      },
    }),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.pds2]: role.inherit("garazyk-default"),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.inherit("garazyk-default"),
    [Role.chat]: role.inherit("garazyk-default"),
    [Role.video]: role.inherit("garazyk-default"),
  },
});

const APPVIEWLITE = defineTopology({
  name: "appviewlite",
  description:
    "AppViewLite (C#/.NET 9, alnkesq) with Garazyk PDS, Relay, and PLC.",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.pds2]: role.inherit("garazyk-default"),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.appview({
      name: "appviewlite",
      source: source.git({
        repo: "https://github.com/alnkesq/AppViewLite.git",
        ref: "main",
        dockerDir: "src",
      }),
      command: ["dotnet", "AppViewLite.Web.dll"],
      env: {
        APPVIEWLITE_DIRECTORY: "/data",
        APPVIEWLITE_BIND_URLS: "http://+:3200",
        APPVIEWLITE_ALLOW_NEW_DATABASE: "1",
        APPVIEWLITE_PLC_DIRECTORY: "http://local-plc:2582",
        APPVIEWLITE_FIREHOSES:
          "ws://local-relay:2584/xrpc/com.atproto.sync.subscribeRepos",
        APPVIEWLITE_LISTEN_TO_FIREHOSE: "1",
        APPVIEWLITE_LISTEN_TO_PLC_DIRECTORY: "1",
        APPVIEWLITE_ADMINISTRATIVE_DIDS: "*",
        APPVIEWLITE_QUICK_REVERSE_BACKFILL_INSTANCE: "-",
      },
      ports: [port(3200)],
      volumes: [volume.named("appviewlite_data", "/data")],
      health: topologyHealth.http("/"),
      capabilities: [
        ...appviewSocialCaps,
        Cap.appview.video,
        Cap.appview.mediaGrid,
        Cap.appview.dataExport,
        Cap.appview.multiProtocol,
      ],
      dependsOnRoles: [Role.relay],
    }),
  },
});

const INDIGO_RELAY = defineTopology({
  name: "indigo-relay",
  description: "Garazyk PDS with indigo Relay (Go).",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.relay]: role.relay({
      name: "indigo-relay",
      source: source.git({
        repo: "https://github.com/bluesky-social/indigo.git",
        ref: "main",
        dockerfile: "cmd/relay/Dockerfile",
      }),
      command: [
        "run",
        "--listen-addr",
        "0.0.0.0:2584",
        "--upstream",
        "ws://local-pds:2583/xrpc/com.atproto.sync.subscribeRepos",
      ],
      env: { RELAY_DIDPLC_URL: "http://local-plc:2582" },
      ports: [port(2584)],
      volumes: [volume.named("indigo_relay_data", "/data")],
      health: topologyHealth.http("/xrpc/com.atproto.sync.subscribeRepos"),
      capabilities: relayBasicCaps,
      dependsOnRoles: [Role.pds],
    }),
    [Role.appview]: role.inherit("garazyk-default"),
  },
});

const RSKY_PDS = defineTopology({
  name: "rsky-pds",
  description: "Garazyk stack with rsky-pds (Rust, blacksky-algorithms).",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.pds({
      name: "rsky-pds",
      source: source.git({
        repo: "https://github.com/blacksky-algorithms/rsky.git",
        ref: "main",
        overlayDir: "docker/rsky-pds",
      }),
      env: {
        PDS_HOSTNAME: "localhost",
        PDS_PORT: "2583",
        PDS_DEV_MODE: "true",
        PDS_INVITE_REQUIRED: "false",
        PDS_DID_PLC_URL: "http://local-plc:2582",
        PDS_SERVICE_HANDLE_DOMAINS: ".test",
        PDS_CRAWLERS: "http://local-relay:2584",
        DATABASE_URL: "postgres://pds:pds@local-pds-db:5432/pds",
        AWS_ENDPOINT: "http://local-pds-s3:3900",
        AWS_ACCESS_KEY_ID: "GKlocaltopologyaccesskey",
        AWS_SECRET_ACCESS_KEY: "localtopologysecretkey1234567890abcdef",
        AWS_ENDPOINT_BUCKET: "local-pds-s3",
        AWS_REGION: "garage",
        ROCKET_ADDRESS: "0.0.0.0",
        ROCKET_PORT: "2583",
      },
      ports: [port(2583)],
      volumes: [volume.named("rsky_pds_data", "/usr/src/rsky")],
      health: topologyHealth.command([
        "CMD-SHELL",
        "wget -qO- http://localhost:2583/health || exit 1",
      ]),
      capabilities: [
        Cap.pds.describeServer,
        Cap.pds.createAccount,
        Cap.pds.createSession,
        Cap.pds.getSession,
        Cap.pds.createRecord,
        Cap.pds.getRecord,
        Cap.pds.deleteRecord,
        Cap.pds.listRecords,
        Cap.pds.uploadBlob,
        Cap.pds.getBlob,
        Cap.pds.listBlobs,
        Cap.pds.resolveHandle,
        Cap.pds.updateHandle,
        Cap.pds.subscribeRepos,
        Cap.pds.getHead,
        Cap.pds.getRepo,
        Cap.pds.requestCrawl,
        Cap.pds.admin,
        Cap.pds.repo,
        Cap.pds.identity,
        Cap.pds.blob,
        Cap.pds.sync,
      ],
      dependsOn: [serviceRef("local-pds-db"), serviceRef("local-pds-s3")],
      sidecars: {
        "local-pds-db": {
          source: source.image("postgres:16-alpine"),
          env: {
            POSTGRES_USER: "pds",
            POSTGRES_PASSWORD: "pds",
            POSTGRES_DB: "pds",
          },
          volumes: [
            volume.named("rsky_pds_pg_data", "/var/lib/postgresql/data"),
          ],
          health: topologyHealth.command(["CMD-SHELL", "pg_isready -U pds"]),
        },
        "local-pds-s3": {
          source: source.image("dxflrs/garage:v2.3.0"),
          command: ["/garage", "server", "--single-node", "--default-bucket"],
          env: {
            GARAGE_DEFAULT_ACCESS_KEY: "GKlocaltopologyaccesskey",
            GARAGE_DEFAULT_SECRET_KEY: "localtopologysecretkey1234567890abcdef",
            GARAGE_DEFAULT_BUCKET: "default-bucket",
          },
          volumes: [
            volume.named("rsky_pds_garage_meta", "/var/lib/garage/meta"),
            volume.named("rsky_pds_garage_data", "/var/lib/garage/data"),
          ],
          health: topologyHealth.command([
            "CMD-SHELL",
            "wget -qO- http://localhost:3900/health || exit 1",
          ]),
        },
      },
    }),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.inherit("garazyk-default"),
  },
});

const RSKY_RELAY = defineTopology({
  name: "rsky-relay",
  description: "Garazyk PDS with rsky-relay (Rust).",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.relay]: role.relay({
      name: "rsky-relay",
      source: source.git({
        repo: "https://github.com/blacksky-algorithms/rsky.git",
        ref: "fd88a2740da299377ee08cf4e76f80e4ad45fc4a",
        overlayDir: "docker/rsky-relay",
      }),
      command: ["rsky-relay", "--no-plc-export"],
      env: {
        RELAY_PORT: "2584",
        RELAY_CRAWL_SCHEME: "ws",
        RELAY_PLC_URL: "http://local-plc:2582",
        RELAY_DISCOVERY_UPSTREAMS: "",
        RELAY_DISCOVERY_ALLOW_HTTP: "true",
        RELAY_DB_PATH: "/data/db",
        RUST_LOG: "rsky_relay=debug,info",
      },
      ports: [port(2584)],
      volumes: [volume.named("rsky_relay_data", "/data")],
      health: topologyHealth.command([
        "CMD-SHELL",
        "wget -qO- http://localhost:2584/xrpc/com.atproto.sync.subscribeRepos || exit 1",
      ]),
      capabilities: relayBasicCaps,
      dependsOnRoles: [Role.pds],
    }),
    [Role.appview]: role.inherit("garazyk-default"),
  },
});

const ALLEGEDLY_PLC = defineTopology({
  name: "allegedly-plc",
  description:
    "Allegedly PLC mirror/wrapper (Rust) wrapping the reference PLC server.",
  roles: {
    [Role.plc]: role.plc({
      name: "allegedly-plc",
      source: source.git({
        repo: "https://tangled.org/microcosm.blue/Allegedly",
        ref: "main",
        dockerfileOverlay: "docker/allegedly/Dockerfile",
      }),
      command: [
        "allegedly",
        "mirror",
        "--upstream",
        "http://local-ref-plc:3000",
        "--wrap",
        "http://local-ref-plc:3000",
        "--bind",
        "0.0.0.0:2582",
      ],
      env: {
        ALLEGEDLY_WRAP_PG: "postgres://plc:plc@local-plc-db:5432/plc",
        RUST_LOG: "allegedly=debug,info",
      },
      ports: [port(2582)],
      volumes: [volume.named("allegedly_plc_data", "/data")],
      health: topologyHealth.command([
        "CMD-SHELL",
        "wget -qO- http://localhost:2582/ || exit 1",
      ]),
      capabilities: plcCaps,
      dependsOn: [serviceRef("local-ref-plc"), serviceRef("local-plc-db")],
      sidecars: {
        "local-ref-plc": {
          source: source.git({
            repo: "https://github.com/did-method-plc/did-method-plc.git",
            ref: "244abb5f6a75916984d5853df34d7bcefc4d2faf",
            dockerfile: "packages/server/Dockerfile",
          }),
          command: ["node", "--enable-source-maps", "index.js"],
          env: {
            PORT: "3000",
            NODE_ENV: "production",
            DB_CREDS_JSON:
              '{"host":"local-plc-db","port":5432,"username":"plc","password":"plc","database":"plc"}',
            ENABLE_MIGRATIONS: "true",
            DB_MIGRATE_CREDS_JSON:
              '{"host":"local-plc-db","port":5432,"username":"plc","password":"plc","database":"plc"}',
            DEBUG_MODE: "1",
            LOG_ENABLED: "true",
            LOG_LEVEL: "debug",
          },
          health: topologyHealth.command([
            "CMD-SHELL",
            "wget -qO- http://localhost:3000/_health || exit 1",
          ]),
          dependsOn: [serviceRef("local-plc-db")],
        },
        "local-plc-db": {
          source: source.image("postgres:16-alpine"),
          env: {
            POSTGRES_USER: "plc",
            POSTGRES_PASSWORD: "plc",
            POSTGRES_DB: "plc",
          },
          volumes: [
            volume.named("allegedly_plc_pg_data", "/var/lib/postgresql/data"),
          ],
          health: topologyHealth.command(["CMD-SHELL", "pg_isready -U plc"]),
        },
      },
    }),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.pds2]: role.inherit("garazyk-default"),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.inherit("garazyk-default"),
  },
});

const HAPPYVIEW = defineTopology({
  name: "happyview",
  description:
    "HappyView (TypeScript/Rust, trezy) with Garazyk PDS, Relay, and PLC.",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.pds2]: role.inherit("garazyk-default"),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.appview({
      name: "happyview",
      source: source.git({
        repo: "https://github.com/gamesgamesgamesgamesgames/happyview.git",
        ref: "v2.7.0",
        buildArgs: { HAPPYVIEW_VERSION: "2.7.0" },
      }),
      env: {
        DATABASE_URL: "sqlite:///data/happyview.db?mode=rwc",
        PUBLIC_URL: "http://localhost:3200",
        SESSION_SECRET: "localdev-session-secret",
        RELAY_URL: "ws://local-relay:2584/xrpc/com.atproto.sync.subscribeRepos",
        PORT: "3200",
      },
      ports: [port({ host: 3200, container: 3000 })],
      volumes: [volume.named("happyview_data", "/data")],
      health: topologyHealth.http("/"),
      capabilities: [
        ...appviewBasicCaps,
        Cap.appview.xrpcEndpoints,
        Cap.appview.oauth,
        Cap.appview.realTimeSync,
        Cap.appview.lexiconDriven,
        Cap.appview.luaScripting,
        Cap.appview.indexHooks,
        Cap.appview.networkLexicons,
        Cap.appview.hotReloading,
        Cap.appview.adminDashboard,
      ],
      dependsOnRoles: [Role.relay],
    }),
  },
});

const PARAKEET = defineTopology({
  name: "parakeet",
  description: "Parakeet AppServer (Rust) with Garazyk PDS, Relay, and PLC.",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.pds2]: role.inherit("garazyk-default"),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.appview({
      name: "parakeet",
      source: source.image(
        "registry.gitlab.com/parakeet-social/parakeet/parakeet-appview:main",
      ),
      env: {
        PK_SERVER__PORT: "3200",
        PK_SERVER__BIND_ADDRESS: "0.0.0.0",
        PK_DATABASE_URL:
          "postgres://parakeet:parakeet@local-parakeet-db:5432/parakeet",
        PK_INDEX_URI: "local-parakeet-index:6001",
        PK_REDIS_URI: "redis://local-parakeet-redis:6379",
        PK_PLC_DIRECTORY: "http://local-plc:2582",
        PK_MIGRATE: "true",
        PK_CDN__BASE: "https://cdn.bsky.app",
        PK_CDN__VIDEO_BASE: "https://video.bsky.app",
      },
      ports: [port(3200)],
      health: topologyHealth.http("/xrpc/app.bsky.actor.getProfile"),
      capabilities: appviewSocialCaps,
      dependsOn: [
        serviceRef("local-parakeet-db"),
        serviceRef("local-parakeet-redis"),
        serviceRef("local-parakeet-index"),
        serviceRef("local-parakeet-consumer"),
      ],
      sidecars: {
        "local-parakeet-consumer": {
          source: source.image(
            "registry.gitlab.com/parakeet-social/parakeet/parakeet-consumer:main",
          ),
          env: {
            PKC_DATABASE__URL:
              "postgres://parakeet:parakeet@local-parakeet-db:5432/parakeet",
            PKC_INDEX_URI: "local-parakeet-index:6001",
            PKC_REDIS_URI: "redis://local-parakeet-redis:6379",
            PKC_PLC_DIRECTORY: "http://local-plc:2582",
            PKC_RESUME_PATH: "/data/consumer-cursor.json",
            PKC_INDEXER__RELAY_SOURCE:
              "ws://local-relay:2584/xrpc/com.atproto.sync.subscribeRepos",
            PKC_INDEXER__HISTORY_MODE: "realtime",
            PKC_INDEXER__INDEXER_WORKERS: "4",
            PKC_INDEXER__SKIP_HANDLE_VALIDATION: "true",
            PKC_UA_CONTACT: "garazyk-scenario-test",
          },
          volumes: [volume.named("parakeet_consumer_data", "/data")],
          health: topologyHealth.none(),
        },
        "local-parakeet-index": {
          source: source.image(
            "registry.gitlab.com/parakeet-social/parakeet/parakeet-index:main",
          ),
          env: {
            PKI_SERVER__BIND_ADDRESS: "0.0.0.0",
            PKI_SERVER__PORT: "6001",
            PKI_INDEX_DB_PATH: "/data/index-db",
          },
          volumes: [volume.named("parakeet_index_data", "/data")],
          health: topologyHealth.none(),
        },
        "local-parakeet-db": {
          source: source.image("postgres:16-alpine"),
          env: {
            POSTGRES_USER: "parakeet",
            POSTGRES_PASSWORD: "parakeet",
            POSTGRES_DB: "parakeet",
          },
          volumes: [
            volume.named("parakeet_pg_data", "/var/lib/postgresql/data"),
          ],
          health: topologyHealth.command([
            "CMD-SHELL",
            "pg_isready -U parakeet",
          ]),
        },
        "local-parakeet-redis": {
          source: source.image("redis:7-alpine"),
          health: topologyHealth.command(["CMD", "redis-cli", "ping"]),
        },
      },
    }),
  },
});

const WINTERMUTE = defineTopology({
  name: "wintermute",
  description: "Wintermute (Rust) with Garazyk stack.",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.pds2]: role.inherit("garazyk-default"),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.inherit("garazyk-default"),
    [Role.backfill]: role.backfill({
      name: "wintermute",
      source: source.git({
        repo: "https://github.com/blacksky-algorithms/rsky.git",
        ref: "main",
        overlayDir: "docker/wintermute",
      }),
      env: {
        RELAY_HOSTS: "http://local-relay:2584",
        DATABASE_URL:
          "postgres://wintermute:wintermute@local-wintermute-db:5432/bsky",
        DATABASE_HOST: "local-wintermute-db",
        DATABASE_PORT: "5432",
        DATABASE_USER: "wintermute",
        METRICS_PORT: "9090",
        RUST_LOG: "info",
      },
      ports: [port(9090)],
      volumes: [volume.named("wintermute_data", "/data")],
      health: topologyHealth.command([
        "CMD-SHELL",
        "wget -qO- http://localhost:9090/metrics || exit 1",
      ]),
      capabilities: [
        Cap.backfill.backfill,
        Cap.backfill.fullNetworkIndexing,
        Cap.backfill.labelSubscription,
        Cap.backfill.prometheusMetrics,
        Cap.backfill.repoBackfill,
        Cap.backfill.directIndexing,
      ],
      dependsOn: [serviceRef("local-dataplane")],
      sidecars: {
        "local-wintermute-db": {
          source: source.image("postgres:16-alpine"),
          env: {
            POSTGRES_DB: "bsky",
            POSTGRES_USER: "wintermute",
            POSTGRES_PASSWORD: "wintermute",
          },
          ports: [port({ host: 5433, container: 5432 })],
          volumes: [
            volume.named("wintermute_db_data", "/var/lib/postgresql/data"),
          ],
          health: topologyHealth.command([
            "CMD-SHELL",
            "pg_isready -U wintermute -d bsky",
          ]),
        },
        "local-dataplane": {
          source: source.git({
            repo: "https://github.com/bluesky-social/atproto.git",
            ref: "main",
            overlayDir: "docker/bsky-dataplane",
          }),
          env: {
            BSKY_DB_POSTGRES_URL:
              "postgres://wintermute:wintermute@local-wintermute-db:5432/bsky?options=-csearch_path%3Dbsky",
            BSKY_DB_POSTGRES_SCHEMA: "bsky",
            BSKY_DATAPLANE_PORT: "2585",
            BSKY_DID_PLC_URL: "http://local-plc:2582",
          },
          ports: [port(2585)],
          health: topologyHealth.command([
            "CMD-SHELL",
            "wget -qO- http://localhost:2585/ || exit 1",
          ]),
          dependsOn: [serviceRef("local-wintermute-db")],
        },
      },
    }),
  },
});

const HYDRANT = defineTopology({
  name: "hydrant",
  description: "Hydrant (Rust) AT Protocol indexer.",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.pds2]: role.inherit("garazyk-default"),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.inherit("garazyk-default"),
    [Role.backfill]: role.backfill({
      name: "hydrant",
      source: source.git({
        repo: "https://tangled.org/ptr.pet/hydrant",
        ref: "main",
      }),
      env: {
        HYDRANT_RELAY_HOST:
          "ws://local-relay:2584/xrpc/com.atproto.sync.subscribeRepos",
        HYDRANT_PLC_URL: "http://local-plc:2582",
        HYDRANT_DATABASE_PATH: "/data/hydrant.db",
        HYDRANT_API_PORT: "3000",
        HYDRANT_FULL_NETWORK: "false",
        HYDRANT_FILTER_SIGNALS: "app.bsky.actor.profile",
        RUST_LOG: "info",
      },
      ports: [port(3000)],
      volumes: [volume.named("hydrant_data", "/data")],
      health: topologyHealth.http("/stats"),
      capabilities: [
        Cap.backfill.backfill,
        Cap.backfill.filteredSync,
        Cap.backfill.xrpcQueries,
        Cap.backfill.eventStream,
        Cap.backfill.filterManagement,
        Cap.backfill.ingestionControl,
        Cap.backfill.repoManagement,
      ],
      dependsOnRoles: [Role.relay],
    }),
  },
});

const ZLAY_RELAY = defineTopology({
  name: "zlay-relay",
  description: "Garazyk PDS with zlay (Zig).",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.relay]: role.relay({
      name: "zlay",
      source: source.git({
        repo: "https://tangled.org/zzstoatzz.io/zlay",
        ref: "main",
        dockerfileOverlay: "docker/zlay/Dockerfile",
      }),
      env: {
        RELAY_PORT: "2584",
        RELAY_METRICS_PORT: "3001",
        RELAY_UPSTREAM: "none",
        RELAY_DATA_DIR: "/data/events",
        COLLECTION_INDEX_DIR: "/data/collection-index",
        RELAY_RETENTION_HOURS: "72",
        DATABASE_URL: "postgres://relay:relay@local-relay-db:5432/relay",
        RESOLVER_THREADS: "2",
        FRAME_WORKERS: "4",
        FRAME_QUEUE_CAPACITY: "2048",
        VALIDATOR_CACHE_SIZE: "50000",
      },
      ports: [port(2584)],
      volumes: [volume.named("zlay_relay_data", "/data")],
      health: topologyHealth.command([
        "CMD-SHELL",
        "wget -qO- http://localhost:2584/_healthz || exit 1",
      ]),
      capabilities: [
        Cap.relay.subscribeRepos,
        Cap.relay.requestCrawl,
        Cap.relay.listRepos,
        Cap.relay.listHosts,
        Cap.relay.healthCheck,
      ],
      dependsOn: [serviceRef("local-relay-db")],
      sidecars: {
        "local-relay-db": {
          source: source.image("postgres:16-alpine"),
          env: {
            POSTGRES_USER: "relay",
            POSTGRES_PASSWORD: "relay",
            POSTGRES_DB: "relay",
          },
          volumes: [
            volume.named("zlay_pg_data", "/var/lib/postgresql/data"),
          ],
          health: topologyHealth.command(["CMD-SHELL", "pg_isready -U relay"]),
        },
      },
    }),
    [Role.appview]: role.inherit("syrena"),
  },
});

TopologyRegistry.register(GARAZYK_DEFAULT);
TopologyRegistry.register(REFERENCE_PDS);
TopologyRegistry.register(REFERENCE_PLC);
TopologyRegistry.register(APPVIEWLITE);
TopologyRegistry.register(INDIGO_RELAY);

const INDIGO_TAP = defineTopology({
  name: "indigo-tap",
  description: "Indigo Tap (Go) standalone sync utility.",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.backfill]: role.backfill({
      name: "indigo-tap",
      source: source.git({
        repo: "https://github.com/bluesky-social/indigo.git",
        ref: "main",
        dockerfile: "cmd/tap/Dockerfile",
      }),
      env: {
        TAP_RELAY_HOST: "ws://local-relay:2584",
        TAP_PLC_URL: "http://local-plc:2582",
      },
      health: topologyHealth.none(),
      capabilities: [
        Cap.backfill.subscribeRepos,
        Cap.backfill.filteredSync,
        Cap.backfill.repoVerification,
        Cap.backfill.webhookDelivery,
        Cap.backfill.collectionFiltering,
        Cap.backfill.perRepoOrdering,
        Cap.backfill.identityCaching,
      ],
      dependsOnRoles: [Role.relay],
    }),
  },
});

TopologyRegistry.register(INDIGO_TAP);
TopologyRegistry.register(RSKY_PDS);
TopologyRegistry.register(RSKY_RELAY);

const SYRENA = defineTopology({
  name: "syrena",
  description: "Syrena AppView (Objective-C) with Garazyk PDS, Relay, and PLC.",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.inherit("garazyk-default"),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.appview({
      name: "syrena",
      source: localBuild,
      entrypoint: ["/usr/local/bin/syrena"],
      command: [
        "serve",
        "--relay",
        "ws://local-relay:2584",
        "--port",
        "3200",
        "--data-dir",
        "/var/lib/atprotopds",
        "--no-backfill",
      ],
      env: {
        TZ: "UTC",
        PDS_ALLOW_PRIVATE_SSRF: "1",
        PDS_ALLOW_HTTP: "1",
        PDS_LEXICON_PATH: "/usr/share/atprotopds/lexicons",
        PDS_WRITE_PROXY_OVERRIDE: "http://local-pds:2583",
        APPVIEW_ADMIN_SECRET,
        APPVIEW_DATA_DIR: "/var/lib/atprotopds",
        APPVIEW_PLC_URL: "http://local-plc:2582",
        APPVIEW_PDS_URL: "http://local-pds:2583",
        APPVIEW_HTTP_PORT: "3200",
      },
      ports: [port(3200)],
      volumes: [volume.named("local_appview_data", "/var/lib/atprotopds")],
      health: topologyHealth.http({
        path: "/admin/backfill/status",
        headers: { Authorization: `Bearer ${APPVIEW_ADMIN_SECRET}` },
      }),
      capabilities: appviewBasicCaps,
      dependsOnRoles: [Role.relay],
    }),
  },
});

const TRANQUIL_PDS = defineTopology({
  name: "tranquil-pds",
  description: "Tranquil PDS (Rust) with Garazyk Relay, PLC, and AppView.",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.pds({
      name: "tranquil-pds",
      source: source.image("ghcr.io/likeco/tranquil-pds:latest"),
      command: ["serve", "--port", "2583"],
      env: {
        TRANQUIL_PDS_HOSTNAME: "localhost",
        TRANQUIL_PDS_PLC_URL: "http://local-plc:2582",
        TRANQUIL_PDS_DATA_DIR: "/data",
      },
      ports: [port(2583)],
      volumes: [volume.named("tranquil_pds_data", "/data")],
      health: topologyHealth.http("/xrpc/com.atproto.server.describeServer"),
      capabilities: pdsFullCaps,
      dependsOnRoles: [Role.plc],
    }),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.inherit("garazyk-default"),
  },
});

TopologyRegistry.register(SYRENA);
TopologyRegistry.register(TRANQUIL_PDS);
TopologyRegistry.register(ALLEGEDLY_PLC);

const COCOON_PDS = defineTopology({
  name: "cocoon-pds",
  description: "Cocoon PDS (Go) with Garazyk Relay, PLC, and AppView.",
  roles: {
    [Role.plc]: role.inherit("garazyk-default"),
    [Role.pds]: role.pds({
      name: "cocoon-pds",
      source: source.git({
        repo: "https://github.com/bluesky-social/cocoon.git",
        ref: "main",
        dockerfile: "Dockerfile",
      }),
      command: ["serve", "--port", "2583"],
      env: {
        COCOON_HOSTNAME: "localhost",
        COCOON_PLC_URL: "http://local-plc:2582",
      },
      ports: [port(2583)],
      volumes: [volume.named("cocoon_pds_data", "/data")],
      health: topologyHealth.http("/xrpc/com.atproto.server.describeServer"),
      capabilities: pdsFullCaps,
      dependsOnRoles: [Role.plc],
    }),
    [Role.relay]: role.inherit("garazyk-default"),
    [Role.appview]: role.inherit("garazyk-default"),
  },
});

TopologyRegistry.register(COCOON_PDS);
TopologyRegistry.register(HAPPYVIEW);
TopologyRegistry.register(PARAKEET);
TopologyRegistry.register(WINTERMUTE);
TopologyRegistry.register(HYDRANT);
TopologyRegistry.register(ZLAY_RELAY);
