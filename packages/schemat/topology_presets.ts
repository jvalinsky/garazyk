import type { RawTopologyPresetV1, WebClientTopology } from "./topology_types.ts";

/**
 * Central registry for ATProto network topologies.
 * Allows for embedded presets and runtime registration.
 */
export class TopologyRegistry {
  private static presets: Map<string, RawTopologyPresetV1> = new Map();
  private static webClients: Map<string, WebClientTopology> = new Map();

  /** Register a topology preset programmatically. */
  static register(preset: RawTopologyPresetV1) {
    this.presets.set(preset.name, preset);
  }

  /** Register a web client preset programmatically. */
  static registerWebClient(client: WebClientTopology) {
    this.webClients.set(client.name, client);
  }

  /** Get a preset by name. */
  static getPreset(name: string): RawTopologyPresetV1 | undefined {
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

function readEnv(name: string): string | undefined {
  try {
    return (globalThis as any).Deno?.env.get(name) || undefined;
  } catch {
    return undefined;
  }
}

const publicWebUrl = readEnv("WEB_CLIENT_URL") || "http://localhost:2591";
const internalWebUrl = readEnv("WEB_CLIENT_INTERNAL_URL") || "http://web-client:2590";

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

const GARAZYK_DEFAULT: RawTopologyPresetV1 = {
  "name": "garazyk-default",
  "description": "Full Garazyk stack: PDS (kaszlak), Relay (zuk), PLC (campagnola), AppView (syrena), Chat (syrena-chat), Video (jelcz). Built from local source.",
  "roles": {
    "plc": {
      "name": "campagnola",
      "buildContext": "docker/local-network",
      "dockerfile": "Dockerfile.local",
      "entrypoint": ["/usr/local/bin/campagnola"],
      "command": [
        "serve", "--host", "0.0.0.0", "--port", "2582", "--database", "/var/lib/atprotopds/plc.db"
      ],
      "env": {
        "TZ": "UTC",
        "PLC_HOURLY_LIMIT": "500",
        "PLC_DAILY_LIMIT": "1000",
        "PLC_WEEKLY_LIMIT": "5000"
      },
      "ports": ["2582:2582"],
      "volumes": ["local_plc_data:/var/lib/atprotopds"],
      "healthCheck": { "path": "/_health" },
      "capabilities": [
        "createAccount", "didResolution", "operationLog", "handleRotation", "quotaEnforcement"
      ]
    },
    "pds": {
      "name": "kaszlak",
      "buildContext": "docker/local-network",
      "dockerfile": "Dockerfile.local",
      "command": ["serve", "--config", "/var/lib/atprotopds/config.json", "--foreground"],
      "env": {
        "TZ": "UTC",
        "PDS_ALLOW_PRIVATE_SSRF": "1",
        "PDS_ALLOW_HTTP": "1",
        "PDS_LEXICON_PATH": "/usr/share/atprotopds/lexicons",
        "HOME": "/var/lib/atprotopds",
        "PDS_RATELIMIT_ENABLED": "false",
        "PDS_MASTER_SECRET": "32107992c973da8445b485263cb2bd3157859cb94294a2355e3c4a7b0f825afe",
        "PDS_ADMIN_PASSWORD": "admin-localdev"
      },
      "ports": ["2583:2583"],
      "volumes": [
        "local_pds_data:/var/lib/atprotopds",
        "./pds-config.json:/var/lib/atprotopds/config.json:ro",
        "local_pds_keys:/var/lib/atprotopds/keys"
      ],
      "healthCheck": { "path": "/xrpc/com.atproto.server.describeServer" },
      "capabilities": [
        "describeServer", "createAccount", "createSession", "getSession", "createRecord",
        "getRecord", "deleteRecord", "listRecords", "uploadBlob", "getBlob", "listBlobs",
        "resolveHandle", "updateHandle", "subscribeRepos", "getHead", "getRepo",
        "requestCrawl", "admin", "sync"
      ],
      "dependsOn": ["local-plc"]
    },
    "pds2": {
      "name": "kaszlak-pds2",
      "buildContext": "docker/local-network",
      "dockerfile": "Dockerfile.local",
      "command": ["serve", "--config", "/var/lib/atprotopds/config.json", "--foreground"],
      "env": {
        "TZ": "UTC",
        "PDS_ALLOW_PRIVATE_SSRF": "1",
        "PDS_ALLOW_HTTP": "1",
        "PDS_LEXICON_PATH": "/usr/share/atprotopds/lexicons",
        "HOME": "/var/lib/atprotopds",
        "PDS_RATELIMIT_ENABLED": "false",
        "PDS_MASTER_SECRET": "32107992c973da8445b485263cb2bd3157859cb94294a2355e3c4a7b0f825afe",
        "PDS_ADMIN_PASSWORD": "admin-localdev"
      },
      "ports": ["2587:2587"],
      "volumes": [
        "local_pds2_data:/var/lib/atprotopds",
        "./pds2-config.json:/var/lib/atprotopds/config.json:ro",
        "local_pds2_keys:/var/lib/atprotopds/keys"
      ],
      "healthCheck": { "path": "/xrpc/com.atproto.server.describeServer" },
      "capabilities": [
        "describeServer", "createAccount", "createSession", "getSession", "createRecord",
        "getRecord", "deleteRecord", "listRecords", "uploadBlob", "getBlob", "listBlobs",
        "resolveHandle", "updateHandle", "subscribeRepos", "getHead", "getRepo",
        "requestCrawl", "admin", "sync"
      ],
      "dependsOn": ["local-plc"]
    },
    "relay": {
      "name": "zuk",
      "buildContext": "docker/local-network",
      "dockerfile": "Dockerfile.local",
      "entrypoint": ["/usr/local/bin/zuk"],
      "command": [
        "serve", "--upstream", "ws://local-pds:2583/xrpc/com.atproto.sync.subscribeRepos",
        "--port", "2584"
      ],
      "ports": ["2584:2584"],
      "volumes": ["local_relay_data:/var/lib/atprotopds"],
      "healthCheck": { "path": "/api/relay/health" },
      "capabilities": ["subscribeRepos", "requestCrawl", "healthCheck"],
      "dependsOn": ["local-pds"]
    },
    "appview": {
      "name": "syrena",
      "buildContext": "docker/local-network",
      "dockerfile": "Dockerfile.local",
      "entrypoint": ["/usr/local/bin/syrena"],
      "command": [
        "serve", "--relay", "ws://local-relay:2584", "--port", "3200", "--no-backfill"
      ],
      "env": {
        "APPVIEW_ADMIN_SECRET": "localdevadmin",
        "APPVIEW_PLC_URL": "http://local-plc:2582",
        "APPVIEW_PDS_URL": "http://local-pds:2583"
      },
      "ports": ["3200:3200"],
      "volumes": ["local_appview_data:/var/lib/atprotopds"],
      "healthCheck": {
        "path": "/admin/backfill/status",
        "headers": { "Authorization": "Bearer localdevadmin" }
      },
      "capabilities": ["getTimeline", "getProfile", "getFeed", "search", "backfill", "admin"],
      "dependsOn": ["local-relay"]
    },
    "chat": {
      "name": "syrena-chat",
      "buildContext": "docker/local-network",
      "dockerfile": "Dockerfile.local",
      "entrypoint": ["/usr/local/bin/syrena-chat"],
      "command": ["serve", "--port", "2585"],
      "ports": ["2585:2585"],
      "volumes": ["local_chat_data:/var/lib/atprotopds"],
      "healthCheck": { "path": "/_health" },
      "capabilities": ["dm", "chat"],
      "dependsOn": ["local-pds"]
    },
    "video": {
      "name": "jelcz",
      "buildContext": "docker/local-network",
      "dockerfile": "Dockerfile.local",
      "entrypoint": ["/usr/local/bin/jelcz"],
      "command": ["serve", "--port", "2586"],
      "ports": ["2586:2586"],
      "volumes": ["local_video_data:/var/lib/atprotopds"],
      "healthCheck": { "path": "/_health" },
      "capabilities": ["uploadVideo", "getVideoStatus"],
      "dependsOn": ["local-pds"]
    }
  },
  "networkAliases": {
    "local-appview": ["bsky.app"]
  }
};

const REFERENCE_PDS: RawTopologyPresetV1 = {
  "name": "reference-pds",
  "description": "Bluesky reference PDS (TypeScript) with Garazyk Relay, PLC, and AppView.",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": {
      "name": "reference-pds",
      "source": {
        "repo": "https://github.com/bluesky-social/pds.git",
        "ref": "v0.4.219"
      },
      "command": ["--port", "2583"],
      "env": {
        "PDS_HOSTNAME": "localhost",
        "PDS_JETSTREAM_URL": "ws://local-relay:2584",
        "PDS_BLOB_CACHE_LOC": "/tmp/pds-blob-cache",
        "PDS_DIDPLC_URL": "http://local-plc:2582"
      },
      "ports": ["2583:2583"],
      "volumes": ["ref_pds_data:/data"],
      "healthCheck": { "path": "/xrpc/com.atproto.server.describeServer" },
      "capabilities": [
        "describeServer", "createAccount", "createSession", "getSession", "createRecord",
        "getRecord", "deleteRecord", "listRecords", "uploadBlob", "getBlob", "listBlobs",
        "resolveHandle", "updateHandle", "subscribeRepos", "getHead", "getRepo",
        "requestCrawl", "admin", "sync"
      ],
      "dependsOn": ["local-plc"]
    },
    "relay": { "inherit": "garazyk-default" },
    "appview": { "inherit": "garazyk-default" }
  }
};

