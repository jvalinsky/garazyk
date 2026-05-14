export type BrowserFlow = "none" | "smoke" | "login" | "deep";

export type ServiceRole = "pds" | "pds2" | "relay" | "plc" | "appview" | "chat" | "video";

export interface SourceBuild {
  /** Git remote URL */
  repo: string;
  /** Git ref — tag, branch, or commit SHA */
  ref: string;
  /** Subdirectory within the repo containing the Dockerfile (default: repo root) */
  dockerDir?: string;
  /** Dockerfile name within dockerDir (default: "Dockerfile") */
  dockerfile?: string;
  /** Build args to pass to docker build */
  buildArgs?: Record<string, string>;
}

export interface SidecarAdapter {
  /** Docker image tag */
  image?: string;
  /** Source build configuration (alternative to image) */
  source?: SourceBuild;
  /** Override command */
  command?: string[];
  /** Environment variables */
  env?: Record<string, string>;
  /** Port mappings — e.g. ["5432:5432"] */
  ports?: string[];
  /** Volume mounts */
  volumes?: string[];
  /** Health check definition (path-based or custom test) */
  healthCheck?: {
    /** HTTP path (null if using customTest instead) */
    path: string | null;
    /** Custom healthcheck test command — e.g. ["CMD-SHELL", "pg_isready -U plc"] */
    customTest?: string[];
    /** Extra headers for HTTP health checks */
    headers?: Record<string, string>;
  };
}

export interface ServiceAdapter {
  /** Adapter name — e.g. "garazyk", "reference-pds", "cocoon-pds" */
  name: string;
  /** Docker image tag (required for non-local adapters) */
  image?: string;
  /** Source build configuration (alternative to image — clone repo and build) */
  source?: SourceBuild;
  /** Local build context path (for garazyk services) */
  buildContext?: string;
  /** Dockerfile within buildContext */
  dockerfile?: string;
  /** Override entrypoint */
  entrypoint?: string[];
  /** Override command */
  command?: string[];
  /** Environment variables */
  env?: Record<string, string>;
  /** Port mappings — e.g. ["2583:2583"] */
  ports?: string[];
  /** Volume mounts — e.g. ["local_pds_data:/var/lib/atprotopds"] */
  volumes?: string[];
  /** Health check definition */
  healthCheck: {
    /** HTTP path — e.g. "/xrpc/com.atproto.server.describeServer" (null for customTest-only) */
    path: string | null;
    /** Custom healthcheck test command — e.g. ["CMD-SHELL", "pg_isready"] */
    customTest?: string[];
    /** Extra headers (e.g. Authorization for admin endpoints) */
    headers?: Record<string, string>;
  };
  /** Capabilities this adapter supports — e.g. ["describeServer", "createAccount"] */
  capabilities: string[];
  /** Service names this adapter depends on */
  dependsOn?: string[];
  /** Sidecar containers that run alongside this service (e.g. PostgreSQL for reference PLC) */
  sidecars?: Record<string, SidecarAdapter>;
}

export interface TopologyPreset {
  name: string;
  description: string;
  roles: Partial<Record<ServiceRole, ServiceAdapter>>;
  webClient?: WebClientTopology;
  /** DNS aliases on the Docker network — e.g. { "local-appview": ["bsky.app"] } */
  networkAliases?: Record<string, string[]>;
}

export interface WebClientTopology {
  name: string;
  source: string;
  ref: string;
  buildPreset: "garazyk-ui" | "social-app" | "witchsky";
  serveCommand: string[];
  publicUrl: string;
  internalUrl: string;
  env: Record<string, string>;
  healthCheck: {
    url: string;
    intervalSeconds: number;
    timeoutSeconds: number;
    retries: number;
    startPeriodSeconds: number;
  };
  oauthRedirects: string[];
  capabilities: string[];
  browserFlow: {
    smoke: string;
    login: string;
    deep: string;
  };
  allowHybridNetwork?: boolean;
}

export interface Topology {
  preset?: TopologyPreset;
  webClient?: WebClientTopology;
  serviceUrls: Record<string, string>;
  /** Union of all adapter capabilities from the active preset */
  capabilities: Set<string>;
}

const publicWebUrl = Deno.env.get("WEB_CLIENT_URL") || "http://localhost:2591";
const internalWebUrl = Deno.env.get("WEB_CLIENT_INTERNAL_URL") || "http://web-client:2590";
const oauthClientUrl = Deno.env.get("OAUTH_CLIENT_URL");

