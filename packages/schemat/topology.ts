/**
 * ATProto network topology management — presets, inheritance, and resolution.
 *
 * Re-exports types and manifest helpers from topology_types.ts and
 * topology_manifest.ts for backward compatibility.
 *
 * @module topology
 */

import { join, resolve } from "@std/path";
import {
  normalizeTopologyPreset,
  parseRawTopologyPresetV1,
  renderPortSpec,
  renderVolumeSpec,
} from "./topology_schema.ts";
import { TopologyRegistry } from "./topology_presets.ts";

export { TopologyRegistry };

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
  dependencyInfoForService,
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
export {
  ROLE_TO_ENV,
  ROLE_TO_PORT,
  ROLE_TO_SERVICE,
} from "./topology_types.ts";

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
  NormalizedServiceSpec,
  ServiceAdapter,
  ServiceRole,
  SidecarAdapter,
  SidecarSpec,
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
const internalWebUrl = readEnv("WEB_CLIENT_INTERNAL_URL") ||
  "http://web-client:2590";
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

function denormalizeService(service: NormalizedServiceSpec): ServiceAdapter {
  return {
    role: service.role as ServiceRole,
    name: service.name,
    serviceName: service.serviceName,
    image: service.image,
    source: service.source,
    buildContext: service.buildContext,
    dockerfile: service.dockerfile,
    entrypoint: service.entrypoint,
    command: service.command,
    env: emptyObjectToUndefined(service.env),
    ports: service.ports.map(renderPortSpec),
    volumes: service.volumes.map(renderVolumeSpec),
    healthCheck: denormalizeHealth(service.health),
    capabilities: service.capabilities,
    dependsOn: emptyArrayToUndefined(service.dependsOn),
    dependsOnRoles: emptyArrayToUndefined(service.dependsOnRoles) as
      | ServiceRole[]
      | undefined,
    sidecars: denormalizeSidecars(service.sidecars),
    diagnostics: denormalizeDiagnostics(service.diagnostics),
    scenarioEnv: emptyObjectToUndefined(service.scenarioEnv),
  };
}

function denormalizeSidecars(
  sidecars: Record<string, SidecarSpec>,
): Record<string, SidecarAdapter> | undefined {
  const entries = Object.entries(sidecars);
  if (entries.length === 0) return undefined;
  return Object.fromEntries(
    entries.map(([name, sidecar]) => [
      name,
      {
        image: sidecar.image,
        source: sidecar.source,
        command: sidecar.command,
        env: emptyObjectToUndefined(sidecar.env),
        ports: sidecar.ports.map(renderPortSpec),
        volumes: sidecar.volumes.map(renderVolumeSpec),
        configFiles: sidecar.configFiles,
        healthCheck: denormalizeHealth(sidecar.health),
        dependsOn: emptyArrayToUndefined(sidecar.dependsOn),
        dependsOnRoles: emptyArrayToUndefined(sidecar.dependsOnRoles) as
          | ServiceRole[]
          | undefined,
        diagnostics: denormalizeDiagnostics(sidecar.diagnostics),
      },
    ]),
  );
}

function denormalizeHealth(
  health: NormalizedServiceSpec["health"],
): ServiceAdapter["healthCheck"] {
  if (!health) return { path: null };
  if (health.type === "command") {
    return { path: null, customTest: health.customTest };
  }
  if (health.type === "http") {
    return { path: health.path || null, headers: health.headers };
  }
  return { path: null };
}

function denormalizeDiagnostics(
  diagnostics: NormalizedServiceSpec["diagnostics"],
): ServiceAdapter["diagnostics"] {
  if (diagnostics.length === 0) return undefined;
  return diagnostics
    .filter((probe) => probe.type === "http")
    .map((probe) => ({
      name: probe.name,
      url: probe.url,
      headers: probe.headers,
    }));
}

function denormalizePreset(
  rawPreset: ReturnType<typeof normalizeTopologyPreset>,
): TopologyPreset {
  const roles: TopologyPreset["roles"] = {};
  for (const [role, value] of Object.entries(rawPreset.roles)) {
    roles[role as ServiceRole] = "inherit" in value
      ? value
      : denormalizeService(value);
  }
  return {
    name: rawPreset.name,
    description: rawPreset.description,
    roles,
    webClient: rawPreset.webClient as WebClientTopology | undefined,
    networkAliases: rawPreset.networkAliases,
  };
}

function emptyObjectToUndefined(
  value: Record<string, string>,
): Record<string, string> | undefined {
  return Object.keys(value).length > 0 ? value : undefined;
}

function emptyArrayToUndefined<T>(value: T[]): T[] | undefined {
  return value.length > 0 ? value : undefined;
}

/**
 * Load a topology preset from the registry or an optional filesystem directory.
 * @param name - Preset name
 * @param presetDir - Optional directory to search for preset JSON files.
 * @returns The loaded topology preset
 * @throws {Error} If the preset is not found or is invalid.
 */