const REFERENCE_PLC: RawTopologyPresetV1 = {
  "name": "reference-plc",
  "description": "Bluesky reference PLC directory server (TypeScript, did-method-plc) with Garazyk PDS, Relay, and AppView.",
  "roles": {
    "plc": {
      "name": "reference-plc",
      "source": {
        "repo": "https://github.com/did-method-plc/did-method-plc.git",
        "ref": "main",
        "dockerfile": "packages/server/Dockerfile"
      },
      "command": ["node", "--enable-source-maps", "index.js"],
      "env": {
        "PORT": "2582",
        "NODE_ENV": "production",
        "DB_CREDS_JSON": "{\"host\":\"local-plc-db\",\"port\":5432,\"username\":\"plc\",\"password\":\"plc\",\"database\":\"plc\"}",
        "ENABLE_MIGRATIONS": "true",
        "DB_MIGRATE_CREDS_JSON": "{\"host\":\"local-plc-db\",\"port\":5432,\"username\":\"plc\",\"password\":\"plc\",\"database\":\"plc\"}",
        "DEBUG_MODE": "1",
        "LOG_ENABLED": "true",
        "LOG_LEVEL": "debug"
      },
      "ports": ["2582:2582"],
      "healthCheck": {
        "path": null as any,
        "customTest": ["CMD-SHELL", "wget -qO- http://localhost:2582/_health || exit 1"]
      },
      "capabilities": ["createAccount", "didResolution", "operationLog", "handleRotation", "quotaEnforcement"],
      "dependsOn": ["local-plc-db"],
      "sidecars": {
        "local-plc-db": {
          "image": "postgres:16-alpine",
          "env": {
            "POSTGRES_USER": "plc",
            "POSTGRES_PASSWORD": "plc",
            "POSTGRES_DB": "plc"
          },
          "volumes": ["ref_plc_pg_data:/var/lib/postgresql/data"],
          "healthCheck": {
            "path": null as any,
            "customTest": ["CMD-SHELL", "pg_isready -U plc"]
          }
        }
      }
    },
    "pds": { "inherit": "garazyk-default" },
    "pds2": { "inherit": "garazyk-default" },
    "relay": { "inherit": "garazyk-default" },
    "appview": { "inherit": "garazyk-default" },
    "chat": { "inherit": "garazyk-default" },
    "video": { "inherit": "garazyk-default" }
  }
};

