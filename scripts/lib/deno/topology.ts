import { join } from "@std/path";
import {
  DEFAULT_PORTS,
  DEFAULT_SERVICE_NAMES,
  defaultRolePort,
  defaultServiceName,
  KnownServiceRole,
  ROLE_ENV_REGISTRY,
  roleEnvKey,
} from "./topology_registry.ts";
import {
  normalizeTopologyPreset,
  parseRawTopologyPresetV1,
  parseTopologyManifestJson,
  type RawTopologyPresetV1,
  type ResolvedTopology,
} from "./topology_schema.ts";

export type BrowserFlow = "none" | "smoke" | "login" | "deep";

export type ServiceRole = KnownServiceRole;

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
} from "./topology_schema.ts";

export interface InheritedAdapter {
  inherit: string;
}

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
  /**
   * Path to a Dockerfile in the Garazyk repo to copy into the cloned source
   * directory after cloning. Useful when the upstream repo doesn't ship a
   * Dockerfile. Path is relative to the Garazyk repo root.
   */
  dockerfileOverlay?: string;
  /**
   * Path to a directory in the Garazyk repo to copy into the cloned source
   * directory after cloning. The directory's contents are merged into the
   * clone root (existing files are overwritten). Useful for shipping patches,
   * config overlays, or additional build files alongside the Dockerfile.
   * Path is relative to the Garazyk repo root.
   */
  overlayDir?: string;
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
  /**
   * Config files to bind-mount from the parent adapter's source clone.
   * Keys are container paths (e.g. "/etc/garage.toml"),
   * values are paths relative to the source clone root (e.g. "garage.toml").
   * The compiler resolves these to absolute bind mounts at render time.
   */
  configFiles?: Record<string, string>;
  /** Health check definition (path-based or custom test) */
  healthCheck?: {
    /** HTTP path (null if using customTest instead) */
    path: string | null;
    /** Custom healthcheck test command — e.g. ["CMD-SHELL", "pg_isready -U plc"] */
    customTest?: string[];
    /** Extra headers for HTTP health checks */
    headers?: Record<string, string>;
  };
  /** Services this sidecar depends on (must be healthy before starting) */
  dependsOn?: string[];
  /** Per-service diagnostic HTTP probes */
  diagnostics?: DiagnosticProbeConfig[];
}

export interface ServiceAdapter {
  /** Optional v2 role marker; the map key remains authoritative for v1 presets */
  role?: ServiceRole;
  /** Adapter name — e.g. "garazyk", "reference-pds", "cocoon-pds" */
  name: string;
  /** Optional explicit Docker Compose service name */
  serviceName?: string;
  /** v2 container block; normalized into the top-level adapter shape */
  container?: Partial<ServiceAdapter>;
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
  /** Per-service diagnostic HTTP probes */
  diagnostics?: DiagnosticProbeConfig[];
  /** Environment variables injected into scenario runners for this service */
  scenarioEnv?: Record<string, string>;
}

export interface TopologyPreset {
  name: string;
  description: string;
  roles: Partial<Record<ServiceRole, ServiceAdapter | InheritedAdapter>>;
  webClient?: WebClientTopology;
  /** DNS aliases on the Docker network — e.g. { "local-appview": ["bsky.app"] } */
  networkAliases?: Record<string, string[]>;
}

export interface DiagnosticProbeConfig {
  name?: string;
  path?: string;
  url?: string;
  headers?: Record<string, string>;
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
  internalUrls: Record<string, string>;
  serviceNames: Record<string, string>;
  /** Union of all adapter capabilities from the active preset */
  capabilities: Set<string>;
  capabilitiesByRole: Record<string, Set<string>>;
  manifest?: TopologyManifest;
  resolved?: ResolvedTopology;
}

export interface SourceBuildInfo {
  /** Adapter name */
  name: string;
  /** Git remote URL */
  repo: string;
  /** Git ref — tag, branch, or commit SHA */
  ref: string;
  /** Subdirectory containing the Dockerfile */
  dockerDir: string;
  /** Dockerfile name */
  dockerfile: string;
  /** Build args */
  buildArgs: Record<string, string>;
  /** Dockerfile overlay path (relative to repo root) */
  dockerfileOverlay: string;
  /** Overlay directory path (relative to repo root) — contents are merged into the clone */
  overlayDir: string;
  /** Local path where the repo should be cloned */
  cloneDir: string;
}

