export type BrowserFlow = "none" | "smoke" | "login" | "deep";

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
  webClient?: WebClientTopology;
  serviceUrls: Record<string, string>;
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

export function resolveTopology(webClientName?: string): Topology {
  const webClient = webClientName ? WEB_CLIENT_PRESETS[webClientName] : undefined;
  if (webClientName && !webClient) {
    throw new Error(
      `Unknown web client preset: ${webClientName}. Available: ${
        Object.keys(WEB_CLIENT_PRESETS).join(", ")
      }`,
    );
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
    webClient,
    serviceUrls,
  };
}