const APPVIEWLITE: RawTopologyPresetV1 = {
  "name": "appviewlite",
  "description": "AppViewLite (C#/.NET 9, alnkesq) with Garazyk PDS, Relay, and PLC.",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": { "inherit": "garazyk-default" },
    "pds2": { "inherit": "garazyk-default" },
    "relay": { "inherit": "garazyk-default" },
    "appview": {
      "name": "appviewlite",
      "source": {
        "repo": "https://github.com/alnkesq/AppViewLite.git",
        "ref": "main",
        "dockerDir": "src"
      },
      "command": ["dotnet", "AppViewLite.Web.dll"],
      "env": {
        "APPVIEWLITE_DIRECTORY": "/data",
        "APPVIEWLITE_BIND_URLS": "http://+:3200",
        "APPVIEWLITE_ALLOW_NEW_DATABASE": "1",
        "APPVIEWLITE_PLC_DIRECTORY": "http://local-plc:2582",
        "APPVIEWLITE_FIREHOSES": "ws://local-relay:2584/xrpc/com.atproto.sync.subscribeRepos",
        "APPVIEWLITE_LISTEN_TO_FIREHOSE": "1",
        "APPVIEWLITE_LISTEN_TO_PLC_DIRECTORY": "1",
        "APPVIEWLITE_ADMINISTRATIVE_DIDS": "*",
        "APPVIEWLITE_QUICK_REVERSE_BACKFILL_INSTANCE": "-"
      },
      "ports": ["3200:3200"],
      "volumes": ["appviewlite_data:/data"],
      "healthCheck": { "path": "/" },
      "capabilities": ["getTimeline", "getProfile", "getFeed", "search", "posts", "likes", "reposts", "follows", "blocks", "labels", "lists", "mutes", "notifications", "feeds", "video", "mediaGrid", "dataExport", "multiProtocol"],
      "dependsOn": ["local-relay"]
    }
  }
};

const INDIGO_RELAY: RawTopologyPresetV1 = {
  "name": "indigo-relay",
  "description": "Garazyk PDS with indigo Relay (Go).",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": { "inherit": "garazyk-default" },
    "relay": {
      "name": "indigo-relay",
      "source": {
        "repo": "https://github.com/bluesky-social/indigo.git",
        "ref": "main",
        "dockerfile": "cmd/relay/Dockerfile"
      },
      "command": [
        "run",
        "--listen-addr", "0.0.0.0:2584",
        "--upstream", "ws://local-pds:2583/xrpc/com.atproto.sync.subscribeRepos"
      ],
      "env": { "RELAY_DIDPLC_URL": "http://local-plc:2582" },
      "ports": ["2584:2584"],
      "volumes": ["indigo_relay_data:/data"],
      "healthCheck": { "path": "/xrpc/com.atproto.sync.subscribeRepos" },
      "capabilities": ["subscribeRepos", "requestCrawl", "healthCheck"],
      "dependsOn": ["local-pds"]
    },
    "appview": { "inherit": "garazyk-default" }
  }
};