export interface TopologyHealthProbe {
  role: string;
  serviceName: string;
  label: string;
  mode: "http" | "docker-health";
  url?: string;
  path?: string | null;
  headers?: Record<string, string>;
  timeoutSeconds: number;
}

export interface TopologyDiagnosticProbe {
  name: string;
  role: string;
  serviceName: string;
  url: string;
  headers?: Record<string, string>;
}

export interface TopologyManifest {
  version: 1 | 2;
  name: string;
  description: string;
  runDir: string;
  repoRoot: string;
  composeFile: string;
  networkName: string;
  serviceUrls: Record<string, string>;
  internalUrls: Record<string, string>;
  serviceNames: Record<string, string>;
  capabilities: string[];
  capabilitiesByRole: Record<string, string[]>;
  scenarioEnv: Record<string, string>;
  health: TopologyHealthProbe[];
  diagnostics: TopologyDiagnosticProbe[];
  sources: SourceBuildInfo[];
  urls?: {
    host: Record<string, string>;
    docker: Record<string, string>;
  };
  env?: {
    hostRunner: Record<string, string>;
    dockerRunner: Record<string, string>;
    scenario: Record<string, string>;
  };
  capabilitiesV2?: {
    all: string[];
    byRole: Record<string, string[]>;
  };
  resources?: Record<string, {
    cpu?: string;
    memory?: string;
    localDisk?: string;
  }>;
  services?: Record<string, {
    role: string;
    name: string;
    serviceName: string;
    capabilities: string[];
    dependencies: {
      requested: string[];
      composeServiceNames: string[];
    };
    secrets: string[];
  }>;
}

export interface TopologyResolveOptions {
  repoRoot?: string;
  runDir?: string;
  composeFile?: string;
  manifestPath?: string;
  includePds2?: boolean;
}

export const ROLE_TO_SERVICE: Record<ServiceRole, string> = DEFAULT_SERVICE_NAMES;
export const ROLE_TO_PORT: Record<ServiceRole, string> = DEFAULT_PORTS;
export const ROLE_TO_ENV: Record<string, string> = ROLE_ENV_REGISTRY;

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

function repoRootFromModule(): string {
  const scriptDir = new URL(".", import.meta.url).pathname;
  return scriptDir.replace(/\/scripts\/lib\/deno\/$/, "");
}

export function sanitizeTopologyName(name: string): string {
  return name.replace(/[^a-zA-Z0-9._-]/g, "_");
}

export function serviceNameForRole(role: string, adapter?: ServiceAdapter): string {
  return adapter?.serviceName || defaultServiceName(role);
}

export function defaultPortForRole(role: string): string {
  return defaultRolePort(role);
}

export function parsePortMapping(mapping?: string): { hostPort: string; containerPort: string } {
  if (!mapping) return { hostPort: "", containerPort: "" };
  const parts = mapping.split(":");
  if (parts.length === 1) return { hostPort: parts[0], containerPort: parts[0] };
  return {
    hostPort: parts[parts.length - 2],
    containerPort: parts[parts.length - 1],
  };
}

export function publicUrlForRole(role: string, adapter: ServiceAdapter): string {
  const parsed = parsePortMapping(adapter.ports?.[0]);
  const port = parsed.hostPort || defaultPortForRole(role);
  return `http://localhost:${port}`;
}

export function internalUrlForRole(role: string, adapter: ServiceAdapter): string {
  const parsed = parsePortMapping(adapter.ports?.[0]);
  const port = parsed.containerPort || parsed.hostPort || defaultPortForRole(role);
  return `http://${serviceNameForRole(role, adapter)}:${port}`;
}

export function roleToEnvKey(role: string): string {
  return roleEnvKey(role);
}

function clonePreset(preset: TopologyPreset): TopologyPreset {
  return JSON.parse(JSON.stringify(preset)) as TopologyPreset;
}