function health(url: string) {
  return {
    url,
    intervalSeconds: 5,
    timeoutSeconds: 5,
    retries: 30,
    startPeriodSeconds: 20,
  };
}

export const WEB_CLIENT_PRESETS: Record<string, WebClientTopology> = {
  "garazyk-ui": {
    name: "garazyk-ui",
    source: "local://garazyk-ui",
    ref: Deno.env.get("GARAZYK_WEB_CLIENT_REF") || "workspace",
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
  skylab: {
    name: "skylab",
    source: "https://github.com/bluesky-social/social-app.git",
    ref: Deno.env.get("SKYLAB_WEB_CLIENT_REF") || "main",
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
  "bluesky-social/social-app": {
    name: "bluesky-social/social-app",
    source: "https://github.com/bluesky-social/social-app.git",
    ref: Deno.env.get("SOCIAL_APP_WEB_CLIENT_REF") || "main",
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
  "jollywhoppers.com/witchsky.app": {
    name: "jollywhoppers.com/witchsky.app",
    source: "https://tangled.org/jollywhoppers.com/witchsky.app",
    ref: Deno.env.get("WITCHSKY_WEB_CLIENT_REF") || "main",
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
};

/**
 * Load a topology preset from scripts/scenarios/topologies/<name>.json.
 * Validates required fields and returns the parsed TopologyPreset.
 */
export function loadTopologyPreset(name: string): TopologyPreset {
  const scriptDir = new URL(".", import.meta.url).pathname;
  const repoRoot = scriptDir.replace(/\/scripts\/lib\/deno\/$/, "");
  const presetPath = `${repoRoot}/scripts/scenarios/topologies/${name}.json`;

  let raw: string;
  try {
    raw = Deno.readTextFileSync(presetPath);
  } catch {
    throw new Error(
      `Unknown topology preset: ${name}. File not found: ${presetPath}`,
    );
  }

  const preset = JSON.parse(raw) as TopologyPreset;

  if (!preset.name || !preset.description || !preset.roles) {
    throw new Error(
      `Invalid topology preset: ${name}. Missing required fields (name, description, roles).`,
    );
  }

  for (const [role, adapter] of Object.entries(preset.roles)) {
    // Skip inheritance markers — they'll be resolved later by resolvePreset
    if ("inherit" in adapter && typeof (adapter as any).inherit === "string") continue;
    if (!adapter.name || !adapter.healthCheck || !adapter.capabilities) {
      throw new Error(
        `Invalid adapter for role "${role}" in preset "${name}": missing name, healthCheck, or capabilities.`,
      );
    }
  }

  return preset;
}

export function resolveTopology(webClientName?: string, topologyName?: string): Topology {
  const webClient = webClientName ? WEB_CLIENT_PRESETS[webClientName] : undefined;
  if (webClientName && !webClient) {
    throw new Error(
      `Unknown web client preset: ${webClientName}. Available: ${
        Object.keys(WEB_CLIENT_PRESETS).join(", ")
      }`,
    );
  }

  let preset: TopologyPreset | undefined;
  let capabilities = new Set<string>();

  if (topologyName) {
    preset = loadTopologyPreset(topologyName);
    for (const adapter of Object.values(preset.roles)) {
      for (const cap of adapter.capabilities) {
        capabilities.add(cap);
      }
    }
  }

  const serviceUrls: Record<string, string> = {
    pds: Deno.env.get("PDS_URL") || "http://localhost:2583",
    pds2: Deno.env.get("PDS2_URL") || "http://localhost:2587",
    plc: Deno.env.get("PLC_URL") || "http://localhost:2582",
    relay: Deno.env.get("RELAY_URL") || "http://localhost:2584",
    appview: Deno.env.get("APPVIEW_URL") || "http://localhost:3200",
    chat: Deno.env.get("CHAT_URL") || "http://localhost:2585",
    video: Deno.env.get("VIDEO_URL") || "http://localhost:2586",
    ui: Deno.env.get("GARAZYK_UI_URL") || "http://localhost:2590",
    oauthClient: oauthClientUrl || webClient?.publicUrl || "http://localhost:8080",
  };
  if (webClient) serviceUrls.webClient = webClient.publicUrl;

  return {
    preset,
    webClient,
    serviceUrls,
    capabilities,
  };
}