const RSKY_PDS: RawTopologyPresetV1 = {
  "name": "rsky-pds",
  "description": "Garazyk stack with rsky-pds (Rust, blacksky-algorithms).",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": {
      "name": "rsky-pds",
      "source": {
        "repo": "https://github.com/blacksky-algorithms/rsky.git",
        "ref": "main",
        "overlayDir": "docker/rsky-pds"
      },
      "env": {
        "PDS_HOSTNAME": "localhost",
        "PDS_PORT": "2583",
        "PDS_DEV_MODE": "true",
        "PDS_INVITE_REQUIRED": "false",
        "PDS_DID_PLC_URL": "http://local-plc:2582",
        "PDS_SERVICE_HANDLE_DOMAINS": ".test",
        "PDS_CRAWLERS": "http://local-relay:2584",
        "DATABASE_URL": "postgres://pds:pds@local-pds-db:5432/pds",
        "AWS_ENDPOINT": "http://local-pds-s3:3900",
        "AWS_ACCESS_KEY_ID": "GKlocaltopologyaccesskey",
        "AWS_SECRET_ACCESS_KEY": "localtopologysecretkey1234567890abcdef",
        "AWS_ENDPOINT_BUCKET": "local-pds-s3",
        "AWS_REGION": "garage",
        "ROCKET_ADDRESS": "0.0.0.0",
        "ROCKET_PORT": "2583"
      },
      "ports": ["2583:2583"],
      "volumes": ["rsky_pds_data:/usr/src/rsky"],
      "healthCheck": {
        "path": null as any,
        "customTest": ["CMD-SHELL", "wget -qO- http://localhost:2583/health || exit 1"]
      },
      "capabilities": [
        "describeServer", "createAccount", "createSession", "getSession", "createRecord",
        "getRecord", "deleteRecord", "listRecords", "uploadBlob", "getBlob", "listBlobs",
        "resolveHandle", "updateHandle", "subscribeRepos", "getHead", "getRepo",
        "requestCrawl", "admin", "repo", "identity", "blob", "sync"
      ],
      "dependsOn": ["local-pds-db", "local-pds-s3"],
      "sidecars": {
        "local-pds-db": {
          "image": "postgres:16-alpine",
          "env": {
            "POSTGRES_USER": "pds",
            "POSTGRES_PASSWORD": "pds",
            "POSTGRES_DB": "pds"
          },
          "volumes": ["rsky_pds_pg_data:/var/lib/postgresql/data"],
          "healthCheck": {
            "path": null as any,
            "customTest": ["CMD-SHELL", "pg_isready -U pds"]
          }
        },
        "local-pds-s3": {
          "image": "dxflrs/garage:v2.3.0",
          "command": ["/garage", "server", "--single-node", "--default-bucket"],
          "env": {
            "GARAGE_DEFAULT_ACCESS_KEY": "GKlocaltopologyaccesskey",
            "GARAGE_DEFAULT_SECRET_KEY": "localtopologysecretkey1234567890abcdef",
            "GARAGE_DEFAULT_BUCKET": "default-bucket"
          },
          "volumes": ["rsky_pds_garage_meta:/var/lib/garage/meta", "rsky_pds_garage_data:/var/lib/garage/data"],
          "healthCheck": {
            "path": null as any,
            "customTest": ["CMD-SHELL", "wget -qO- http://localhost:3900/health || exit 1"]
          }
        }
      }
    },
    "relay": { "inherit": "garazyk-default" },
    "appview": { "inherit": "garazyk-default" }
  }
};

const RSKY_RELAY: RawTopologyPresetV1 = {
  "name": "rsky-relay",
  "description": "Garazyk PDS with rsky-relay (Rust).",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": { "inherit": "garazyk-default" },
    "relay": {
      "name": "rsky-relay",
      "source": {
        "repo": "https://github.com/blacksky-algorithms/rsky.git",
        "ref": "fd88a2740da299377ee08cf4e76f80e4ad45fc4a",
        "overlayDir": "docker/rsky-relay"
      },
      "command": ["rsky-relay", "--no-plc-export"],
      "env": {
        "RELAY_PORT": "2584",
        "RELAY_CRAWL_SCHEME": "ws",
        "RELAY_PLC_URL": "http://local-plc:2582",
        "RELAY_DISCOVERY_UPSTREAMS": "",
        "RELAY_DISCOVERY_ALLOW_HTTP": "true",
        "RELAY_DB_PATH": "/data/db",
        "RUST_LOG": "rsky_relay=debug,info"
      },
      "ports": ["2584:2584"],
      "volumes": ["rsky_relay_data:/data"],
      "healthCheck": {
        "path": null as any,
        "customTest": ["CMD-SHELL", "wget -qO- http://localhost:2584/xrpc/com.atproto.sync.subscribeRepos || exit 1"]
      },
      "capabilities": ["subscribeRepos", "requestCrawl", "healthCheck"],
      "dependsOn": ["local-pds"]
    },
    "appview": { "inherit": "garazyk-default" }
  }
};

