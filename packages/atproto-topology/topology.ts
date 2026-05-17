/**
 * ATProto network topology management — presets, inheritance, and resolution.
 *
 * Re-exports types and manifest helpers from topology_types.ts and
 * topology_manifest.ts for backward compatibility.
 *
 * @module topology
 */

import { join, resolve } from "@std/path";
import { normalizeTopologyPreset, parseRawTopologyPresetV1 } from "./topology_schema.ts";

// Re-export all types
export type { BrowserFlow, ServiceRole } from "./topology_types.ts";
export type {
  ContainerSpec,
  DiagnosticProbeSpec,
  HealthProbeSpec,
  NormalizedServiceSpec,
  NormalizedTopologyPreset,
  PortSpec,
  RawTopologyPresetV1,
  ResolvedTopology,
  ScenarioRequirement,
  SidecarSpec,
  VolumeSpec,
} from "./topology_types.ts";
export type {
  DiagnosticProbeConfig,
  InheritedAdapter,
  ServiceAdapter,
  ServiceRole as ServiceRoleAlias,
  SidecarAdapter,
  SourceBuild,
  SourceBuildInfo,
  Topology,
  TopologyDiagnosticProbe,
  TopologyHealthProbe,
  TopologyManifest,
  TopologyPreset,
  TopologyResolveOptions,
  WebClientTopology,
} from "./topology_types.ts";

// Re-export manifest helpers
export {
  createTopologyManifest,
  defaultPortForRole,
  internalUrlForRole,
  loadTopologyManifest,
  parsePortMapping,
  publicUrlForRole,
  roleToEnvKey,
  sanitizeTopologyName,
  serviceNameForRole,
  writeTopologyManifest,
} from "./topology_manifest.ts";

// Re-export constants
export { ROLE_TO_ENV, ROLE_TO_PORT, ROLE_TO_SERVICE } from "./topology_types.ts";

// ---------------------------------------------------------------------------
// Internal imports
// ---------------------------------------------------------------------------

import {
  internalUrlForRole,
  loadTopologyManifest,
  publicUrlForRole,
  roleToEnvKey,
  sanitizeTopologyName,
  serviceNameForRole,
} from "./topology_manifest.ts";
import type {
  InheritedAdapter,
  ServiceAdapter,
  ServiceRole,
  Topology,
  TopologyPreset,
  TopologyResolveOptions,
  WebClientTopology,
} from "./topology_types.ts";
import {
  defaultRolePort,
  defaultServiceName,
  KnownServiceRole,
  roleEnvKey,
} from "./topology_registry.ts";

// ---------------------------------------------------------------------------
// Web client presets
// ---------------------------------------------------------------------------

function readEnv(name: string): string | undefined {
  try {
    return Deno.env.get(name) || undefined;
  } catch {
    return undefined;
  }
}

const publicWebUrl = readEnv("WEB_CLIENT_URL") || "http://localhost:2591";
const internalWebUrl = readEnv("WEB_CLIENT_INTERNAL_URL") || "http://web-client:2590";
const oauthClientUrl = readEnv("OAUTH_CLIENT_URL");

function health(url: string) {
  return {
    url,
    intervalSeconds: 5,
    timeoutSeconds: 5,
    retries: 30,
    startPeriodSeconds: 20,
  };
}