export function loadTopologyPreset(
  name: string,
  presetDir?: string,
): TopologyPreset {
  // 1. Check registry for embedded presets
  const embedded = TopologyRegistry.getPreset(name);
  if (embedded) {
    const rawPreset = parseRawTopologyPresetV1(embedded, `registry:${name}`);
    const preset = denormalizePreset(normalizeTopologyPreset(rawPreset));
    for (const [role, adapter] of Object.entries(preset.roles)) {
      preset.roles[role as ServiceRole] = normalizeAdapter(adapter);
    }
    return preset;
  }

  // 2. Check filesystem (legacy/override)
  if (!presetDir) {
    throw new Error(
      `Unknown topology preset: ${name}. No presetDir provided for filesystem lookup.`,
    );
  }

  if (!/^[a-zA-Z0-9_-]+$/.test(name)) {
    throw new Error(
      `Invalid topology preset name: "${name}". Only alphanumeric characters, hyphens, and underscores are allowed.`,
    );
  }

  const presetPath = join(presetDir, `${name}.json`);

  const resolvedPath = resolve(presetPath);
  const resolvedDir = resolve(presetDir);
  if (
    !resolvedPath.startsWith(resolvedDir + "/") && resolvedPath !== resolvedDir
  ) {
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
    throw new Error(
      `Invalid topology preset ${presetPath}: malformed JSON (${exc})`,
    );
  }

  const rawPreset = parseRawTopologyPresetV1(rawJson, presetPath);
  const preset = denormalizePreset(normalizeTopologyPreset(rawPreset));

  for (const [role, adapter] of Object.entries(preset.roles)) {
    preset.roles[role as ServiceRole] = normalizeAdapter(adapter);
    if ("inherit" in adapter && typeof (adapter as any).inherit === "string") {
      continue;
    }
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
  presetDir?: string,
): ServiceAdapter {
  const normalized = normalizeAdapter(adapter);
  if (!("inherit" in normalized)) return normalized;

  const parentName = normalized.inherit;
  const key = `${parentName}:${role}`;
  if (seen.includes(key)) {
    throw new Error(
      `Topology inheritance cycle for role "${role}": ${
        [...seen, key].join(" -> ")
      }`,
    );
  }

  const parentPreset = loadTopologyPreset(parentName, presetDir);
  const parentAdapter = parentPreset.roles[role];
  if (!parentAdapter) {
    throw new Error(
      `Inheritance failed: role "${role}" not found in parent preset "${parentName}"`,
    );
  }
  return resolveInheritedAdapter(
    role,
    parentAdapter,
    [...seen, key],
    presetDir,
  );
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
  options: { includePds2?: boolean; presetDir?: string } = {},
): TopologyPreset {
  const preset = clonePreset(loadTopologyPreset(presetName, options.presetDir));
  const resolvedRoles: Partial<Record<ServiceRole, ServiceAdapter>> = {};
  const includePds2 = options.includePds2 === true;

  for (const [role, adapter] of Object.entries(preset.roles)) {
    if (role === "pds2" && !includePds2) continue;
    resolvedRoles[role as ServiceRole] = resolveInheritedAdapter(
      role as ServiceRole,
      adapter,
      [`${presetName}:${role}`],
      options.presetDir,
    );
  }

  if (includePds2 && !resolvedRoles.pds2) {
    const defaultPreset = loadTopologyPreset(
      "garazyk-default",
      options.presetDir,
    );
    const defaultPds2 = defaultPreset.roles.pds2;
    if (defaultPds2) {
      resolvedRoles.pds2 = resolveInheritedAdapter("pds2", defaultPds2, [
        "garazyk-default:pds2",
      ], options.presetDir);
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
    Object.entries(capabilitiesByRole).map((
      [role, caps],
    ) => [role, new Set(caps)]),
  );
}

function defaultServiceUrls(
  webClient?: WebClientTopology,
): Record<string, string> {
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
    oauthClient: oauthClientUrl || webClient?.publicUrl ||
      "http://localhost:8080",
  };
  if (webClient) urls.webClient = webClient.publicUrl;
  return urls;
}

function defaultInternalUrls(
  serviceUrls: Record<string, string>,
): Record<string, string> {
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
  const webClient = webClientName
    ? TopologyRegistry.getWebClient(webClientName)
    : undefined;
  if (webClientName && !webClient) {
    throw new Error(
      `Unknown web client preset: ${webClientName}. Available: ${
        TopologyRegistry.listWebClients().join(", ")
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
        ? resolvePreset(topologyName, {
          includePds2: options.includePds2,
          presetDir: options.presetDir,
        })
        : undefined,
      webClient,
      serviceUrls,
      internalUrls: {
        ...defaultInternalUrls(serviceUrls),
        ...(manifest.urls?.docker || manifest.internalUrls),
      },
      serviceNames: manifest.serviceNames,
      capabilities: new Set(
        manifest.capabilitiesV2?.all || manifest.capabilities,
      ),
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
    preset = resolvePreset(topologyName, {
      includePds2: options.includePds2,
      presetDir: options.presetDir,
    });
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