const ALLEGEDLY_PLC: RawTopologyPresetV1 = {
  "name": "allegedly-plc",
  "description": "Allegedly PLC mirror/wrapper (Rust) wrapping the reference PLC server.",
  "roles": {
    "plc": {
      "name": "allegedly-plc",
      "source": {
        "repo": "https://tangled.org/microcosm.blue/Allegedly",
        "ref": "main",
        "dockerfileOverlay": "docker/allegedly/Dockerfile"
      },
      "command": ["allegedly", "mirror", "--upstream", "http://local-ref-plc:3000", "--wrap", "http://local-ref-plc:3000", "--bind", "0.0.0.0:2582"],
      "env": {
        "ALLEGEDLY_WRAP_PG": "postgres://plc:plc@local-plc-db:5432/plc",
        "RUST_LOG": "allegedly=debug,info"
      },
      "ports": ["2582:2582"],
      "volumes": ["allegedly_plc_data:/data"],
      "healthCheck": {
        "path": null as any,
        "customTest": ["CMD-SHELL", "wget -qO- http://localhost:2582/ || exit 1"]
      },
      "capabilities": ["createAccount", "didResolution", "operationLog", "handleRotation", "quotaEnforcement"],
      "dependsOn": ["local-ref-plc", "local-plc-db"],
      "sidecars": {
        "local-ref-plc": {
          "source": {
            "repo": "https://github.com/did-method-plc/did-method-plc.git",
            "ref": "244abb5f6a75916984d5853df34d7bcefc4d2faf",
            "dockerfile": "packages/server/Dockerfile"
          },
          "command": ["node", "--enable-source-maps", "index.js"],
          "env": {
            "PORT": "3000",
            "NODE_ENV": "production",
            "DB_CREDS_JSON": "{\"host\":\"local-plc-db\",\"port\":5432,\"username\":\"plc\",\"password\":\"plc\",\"database\":\"plc\"}",
            "ENABLE_MIGRATIONS": "true",
            "DB_MIGRATE_CREDS_JSON": "{\"host\":\"local-plc-db\",\"port\":5432,\"username\":\"plc\",\"password\":\"plc\",\"database\":\"plc\"}",
            "DEBUG_MODE": "1",
            "LOG_ENABLED": "true",
            "LOG_LEVEL": "debug"
          },
          "healthCheck": {
            "path": null as any,
            "customTest": ["CMD-SHELL", "wget -qO- http://localhost:3000/_health || exit 1"]
          },
          "dependsOn": ["local-plc-db"]
        },
        "local-plc-db": {
          "image": "postgres:16-alpine",
          "env": {
            "POSTGRES_USER": "plc",
            "POSTGRES_PASSWORD": "plc",
            "POSTGRES_DB": "plc"
          },
          "volumes": ["allegedly_plc_pg_data:/var/lib/postgresql/data"],
          "healthCheck": {
            "path": null as any,
            "customTest": ["CMD-SHELL", "pg_isready -U plc"]
          }
        }
      }
    },
    "pds": { "inherit": "garazyk-default" },
    "pds2": { "inherit": "garazyk-default" },
    "relay": { "inherit": "garazyk-default" },
    "appview": { "inherit": "garazyk-default" }
  }
};

const HAPPYVIEW: RawTopologyPresetV1 = {
  "name": "happyview",
  "description": "HappyView (TypeScript/Rust, trezy) with Garazyk PDS, Relay, and PLC.",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": { "inherit": "garazyk-default" },
    "pds2": { "inherit": "garazyk-default" },
    "relay": { "inherit": "garazyk-default" },
    "appview": {
      "name": "happyview",
      "source": {
        "repo": "https://github.com/gamesgamesgamesgamesgames/happyview.git",
        "ref": "v2.7.0",
        "buildArgs": { "HAPPYVIEW_VERSION": "2.7.0" }
      },
      "env": {
        "DATABASE_URL": "sqlite:///data/happyview.db?mode=rwc",
        "PUBLIC_URL": "http://localhost:3200",
        "SESSION_SECRET": "localdev-session-secret",
        "RELAY_URL": "ws://local-relay:2584/xrpc/com.atproto.sync.subscribeRepos",
        "PORT": "3200"
      },
      "ports": ["3200:3000"],
      "volumes": ["happyview_data:/data"],
      "healthCheck": { "path": "/" },
      "capabilities": ["getTimeline", "getProfile", "getFeed", "search", "xrpcEndpoints", "oauth", "realTimeSync", "backfill", "lexiconDriven", "luaScripting", "indexHooks", "networkLexicons", "hotReloading", "adminDashboard"],
      "dependsOn": ["local-relay"]
    }
  }
};