/** Built-in web client topology presets. */
export const WEB_CLIENT_PRESETS: Record<string, WebClientTopology> = {
  "garazyk-ui": {
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
  skylab: {
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
  "bluesky-social/social-app": {
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
  "jollywhoppers.com/witchsky.app": {
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
};

// ---------------------------------------------------------------------------
// Repo root
// ---------------------------------------------------------------------------

function repoRootFromModule(): string {
  const scriptDir = new URL(".", import.meta.url).pathname;
  return scriptDir.replace(/\/packages\/atproto-topology\/$/, "");
}

// ---------------------------------------------------------------------------
// Preset loading
// ---------------------------------------------------------------------------

function normalizeAdapter(
  raw: ServiceAdapter | InheritedAdapter,
): ServiceAdapter | InheritedAdapter {
  if ("inherit" in raw) return raw;
  const container = raw.container || {};
  const merged = { ...container, ...raw } as ServiceAdapter;
  merged.healthCheck = merged.healthCheck || (merged as any).health;
  return merged;
}

function clonePreset(preset: TopologyPreset): TopologyPreset {
  return JSON.parse(JSON.stringify(preset)) as TopologyPreset;
}

/**
 * Load a topology preset from scripts/scenarios/topologies/<name>.json.
 */
export function loadTopologyPreset(name: string): TopologyPreset {
  if (!/^[a-zA-Z0-9_-]+$/.test(name)) {
    throw new Error(
      `Invalid topology preset name: "${name}". Only alphanumeric characters, hyphens, and underscores are allowed.`,
    );
  }

  const repoRoot = repoRootFromModule();
  const topologiesDir = join(repoRoot, "scripts/scenarios/topologies");
  const presetPath = join(topologiesDir, `${name}.json`);

  const resolvedPath = resolve(presetPath);
  const resolvedDir = resolve(topologiesDir);
  if (!resolvedPath.startsWith(resolvedDir + "/") && resolvedPath !== resolvedDir) {
    throw new Error(
      `Preset path escapes topologies directory: ${presetPath} (resolved: ${resolvedPath})`,
    );
  }

  let rawText: string;
  try {
    rawText = Deno.readTextFileSync(presetPath);
  } catch {
    throw new Error(
      `Unknown topology preset: ${name}. File not found: ${presetPath}`,
    );
  }

  let rawJson: unknown;
  try {
    rawJson = JSON.parse(rawText);
  } catch (exc) {
    throw new Error(`Invalid topology preset ${presetPath}: malformed JSON (${exc})`);
  }

  const rawPreset = parseRawTopologyPresetV1(rawJson, presetPath);
  normalizeTopologyPreset(rawPreset);
  const preset = rawPreset as unknown as TopologyPreset;

  for (const [role, adapter] of Object.entries(preset.roles)) {
    preset.roles[role as ServiceRole] = normalizeAdapter(adapter);
    if ("inherit" in adapter && typeof (adapter as any).inherit === "string") continue;
    const concrete = preset.roles[role as ServiceRole] as ServiceAdapter;
    if (!concrete.name || !concrete.healthCheck || !concrete.capabilities) {
      throw new Error(
        `Invalid adapter for role "${role}" in preset "${name}": missing name, healthCheck, or capabilities.`,
      );
    }
  }

  return preset;
}

// ---------------------------------------------------------------------------
// Inheritance resolution
// ---------------------------------------------------------------------------

function resolveInheritedAdapter(
  role: ServiceRole,
  adapter: ServiceAdapter | InheritedAdapter,
  seen: string[],
): ServiceAdapter {
  const normalized = normalizeAdapter(adapter);
  if (!("inherit" in normalized)) return normalized;

  const parentName = normalized.inherit;
  const key = `${parentName}:${role}`;
  if (seen.includes(key)) {
    throw new Error(
      `Topology inheritance cycle for role "${role}": ${[...seen, key].join(" -> ")}`,
    );
  }

  const parentPreset = loadTopologyPreset(parentName);
  const parentAdapter = parentPreset.roles[role];
  if (!parentAdapter) {
    throw new Error(
      `Inheritance failed: role "${role}" not found in parent preset "${parentName}"`,
    );
  }
  return resolveInheritedAdapter(role, parentAdapter, [...seen, key]);
}

/** 
 * Resolve a preset and its inherited role adapters. 
 * @param presetName - Topology preset name. 
 * @param options - Resolution options. 
 * @returns A resolved topology preset. 
 * @throws {Error} If the preset is not found or is invalid.
 */
export function resolvePreset(
  presetName: string,
  options: { includePds2?: boolean } = {},
): TopologyPreset {
  const preset = clonePreset(loadTopologyPreset(presetName));
  const resolvedRoles: Partial<Record<ServiceRole, ServiceAdapter>> = {};
  const includePds2 = options.includePds2 === true;

  for (const [role, adapter] of Object.entries(preset.roles)) {
    if (role === "pds2" && !includePds2) continue;
    resolvedRoles[role as ServiceRole] = resolveInheritedAdapter(
      role as ServiceRole,
      adapter,
      [`${presetName}:${role}`],
    );
  }

  if (includePds2 && !resolvedRoles.pds2) {
    const defaultPreset = loadTopologyPreset("garazyk-default");
    const defaultPds2 = defaultPreset.roles.pds2;
    if (defaultPds2) {
      resolvedRoles.pds2 = resolveInheritedAdapter("pds2", defaultPds2, ["garazyk-default:pds2"]);
    }
  }

  return {
    ...preset,
    roles: resolvedRoles,
  };
}

// ---------------------------------------------------------------------------
// URL defaults
// ---------------------------------------------------------------------------

function capabilitiesByRoleToSets(
  capabilitiesByRole: Record<string, string[]>,
): Record<string, Set<string>> {
  return Object.fromEntries(
    Object.entries(capabilitiesByRole).map(([role, caps]) => [role, new Set(caps)]),
  );
}

function defaultServiceUrls(webClient?: WebClientTopology): Record<string, string> {
  const urls: Record<string, string> = {
    pds: readEnv("PDS_URL") || "http://localhost:2583",
    pds2: readEnv("PDS2_URL") || "http://localhost:2587",
    plc: readEnv("PLC_URL") || "http://localhost:2582",
    relay: readEnv("RELAY_URL") || "http://localhost:2584",
    appview: readEnv("APPVIEW_URL") || "http://localhost:3200",
    chat: readEnv("CHAT_URL") || "http://localhost:2585",
    video: readEnv("VIDEO_URL") || "http://localhost:2586",
    ui: readEnv("GARAZYK_UI_URL") || "http://localhost:2590",
    backfill: readEnv("BACKFILL_URL") || "http://localhost:2480",
    oauthClient: oauthClientUrl || webClient?.publicUrl || "http://localhost:8080",
  };
  if (webClient) urls.webClient = webClient.publicUrl;
  return urls;
}

function defaultInternalUrls(serviceUrls: Record<string, string>): Record<string, string> {
  return Object.fromEntries(
    Object.entries(serviceUrls).map(([role, url]) => {
      const serviceName = defaultServiceName(role);
      return [role, url.replace(/localhost|127\.0\.0\.1/, serviceName)];
    }),
  );
}

// ---------------------------------------------------------------------------
// Topology resolution
// ---------------------------------------------------------------------------

/** Resolve a complete topology view from preset and manifest inputs. @param webClientName - Optional web client preset name. @param topologyName - Optional topology preset name. @param options - Resolution options. @returns The resolved topology configuration. */
export function resolveTopology(
  webClientName?: string,
  topologyName?: string,
  options: TopologyResolveOptions = {},
): Topology {
  const webClient = webClientName ? WEB_CLIENT_PRESETS[webClientName] : undefined;
  if (webClientName && !webClient) {
    throw new Error(
      `Unknown web client preset: ${webClientName}. Available: ${
        Object.keys(WEB_CLIENT_PRESETS).join(", ")
      }`,
    );
  }

  const manifest = loadTopologyManifest(options.manifestPath);
  if (manifest) {
    const serviceUrls = {
      ...defaultServiceUrls(webClient),
      ...(manifest.urls?.host || manifest.serviceUrls),
    };
    if (webClient) serviceUrls.webClient = webClient.publicUrl;
    return {
      preset: topologyName
        ? resolvePreset(topologyName, { includePds2: options.includePds2 })
        : undefined,
      webClient,
      serviceUrls,
      internalUrls: {
        ...defaultInternalUrls(serviceUrls),
        ...(manifest.urls?.docker || manifest.internalUrls),
      },
      serviceNames: manifest.serviceNames,
      capabilities: new Set(manifest.capabilitiesV2?.all || manifest.capabilities),
      capabilitiesByRole: capabilitiesByRoleToSets(
        manifest.capabilitiesV2?.byRole || manifest.capabilitiesByRole,
      ),
      manifest,
    };
  }

  let preset: TopologyPreset | undefined;
  let capabilities = new Set<string>();
  let capabilitiesByRole: Record<string, Set<string>> = {};
  let serviceNames: Record<string, string> = {};
  let internalUrls: Record<string, string> = {};

  if (topologyName) {
    preset = resolvePreset(topologyName, { includePds2: options.includePds2 });
    for (const [role, adapter] of Object.entries(preset.roles)) {
      if ("inherit" in adapter) continue;
      capabilitiesByRole[role] = new Set(adapter.capabilities);
      serviceNames[role] = serviceNameForRole(role, adapter);
      internalUrls[role] = internalUrlForRole(role, adapter);
      for (const cap of adapter.capabilities) {
        capabilities.add(cap);
      }
    }
  }

  const serviceUrls = defaultServiceUrls(webClient);
  if (preset) {
    for (const [role, adapter] of Object.entries(preset.roles)) {
      if ("inherit" in adapter) continue;
      serviceUrls[role] = publicUrlForRole(role, adapter);
    }
  }
  internalUrls = { ...defaultInternalUrls(serviceUrls), ...internalUrls };

  return {
    preset,
    webClient,
    serviceUrls,
    internalUrls,
    serviceNames,
    capabilities,
    capabilitiesByRole,
  };
}