function normalizeAdapter(
  raw: ServiceAdapter | InheritedAdapter,
): ServiceAdapter | InheritedAdapter {
  if ("inherit" in raw) return raw;
  const container = raw.container || {};
  const merged = { ...container, ...raw } as ServiceAdapter;
  merged.healthCheck = merged.healthCheck || (merged as any).health;
  return merged;
}

/**
 * Load a topology preset from scripts/scenarios/topologies/<name>.json.
 * Validates required fields and returns the parsed TopologyPreset.
 */
export function loadTopologyPreset(name: string): TopologyPreset {
  const repoRoot = repoRootFromModule();
  const presetPath = `${repoRoot}/scripts/scenarios/topologies/${name}.json`;

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
    // Skip inheritance markers — they'll be resolved later by resolvePreset
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

function sourceInfo(
  name: string,
  source: SourceBuild,
  runDir: string,
  cloneName = name,
): SourceBuildInfo {
  return {
    name,
    repo: source.repo,
    ref: source.ref,
    dockerDir: source.dockerDir || ".",
    dockerfile: source.dockerfile || "Dockerfile",
    buildArgs: source.buildArgs || {},
    dockerfileOverlay: source.dockerfileOverlay || "",
    overlayDir: source.overlayDir || "",
    cloneDir: join(runDir, "sources", sanitizeTopologyName(cloneName)),
  };
}

export function createTopologyManifest(
  preset: TopologyPreset,
  options: {
    runDir: string;
    repoRoot: string;
    composeFile?: string;
  },
): TopologyManifest {
  const serviceUrls: Record<string, string> = {};
  const internalUrls: Record<string, string> = {};
  const serviceNames: Record<string, string> = {};
  const capabilitiesByRole: Record<string, string[]> = {};
  const capabilitySet = new Set<string>();
  const scenarioEnv: Record<string, string> = {};
  const hostRunnerEnv: Record<string, string> = {};
  const dockerRunnerEnv: Record<string, string> = {};
  const scenarioOnlyEnv: Record<string, string> = {};
  const health: TopologyHealthProbe[] = [];
  const diagnostics: TopologyDiagnosticProbe[] = [];
  const sources: SourceBuildInfo[] = [];
  const resources: TopologyManifest["resources"] = {};
  const services: NonNullable<TopologyManifest["services"]> = {};

  for (const [role, adapterValue] of Object.entries(preset.roles)) {
    if ("inherit" in adapterValue) {
      throw new Error(
        `Preset "${preset.name}" still has unresolved inheritance for role "${role}"`,
      );
    }
    const adapter = adapterValue as ServiceAdapter;
    const serviceName = serviceNameForRole(role, adapter);
    const publicUrl = publicUrlForRole(role, adapter);
    const internalUrl = internalUrlForRole(role, adapter);

    serviceUrls[role] = publicUrl;
    internalUrls[role] = internalUrl;
    serviceNames[role] = serviceName;
    hostRunnerEnv[roleToEnvKey(role)] = publicUrl;
    dockerRunnerEnv[roleToEnvKey(role)] = internalUrl;
    scenarioEnv[roleToEnvKey(role)] = publicUrl;
    Object.assign(scenarioEnv, adapter.scenarioEnv || {});
    Object.assign(scenarioOnlyEnv, adapter.scenarioEnv || {});

    const roleCapabilities = [...adapter.capabilities];
    capabilitiesByRole[role] = roleCapabilities;
    for (const cap of roleCapabilities) capabilitySet.add(cap);
    services[role] = {
      role,
      name: adapter.name,
      serviceName,
      capabilities: roleCapabilities,
      dependencies: {
        requested: adapter.dependsOn || [],
        composeServiceNames: adapter.dependsOn || [],
      },
      secrets: Object.keys(adapter.env || {}).filter((key) =>
        /(SECRET|TOKEN|PASSWORD|JWT|KEY)/i.test(key)
      ),
    };

    if (adapter.source) {
      sources.push(sourceInfo(adapter.name, adapter.source, options.runDir));
    }
    if ((adapter as any).resources) {
      resources[role] = (adapter as any).resources;
    }

    const healthCheck = adapter.healthCheck;
    const timeoutSeconds = role === "appview" ? 90 : 60;
    if (healthCheck?.path) {
      const probe: TopologyHealthProbe = {
        role,
        serviceName,
        label: role.toUpperCase(),
        mode: "http",
        url: `${publicUrl}${healthCheck.path}`,
        path: healthCheck.path,
        headers: healthCheck.headers,
        timeoutSeconds,
      };
      health.push(probe);
      diagnostics.push({
        name: `${role}-health`,
        role,
        serviceName,
        url: probe.url!,
        headers: healthCheck.headers,
      });
    } else if (healthCheck?.customTest) {
      health.push({
        role,
        serviceName,
        label: role.toUpperCase(),
        mode: "docker-health",
        path: null,
        timeoutSeconds,
      });
    }

    for (const probe of adapter.diagnostics || []) {
      const url = probe.url || `${publicUrl}${probe.path || ""}`;
      diagnostics.push({
        name: probe.name || `${role}-${diagnostics.length}`,
        role,
        serviceName,
        url,
        headers: probe.headers,
      });
    }

    for (const [sidecarName, sidecar] of Object.entries(adapter.sidecars || {})) {
      if (sidecar.source) {
        sources.push(sourceInfo(sidecarName, sidecar.source, options.runDir, sidecarName));
      }
    }
  }

  scenarioEnv.ATPROTO_TOPOLOGY = preset.name;
  scenarioEnv.ATPROTO_TOPOLOGY_CAPABILITIES = [...capabilitySet].sort().join(",");
  scenarioOnlyEnv.ATPROTO_TOPOLOGY = preset.name;
  scenarioOnlyEnv.ATPROTO_TOPOLOGY_CAPABILITIES = [...capabilitySet].sort().join(",");

  return {
    version: 2,
    name: preset.name,
    description: preset.description,
    runDir: options.runDir,
    repoRoot: options.repoRoot,
    composeFile: options.composeFile || join(options.runDir, "docker-compose.topology.yml"),
    networkName: "topology_net",
    serviceUrls,
    internalUrls,
    serviceNames,
    capabilities: [...capabilitySet].sort(),
    capabilitiesByRole,
    scenarioEnv,
    health,
    diagnostics,
    sources,
    urls: {
      host: serviceUrls,
      docker: internalUrls,
    },
    env: {
      hostRunner: {
        ...hostRunnerEnv,
        ATPROTO_TOPOLOGY: preset.name,
        ATPROTO_TOPOLOGY_CAPABILITIES: [...capabilitySet].sort().join(","),
      },
      dockerRunner: {
        ...dockerRunnerEnv,
        ATPROTO_TOPOLOGY: preset.name,
        ATPROTO_TOPOLOGY_CAPABILITIES: [...capabilitySet].sort().join(","),
      },
      scenario: scenarioOnlyEnv,
    },
    capabilitiesV2: {
      all: [...capabilitySet].sort(),
      byRole: capabilitiesByRole,
    },
    resources,
    services,
  };
}

export function writeTopologyManifest(path: string, manifest: TopologyManifest): Promise<void> {
  parseTopologyManifestJson(manifest, path);
  return Deno.writeTextFile(path, JSON.stringify(manifest, null, 2) + "\n");
}

export function loadTopologyManifest(path?: string): TopologyManifest | undefined {
  const explicitPath = path || readEnv("ATPROTO_TOPOLOGY_MANIFEST");
  const manifestPath = explicitPath;
  if (!manifestPath) return undefined;
  try {
    return parseTopologyManifestJson(
      JSON.parse(Deno.readTextFileSync(manifestPath)),
      manifestPath,
    ) as TopologyManifest;
  } catch (exc) {
    throw new Error(`Unable to load topology manifest ${manifestPath}: ${exc}`);
  }
}

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
      const serviceName = ROLE_TO_SERVICE[role as ServiceRole] || `local-${role}`;
      return [role, url.replace(/localhost|127\.0\.0\.1/, serviceName)];
    }),
  );
}

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