const PARAKEET: RawTopologyPresetV1 = {
  "name": "parakeet",
  "description": "Parakeet AppServer (Rust) with Garazyk PDS, Relay, and PLC.",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": { "inherit": "garazyk-default" },
    "pds2": { "inherit": "garazyk-default" },
    "relay": { "inherit": "garazyk-default" },
    "appview": {
      "name": "parakeet",
      "image": "registry.gitlab.com/parakeet-social/parakeet/parakeet-appview:main",
      "env": {
        "PK_SERVER__PORT": "3200",
        "PK_SERVER__BIND_ADDRESS": "0.0.0.0",
        "PK_DATABASE_URL": "postgres://parakeet:parakeet@local-parakeet-db:5432/parakeet",
        "PK_INDEX_URI": "local-parakeet-index:6001",
        "PK_REDIS_URI": "redis://local-parakeet-redis:6379",
        "PK_PLC_DIRECTORY": "http://local-plc:2582",
        "PK_MIGRATE": "true",
        "PK_CDN__BASE": "https://cdn.bsky.app",
        "PK_CDN__VIDEO_BASE": "https://video.bsky.app"
      },
      "ports": ["3200:3200"],
      "healthCheck": { "path": "/xrpc/app.bsky.actor.getProfile" },
      "capabilities": ["getTimeline", "getProfile", "getFeed", "posts", "likes", "reposts", "follows", "blocks", "labels", "lists", "mutes", "notifications", "feeds"],
      "dependsOn": ["local-parakeet-db", "local-parakeet-redis", "local-parakeet-index", "local-parakeet-consumer"],
      "sidecars": {
        "local-parakeet-consumer": {
          "image": "registry.gitlab.com/parakeet-social/parakeet/parakeet-consumer:main",
          "env": {
            "PKC_DATABASE__URL": "postgres://parakeet:parakeet@local-parakeet-db:5432/parakeet",
            "PKC_INDEX_URI": "local-parakeet-index:6001",
            "PKC_REDIS_URI": "redis://local-parakeet-redis:6379",
            "PKC_PLC_DIRECTORY": "http://local-plc:2582",
            "PKC_RESUME_PATH": "/data/consumer-cursor.json",
            "PKC_INDEXER__RELAY_SOURCE": "ws://local-relay:2584/xrpc/com.atproto.sync.subscribeRepos",
            "PKC_INDEXER__HISTORY_MODE": "realtime",
            "PKC_INDEXER__INDEXER_WORKERS": "4",
            "PKC_INDEXER__SKIP_HANDLE_VALIDATION": "true",
            "PKC_UA_CONTACT": "garazyk-scenario-test"
          },
          "volumes": ["parakeet_consumer_data:/data"],
          "healthCheck": { "path": null as any }
        },
        "local-parakeet-index": {
          "image": "registry.gitlab.com/parakeet-social/parakeet/parakeet-index:main",
          "env": { "PKI_SERVER__BIND_ADDRESS": "0.0.0.0", "PKI_SERVER__PORT": "6001", "PKI_INDEX_DB_PATH": "/data/index-db" },
          "volumes": ["parakeet_index_data:/data"],
          "healthCheck": { "path": null as any }
        },
        "local-parakeet-db": {
          "image": "postgres:16-alpine",
          "env": { "POSTGRES_USER": "parakeet", "POSTGRES_PASSWORD": "parakeet", "POSTGRES_DB": "parakeet" },
          "volumes": ["parakeet_pg_data:/var/lib/postgresql/data"],
          "healthCheck": { "path": null as any, "customTest": ["CMD-SHELL", "pg_isready -U parakeet"] }
        },
        "local-parakeet-redis": {
          "image": "redis:7-alpine",
          "healthCheck": { "path": null as any, "customTest": ["CMD", "redis-cli", "ping"] }
        }
      }
    }
  }
};

const WINTERMUTE: RawTopologyPresetV1 = {
  "name": "wintermute",
  "description": "Wintermute (Rust) with Garazyk stack.",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": { "inherit": "garazyk-default" },
    "pds2": { "inherit": "garazyk-default" },
    "relay": { "inherit": "garazyk-default" },
    "appview": { "inherit": "garazyk-default" },
    "backfill": {
      "name": "wintermute",
      "source": {
        "repo": "https://github.com/blacksky-algorithms/rsky.git",
        "ref": "main",
        "overlayDir": "docker/wintermute"
      },
      "env": {
        "RELAY_HOSTS": "http://local-relay:2584",
        "DATABASE_URL": "postgres://wintermute:wintermute@local-wintermute-db:5432/bsky",
        "DATABASE_HOST": "local-wintermute-db",
        "DATABASE_PORT": "5432",
        "DATABASE_USER": "wintermute",
        "METRICS_PORT": "9090",
        "RUST_LOG": "info"
      },
      "ports": ["9090:9090"],
      "volumes": ["wintermute_data:/data"],
      "healthCheck": {
        "path": null as any,
        "customTest": ["CMD-SHELL", "wget -qO- http://localhost:9090/metrics || exit 1"]
      },
      "capabilities": ["backfill", "fullNetworkIndexing", "labelSubscription", "prometheusMetrics", "repoBackfill", "directIndexing"],
      "dependsOn": ["local-dataplane"],
      "sidecars": {
        "local-wintermute-db": {
          "image": "postgres:16-alpine",
          "env": { "POSTGRES_DB": "bsky", "POSTGRES_USER": "wintermute", "POSTGRES_PASSWORD": "wintermute" },
          "ports": ["5433:5432"],
          "volumes": ["wintermute_db_data:/var/lib/postgresql/data"],
          "healthCheck": { "path": null as any, "customTest": ["CMD-SHELL", "pg_isready -U wintermute -d bsky"] }
        },
        "local-dataplane": {
          "source": { "repo": "https://github.com/bluesky-social/atproto.git", "ref": "main", "overlayDir": "docker/bsky-dataplane" },
          "env": { "BSKY_DB_POSTGRES_URL": "postgres://wintermute:wintermute@local-wintermute-db:5432/bsky?options=-csearch_path%3Dbsky", "BSKY_DB_POSTGRES_SCHEMA": "bsky", "BSKY_DATAPLANE_PORT": "2585", "BSKY_DID_PLC_URL": "http://local-plc:2582" },
          "ports": ["2585:2585"],
          "healthCheck": { "path": null as any, "customTest": ["CMD-SHELL", "wget -qO- http://localhost:2585/ || exit 1"] },
          "dependsOn": ["local-wintermute-db"]
        }
      }
    }
  }
};

const HYDRANT: RawTopologyPresetV1 = {
  "name": "hydrant",
  "description": "Hydrant (Rust) AT Protocol indexer.",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": { "inherit": "garazyk-default" },
    "pds2": { "inherit": "garazyk-default" },
    "relay": { "inherit": "garazyk-default" },
    "appview": { "inherit": "garazyk-default" },
    "backfill": {
      "name": "hydrant",
      "source": { "repo": "https://tangled.org/ptr.pet/hydrant", "ref": "main" },
      "env": { "HYDRANT_RELAY_HOST": "ws://local-relay:2584/xrpc/com.atproto.sync.subscribeRepos", "HYDRANT_PLC_URL": "http://local-plc:2582", "HYDRANT_DATABASE_PATH": "/data/hydrant.db", "HYDRANT_API_PORT": "3000", "HYDRANT_FULL_NETWORK": "false", "HYDRANT_FILTER_SIGNALS": "app.bsky.actor.profile", "RUST_LOG": "info" },
      "ports": ["3000:3000"],
      "volumes": ["hydrant_data:/data"],
      "healthCheck": { "path": "/stats" },
      "capabilities": ["backfill", "filteredSync", "xrpcQueries", "eventStream", "filterManagement", "ingestionControl", "repoManagement"],
      "dependsOn": ["local-relay"]
    }
  }
};

const ZLAY_RELAY: RawTopologyPresetV1 = {
  "name": "zlay-relay",
  "description": "Garazyk PDS with zlay (Zig).",
  "roles": {
    "plc": { "inherit": "garazyk-default" },
    "pds": { "inherit": "garazyk-default" },
    "relay": {
      "name": "zlay",
      "source": { "repo": "https://tangled.org/zzstoatzz.io/zlay", "ref": "main", "dockerfileOverlay": "docker/zlay/Dockerfile" },
      "env": { "RELAY_PORT": "2584", "RELAY_METRICS_PORT": "3001", "RELAY_UPSTREAM": "none", "RELAY_DATA_DIR": "/data/events", "COLLECTION_INDEX_DIR": "/data/collection-index", "RELAY_RETENTION_HOURS": "72", "DATABASE_URL": "postgres://relay:relay@local-relay-db:5432/relay", "RESOLVER_THREADS": "2", "FRAME_WORKERS": "4", "FRAME_QUEUE_CAPACITY": "2048", "VALIDATOR_CACHE_SIZE": "50000" },
      "ports": ["2584:2584"],
      "volumes": ["zlay_relay_data:/data"],
      "healthCheck": { "path": null as any, "customTest": ["CMD-SHELL", "wget -qO- http://localhost:2584/_healthz || exit 1"] },
      "capabilities": ["subscribeRepos", "requestCrawl", "listRepos", "listHosts", "healthCheck"],
      "dependsOn": ["local-relay-db"],
      "sidecars": {
        "local-relay-db": {
          "image": "postgres:16-alpine",
          "env": { "POSTGRES_USER": "relay", "POSTGRES_PASSWORD": "relay", "POSTGRES_DB": "relay" },
          "volumes": ["zlay_pg_data:/var/lib/postgresql/data"],
          "healthCheck": { "path": null as any, "customTest": ["CMD-SHELL", "pg_isready -U relay"] }
        }
      }
    },
    "appview": { "inherit": "syrena" as any }
  }
};

TopologyRegistry.register(GARAZYK_DEFAULT);
TopologyRegistry.register(REFERENCE_PDS);
TopologyRegistry.register(REFERENCE_PLC);
TopologyRegistry.register(APPVIEWLITE);
TopologyRegistry.register(INDIGO_RELAY);

const INDIGO_TAP: RawTopologyPresetV1 = {
  "name": "indigo-tap",
  "description": "Indigo Tap (Go) standalone sync utility.",
  "roles": {
    "plc": { "inherit": "garazyk-default" as any },
    "pds": { "inherit": "garazyk-default" as any },
    "relay": { "inherit": "garazyk-default" as any },
    "backfill": {
      "name": "indigo-tap",
      "source": {
        "repo": "https://github.com/bluesky-social/indigo.git",
        "ref": "main",
        "dockerfile": "cmd/tap/Dockerfile"
      },
      "env": {
        "TAP_RELAY_HOST": "ws://local-relay:2584",
        "TAP_PLC_URL": "http://local-plc:2582"
      },
      "healthCheck": { "path": null as any },
      "capabilities": ["subscribeRepos", "filteredSync", "repoVerification", "webhookDelivery", "collectionFiltering", "perRepoOrdering", "identityCaching"],
      "dependsOn": ["local-relay"]
    }
  }
};

TopologyRegistry.register(INDIGO_TAP);
TopologyRegistry.register(RSKY_PDS);
TopologyRegistry.register(RSKY_RELAY);

const SYRENA: RawTopologyPresetV1 = {
  "name": "syrena",
  "description": "Syrena AppView (Objective-C) with Garazyk PDS, Relay, and PLC.",
  "roles": {
    "plc": { "inherit": "garazyk-default" as any },
    "pds": { "inherit": "garazyk-default" as any },
    "relay": { "inherit": "garazyk-default" as any },
    "appview": {
      "name": "syrena",
      "buildContext": "docker/local-network",
      "dockerfile": "Dockerfile.local",
      "entrypoint": ["/usr/local/bin/syrena"],
      "command": [
        "serve", "--relay", "ws://local-relay:2584", "--port", "3200", "--data-dir", "/var/lib/atprotopds", "--no-backfill"
      ],
      "env": {
        "TZ": "UTC",
        "PDS_ALLOW_PRIVATE_SSRF": "1",
        "PDS_ALLOW_HTTP": "1",
        "PDS_LEXICON_PATH": "/usr/share/atprotopds/lexicons",
        "PDS_WRITE_PROXY_OVERRIDE": "http://local-pds:2583",
        "APPVIEW_ADMIN_SECRET": "localdevadmin",
        "APPVIEW_DATA_DIR": "/var/lib/atprotopds",
        "APPVIEW_PLC_URL": "http://local-plc:2582",
        "APPVIEW_PDS_URL": "http://local-pds:2583",
        "APPVIEW_HTTP_PORT": "3200"
      },
      "ports": ["3200:3200"],
      "volumes": ["local_appview_data:/var/lib/atprotopds"],
      "healthCheck": {
        "path": "/admin/backfill/status",
        "headers": { "Authorization": "Bearer localdevadmin" }
      },
      "capabilities": ["getTimeline", "getProfile", "getFeed", "search", "backfill", "admin"],
      "dependsOn": ["local-relay"]
    }
  }
};

const TRANQUIL_PDS: RawTopologyPresetV1 = {
  "name": "tranquil-pds",
  "description": "Tranquil PDS (Rust) with Garazyk Relay, PLC, and AppView.",
  "roles": {
    "plc": { "inherit": "garazyk-default" as any },
    "pds": {
      "name": "tranquil-pds",
      "image": "ghcr.io/likeco/tranquil-pds:latest",
      "command": ["serve", "--port", "2583"],
      "env": {
        "TRANQUIL_PDS_HOSTNAME": "localhost",
        "TRANQUIL_PDS_PLC_URL": "http://local-plc:2582",
        "TRANQUIL_PDS_DATA_DIR": "/data"
      },
      "ports": ["2583:2583"],
      "volumes": ["tranquil_pds_data:/data"],
      "healthCheck": { "path": "/xrpc/com.atproto.server.describeServer" },
      "capabilities": [
        "describeServer", "createAccount", "createSession", "getSession", "createRecord",
        "getRecord", "deleteRecord", "listRecords", "uploadBlob", "getBlob", "listBlobs",
        "resolveHandle", "updateHandle", "subscribeRepos", "getHead", "getRepo",
        "requestCrawl", "admin", "repo", "identity", "blob", "sync"
      ],
      "dependsOn": ["local-plc"]
    },
    "relay": { "inherit": "garazyk-default" as any },
    "appview": { "inherit": "garazyk-default" as any }
  }
};

TopologyRegistry.register(SYRENA);
TopologyRegistry.register(TRANQUIL_PDS);
TopologyRegistry.register(ALLEGEDLY_PLC);

const COCOON_PDS: RawTopologyPresetV1 = {
  "name": "cocoon-pds",
  "description": "Cocoon PDS (Go) with Garazyk Relay, PLC, and AppView.",
  "roles": {
    "plc": { "inherit": "garazyk-default" as any },
    "pds": {
      "name": "cocoon-pds",
      "source": {
        "repo": "https://github.com/bluesky-social/cocoon.git",
        "ref": "main",
        "dockerfile": "Dockerfile"
      },
      "command": ["serve", "--port", "2583"],
      "env": {
        "COCOON_HOSTNAME": "localhost",
        "COCOON_PLC_URL": "http://local-plc:2582"
      },
      "ports": ["2583:2583"],
      "volumes": ["cocoon_pds_data:/data"],
      "healthCheck": { "path": "/xrpc/com.atproto.server.describeServer" },
      "capabilities": [
        "describeServer", "createAccount", "createSession", "getSession", "createRecord",
        "getRecord", "deleteRecord", "listRecords", "uploadBlob", "getBlob", "listBlobs",
        "resolveHandle", "updateHandle", "subscribeRepos", "getHead", "getRepo",
        "requestCrawl", "admin", "repo", "identity", "blob", "sync"
      ],
      "dependsOn": ["local-plc"]
    },
    "relay": { "inherit": "garazyk-default" as any },
    "appview": { "inherit": "garazyk-default" as any }
  }
};

TopologyRegistry.register(COCOON_PDS);
TopologyRegistry.register(HAPPYVIEW);
TopologyRegistry.register(PARAKEET);
TopologyRegistry.register(WINTERMUTE);
TopologyRegistry.register(HYDRANT);
TopologyRegistry.register(ZLAY_RELAY);
