/** Zod schemas and normalization for topology presets, manifests, and service specs. @module topology_schema */
import { z } from "zod";
import {
  defaultRolePort,
  defaultServiceName,
  ExperimentalRoleMetadata,
  isExperimentalRole,
  isKnownServiceRole,
  roleEnvKey,
  validateRoleCapability,
} from "./topology_registry.ts";

const stringRecordSchema = z.record(z.string(), z.string());
const stringArraySchema = z.array(z.string());

/** Zod schema for source build definitions */
export const sourceBuildSchema = z.object({
  repo: z.string().min(1),
  ref: z.string().min(1),
  dockerDir: z.string().optional(),
  dockerfile: z.string().optional(),
  buildArgs: stringRecordSchema.optional(),
  dockerfileOverlay: z.string().optional(),
  overlayDir: z.string().optional(),
}).strict();

/** Source build definition embedded in topology presets. */
export interface SourceBuildSpec {
  /** Source repository URL. */
  repo: string;
  /** Git ref to build. */
  ref: string;
  /** Directory containing the Dockerfile. */
  dockerDir?: string;
  /** Dockerfile name. */
  dockerfile?: string;
  /** Docker build arguments. */
  buildArgs?: Record<string, string>;
  /** Dockerfile fragment appended during rendering. */
  dockerfileOverlay?: string;
  /** Directory copied into the build context for overlay files. */
  overlayDir?: string;
}

const legacyHealthSchema = z.object({
  path: z.string().nullable(),
  customTest: stringArraySchema.optional(),
  headers: stringRecordSchema.optional(),
}).strict();

/** Zod schema for normalized port mappings */
export const portSpecSchema = z.object({
  host: z.string().optional(),
  container: z.string(),
  protocol: z.enum(["tcp", "udp"]).default("tcp"),
}).strict();

/** Normalized port mapping for container specs. */
export interface PortSpec {
  /** Optional host port. */
  host?: string;
  /** Container port. */
  container: string;
  /** Transport protocol. */
  protocol: "tcp" | "udp";
}

/** Zod schema for normalized volume mappings */
export const volumeSpecSchema = z.object({
  kind: z.enum(["named", "bind"]),
  source: z.string(),
  target: z.string(),
  mode: z.string().optional(),
}).strict();

/** Normalized volume mapping for container specs. */
export interface VolumeSpec {
  /** Volume kind. */
  kind: "named" | "bind";
  /** Host path or named volume. */
  source: string;
  /** Container mount path. */
  target: string;
  /** Optional mount mode. */
  mode?: string;
}

/** Zod schema for resource hints */
export const resourcesSchema = z.object({
  cpu: z.string().optional(),
  memory: z.string().optional(),
  localDisk: z.string().optional(),
}).strict();

/** Normalized resource requests for a service. */
export interface ResourceHints {
  /** CPU hint. */
  cpu?: string;
  /** Memory hint. */
  memory?: string;
  /** Local disk hint. */
  localDisk?: string;
}

/** Zod schema for HTTP health probes */
export const httpHealthProbeSchema = z.object({
  type: z.literal("http"),
  url: z.string().optional(),
  path: z.string().optional(),
  headers: stringRecordSchema.optional(),
  timeoutSeconds: z.number().int().positive().default(60),
}).strict();

/** Zod schema for docker health probes */
export const dockerHealthProbeSchema = z.object({
  type: z.literal("docker"),
  serviceName: z.string().min(1),
  timeoutSeconds: z.number().int().positive().default(60),
}).strict();

/** Zod schema for command health probes */
export const commandHealthProbeSchema = z.object({
  type: z.literal("command"),
  customTest: stringArraySchema.min(1),
  timeoutSeconds: z.number().int().positive().default(60),
}).strict();

/** Discriminated union of supported health probes */
export const healthProbeSchema = z.discriminatedUnion("type", [
  httpHealthProbeSchema,
  dockerHealthProbeSchema,
  commandHealthProbeSchema,
]);

/** Normalized health probe definition. */
export type HealthProbeSpec =
  | {
    /** HTTP probe discriminator. */
    type: "http";
    /** Full probe URL. */
    url?: string;
    /** Path relative to the service URL. */
    path?: string;
    /** Optional request headers. */
    headers?: Record<string, string>;
    /** Probe timeout in seconds. */
    timeoutSeconds: number;
  }
  | {
    /** Docker health probe discriminator. */
    type: "docker";
    /** Docker Compose service name. */
    serviceName: string;
    /** Probe timeout in seconds. */
    timeoutSeconds: number;
  }
  | {
    /** Command health probe discriminator. */
    type: "command";
    /** Docker healthcheck command. */
    customTest: string[];
    /** Probe timeout in seconds. */
    timeoutSeconds: number;
  };

/** Discriminated union of supported diagnostic probes */
export const diagnosticProbeSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("http"),
    name: z.string().min(1),
    url: z.string(),
    headers: stringRecordSchema.optional(),
    authSecret: z.string().optional(),
  }).strict(),
  z.object({
    type: z.literal("dockerLogs"),
    name: z.string().min(1),
    serviceName: z.string().min(1),
  }).strict(),
  z.object({
    type: z.literal("dockerInspect"),
    name: z.string().min(1),
    serviceName: z.string().min(1),
  }).strict(),
]);

/** Normalized diagnostic probe definition. */
export type DiagnosticProbeSpec =
  | {
    /** HTTP diagnostic probe discriminator. */
    type: "http";
    /** Diagnostic artifact name. */
    name: string;
    /** URL to collect. */
    url: string;
    /** Optional request headers. */
    headers?: Record<string, string>;
    /** Environment variable containing an auth secret. */
    authSecret?: string;
  }
  | {
    /** Docker logs diagnostic probe discriminator. */
    type: "dockerLogs";
    /** Diagnostic artifact name. */
    name: string;
    /** Docker Compose service name. */
    serviceName: string;
  }
  | {
    /** Docker inspect diagnostic probe discriminator. */
    type: "dockerInspect";
    /** Diagnostic artifact name. */
    name: string;
    /** Docker Compose service name. */
    serviceName: string;
  };

/** Zod schema for scenario requirements */
export const scenarioRequirementSchema = z.object({
  role: z.string().min(1).optional(),
  capability: z.string().min(1),
}).strict();

/** Scenario requirement with optional role scoping. */
export interface ScenarioRequirement {
  /** Optional service role that must provide the capability. */
  role?: string;
  /** Capability required by the scenario. */
  capability: string;
}

/** Parse a scenario requirement from string ("role:capability") or object form. */
export function parseScenarioRequirement(
  value: string | ScenarioRequirement,
): ScenarioRequirement {
  if (typeof value !== "string") return scenarioRequirementSchema.parse(value);
  const [role, capability, extra] = value.split(":");
  if (extra !== undefined) {
    throw new Error(
      `Invalid scenario requirement "${value}": expected role:capability`,
    );
  }
  return capability ? { role, capability } : { capability: role };
}

const containerPrimitiveSchema = z.object({
  image: z.string().optional(),
  source: sourceBuildSchema.optional(),
  buildContext: z.string().optional(),
  dockerfile: z.string().optional(),
  entrypoint: stringArraySchema.optional(),
  command: stringArraySchema.optional(),
  env: stringRecordSchema.optional(),
  ports: z.union([z.array(z.string()), z.array(portSpecSchema)]).optional(),
  volumes: z.union([z.array(z.string()), z.array(volumeSpecSchema)]).optional(),
  resources: resourcesSchema.optional(),
  secrets: z.array(z.string()).optional(),
  healthCheck: legacyHealthSchema.optional(),
  health: legacyHealthSchema.optional(),
  diagnostics: z.array(z.union([
    z.object({
      name: z.string().optional(),
      path: z.string().optional(),
      url: z.string().optional(),
      headers: stringRecordSchema.optional(),
    }).strict(),
    diagnosticProbeSchema,
  ])).optional(),
  dependsOn: z.array(z.string()).optional(),
  configFiles: stringRecordSchema.optional(),
}).strict();

/** Zod schema for raw sidecar specifications */
export const rawSidecarSpecSchema = containerPrimitiveSchema.extend({
  capabilities: z.array(z.string()).optional(),
});

/** Raw sidecar specification before normalization */
export type RawSidecarSpec = z.infer<typeof rawSidecarSpecSchema>;

/** Zod schema for raw service specifications */
export const rawServiceSpecSchema = containerPrimitiveSchema.extend({
  role: z.string().optional(),
  name: z.string().min(1),
  serviceName: z.string().optional(),
  container: containerPrimitiveSchema.partial().optional(),
  capabilities: z.array(z.string()).default([]),
  sidecars: z.record(rawSidecarSpecSchema).optional(),
  scenarioEnv: stringRecordSchema.optional(),
}).strict();

/** Raw service specification before normalization */
export type RawServiceSpec = z.infer<typeof rawServiceSpecSchema>;

/** Zod schema for inherited service references */
export const inheritedServiceSchema = z.object({ inherit: z.string().min(1) })
  .strict();
/** Inheritance marker for raw topology presets */
export type InheritedServiceSpec = z.infer<typeof inheritedServiceSchema>;

/** Zod schema for experimental role metadata */
export const experimentalRoleSchema = z.object({
  envVar: z.string().regex(/^[A-Z][A-Z0-9_]*$/),
  defaultPort: z.string().regex(/^\d+$/),
  runnerExposure: z.enum(["host", "docker", "both", "none"]),
}).strict();

/** Zod schema for version 1 topology presets */
export const rawTopologyPresetV1Schema = z.object({
  name: z.string().min(1),
  description: z.string().min(1),
  roles: z.record(z.union([rawServiceSpecSchema, inheritedServiceSchema])),
  experimentalRoles: z.record(experimentalRoleSchema).optional(),
  webClient: z.unknown().optional(),
  networkAliases: z.record(z.array(z.string())).optional(),
}).strict();

/** Raw topology preset shape before normalization */
export type RawTopologyPresetV1 = z.infer<typeof rawTopologyPresetV1Schema>;

/** Normalized topology preset ready for resolution
 *
 * @remarks
 * Role entries are either normalized services or inheritance markers, and experimental role metadata must be present when experimental roles are used
 */
export interface NormalizedTopologyPreset {
  /** Preset name */
  name: string;
  /** Preset description */
  description: string;
  /** Service definitions keyed by role */
  roles: Record<string, NormalizedServiceSpec | InheritedServiceSpec>;
  /** Experimental role metadata keyed by role */
  experimentalRoles: Record<string, ExperimentalRoleMetadata>;
  /** Optional host aliases keyed by service name */
  networkAliases?: Record<string, string[]>;
  /** Optional browser client payload preserved from the raw preset */
  webClient?: unknown;
}

/** Normalized container specification used by services and sidecars
 *
 * @remarks
 * Collection fields are fully normalized and defaults are applied before resolution
 */
export interface ContainerSpec {
  /** Container image to run */
  image?: string;
  /** Source build used when the container is built locally */
  source?: SourceBuildSpec;
  /** Build context path for local builds */
  buildContext?: string;
  /** Dockerfile name for local builds */
  dockerfile?: string;
  /** Entrypoint command passed to the container */
  entrypoint?: string[];
  /** Command arguments passed to the container */
  command?: string[];
  /** Environment variables injected into the container */
  env: Record<string, string>;
  /** Normalized port mappings */
  ports: PortSpec[];
  /** Normalized volume mappings */
  volumes: VolumeSpec[];
  /** Resource requests and limits */
  resources?: ResourceHints;
  /** Secret keys inferred or declared for the container */
  secrets: string[];
  /** Normalized health probe, if present */
  health?: HealthProbeSpec;
  /** Normalized diagnostic probes */
  diagnostics: DiagnosticProbeSpec[];
  /** Upstream dependencies expressed by name */
  dependsOn: string[];
  /** Config files materialized for the container */
  configFiles?: Record<string, string>;
}

/** Normalized sidecar specification */
export interface SidecarSpec extends ContainerSpec {
  /** Capability flags advertised by the sidecar */
  capabilities: string[];
}

/** Normalized service specification keyed by role
 *
 * @remarks
 * `serviceName`, `sidecars`, and `scenarioEnv` are always populated after normalization
 */
export interface NormalizedServiceSpec extends ContainerSpec {
  /** Role name for the service */
  role: string;
  /** Human-readable service label */
  name: string;
  /** Compose service name */
  serviceName: string;
  /** Capability flags advertised by the service */
  capabilities: string[];
  /** Normalized sidecars keyed by sidecar name */
  sidecars: Record<string, SidecarSpec>;
  /** Scenario environment variables exported by the service */
  scenarioEnv: Record<string, string>;
}

/** Resolved service snapshot with URLs and environment maps
 *
 * @remarks
 * This shape is derived from {@link NormalizedServiceSpec} and adds runtime-only URLs, env maps, and dependency resolution
 */
export interface ResolvedTopologyService
  extends Omit<NormalizedServiceSpec, "env"> {
  /** Host and docker URLs for the service */
  urls: {
    host: string;
    docker: string;
  };
  /** Environment maps grouped by execution target */
  env: {
    containerEnv: Record<string, string>;
    hostRunnerEnv: Record<string, string>;
    dockerRunnerEnv: Record<string, string>;
    scenarioEnv: Record<string, string>;
  };
  /** Requested and resolved dependencies */
  dependencies: {
    requested: string[];
    composeServiceNames: string[];
  };
}

/** Fully resolved topology model
 *
 * @remarks
 * All maps are keyed by role unless otherwise noted, and the URL, env, health, diagnostics, and source summaries are ready for manifests and dashboards
 */
export interface ResolvedTopology {
  /** Topology name */
  name: string;
  /** Topology description */
  description: string;
  /** Resolved services keyed by role */
  services: Record<string, ResolvedTopologyService>;
  /** Experimental role metadata keyed by role */
  experimentalRoles: Record<string, ExperimentalRoleMetadata>;
  /** All capabilities across the topology */
  capabilities: string[];
  /** Capabilities grouped by role */
  capabilitiesByRole: Record<string, string[]>;
  /** Host and docker URLs keyed by role */
  urls: {
    host: Record<string, string>;
    docker: Record<string, string>;
  };
  /** Runner and scenario environment maps */
  env: {
    hostRunner: Record<string, string>;
    dockerRunner: Record<string, string>;
    scenario: Record<string, string>;
  };
  /** Compose service names keyed by role */
  serviceNames: Record<string, string>;
  /** Health probes annotated with role metadata */
  health: Array<
    HealthProbeSpec & { role: string; serviceName: string; label: string }
  >;
  /** Diagnostic probes annotated with role metadata */
  diagnostics: Array<
    DiagnosticProbeSpec & { role: string; serviceName: string }
  >;
  /** Source build summaries annotated with role metadata */
  sources: Array<{
    role: string;
    serviceName: string;
    name: string;
    repo: string;
    ref: string;
    dockerDir: string;
    dockerfile: string;
    buildArgs: Record<string, string>;
    dockerfileOverlay: string;
    overlayDir: string;
  }>;
}

/** Parse and validate a raw topology preset JSON value */
export function parseRawTopologyPresetV1(
  value: unknown,
  pathLabel: string,
): RawTopologyPresetV1 {
  const result = rawTopologyPresetV1Schema.safeParse(value);
  if (result.success) return result.data;
  throw new Error(
    `Invalid topology preset ${pathLabel}:\n${formatZodError(result.error)}`,
  );
}

/** Normalize raw topology preset data into a {@link NormalizedTopologyPreset} */
export function normalizeTopologyPreset(
  raw: RawTopologyPresetV1,
): NormalizedTopologyPreset {
  const experimentalRoles = raw.experimentalRoles || {};
  validateRoleDeclarations(raw.roles, experimentalRoles, raw.name);

  const roles: Record<string, NormalizedServiceSpec | InheritedServiceSpec> =
    {};
  for (const [roleKey, value] of Object.entries(raw.roles)) {
    if (typeof value === "object" && value !== null && "inherit" in value) {
      roles[roleKey] = value as InheritedServiceSpec;
      continue;
    }
    roles[roleKey] = normalizeService(roleKey, value as RawServiceSpec);
  }

  return {
    name: raw.name,
    description: raw.description,
    roles,
    experimentalRoles,
    networkAliases: raw.networkAliases,
    webClient: raw.webClient,
  };
}

/** Resolve a {@link NormalizedTopologyPreset} into runtime topology data */
export function resolveNormalizedTopologyPreset(
  preset: NormalizedTopologyPreset,
): ResolvedTopology {
  const services: Record<string, ResolvedTopologyService> = {};
  const capabilities = new Set<string>();
  const capabilitiesByRole: Record<string, string[]> = {};
  const hostUrls: Record<string, string> = {};
  const dockerUrls: Record<string, string> = {};
  const hostRunner: Record<string, string> = {};
  const dockerRunner: Record<string, string> = {};
  const scenario: Record<string, string> = {};
  const serviceNames: Record<string, string> = {};
  const health: ResolvedTopology["health"] = [];
  const diagnostics: ResolvedTopology["diagnostics"] = [];
  const sources: ResolvedTopology["sources"] = [];

  for (const [role, value] of Object.entries(preset.roles)) {
    if ("inherit" in value) {
      throw new Error(
        `Preset "${preset.name}" still has unresolved inheritance for role "${role}"`,
      );
    }
    const service = value;
    const hostUrl = hostUrlForService(role, service, preset.experimentalRoles);
    const dockerUrl = dockerUrlForService(
      role,
      service,
      preset.experimentalRoles,
    );
    const envKey = roleEnvKey(role, preset.experimentalRoles);
    const roleCapabilities = service.capabilities.slice();

    validateCapabilities(role, roleCapabilities, preset.name);

    hostUrls[role] = hostUrl;
    dockerUrls[role] = dockerUrl;
    hostRunner[envKey] = hostUrl;
    dockerRunner[envKey] = dockerUrl;
    serviceNames[role] = service.serviceName;
    capabilitiesByRole[role] = roleCapabilities;
    for (const capability of roleCapabilities) capabilities.add(capability);
    Object.assign(scenario, service.scenarioEnv);

    const requestedDeps = service.dependsOn;
    const resolvedDeps = requestedDeps.map((dep) => serviceNames[dep] || dep);

    const resolvedService: ResolvedTopologyService = {
      ...service,
      urls: { host: hostUrl, docker: dockerUrl },
      env: {
        containerEnv: service.env,
        hostRunnerEnv: { [envKey]: hostUrl },
        dockerRunnerEnv: { [envKey]: dockerUrl },
        scenarioEnv: service.scenarioEnv,
      },
      dependencies: {
        requested: requestedDeps,
        composeServiceNames: resolvedDeps,
      },
    };
    services[role] = resolvedService;

    if (service.source) sources.push(sourceInfo(role, service));
    for (const [sidecarName, sidecar] of Object.entries(service.sidecars)) {
      if (sidecar.source) {
        sources.push(sourceInfo(role, sidecar, sidecarName, sidecarName));
      }
    }

    if (service.health) {
      health.push({
        ...service.health,
        role,
        serviceName: service.serviceName,
        label: role.toUpperCase(),
      });
      if (service.health.type === "http") {
        diagnostics.push({
          type: "http",
          name: `${role}-health`,
          role,
          serviceName: service.serviceName,
          url: service.health.url || `${hostUrl}${service.health.path || ""}`,
          headers: service.health.headers,
        });
      }
    }

    for (const probe of service.diagnostics) {
      diagnostics.push({ ...probe, role, serviceName: service.serviceName });
    }
  }

  scenario.ATPROTO_TOPOLOGY = preset.name;
  scenario.ATPROTO_TOPOLOGY_CAPABILITIES = [...capabilities].sort().join(",");

  return {
    name: preset.name,
    description: preset.description,
    services,
    experimentalRoles: preset.experimentalRoles,
    capabilities: [...capabilities].sort(),
    capabilitiesByRole,
    urls: { host: hostUrls, docker: dockerUrls },
    env: { hostRunner, dockerRunner, scenario },
    serviceNames,
    health,
    diagnostics,
    sources,
  };
}

function normalizeService(
  role: string,
  raw: RawServiceSpec,
): NormalizedServiceSpec {
  const container = raw.container || {};
  const merged = {
    ...container,
    ...raw,
    container: undefined,
  } as RawServiceSpec;
  const health = normalizeHealth(merged.healthCheck || merged.health);
  return {
    role: merged.role || role,
    name: merged.name,
    serviceName: merged.serviceName || defaultServiceName(role),
    image: merged.image,
    source: merged.source,
    buildContext: merged.buildContext,
    dockerfile: merged.dockerfile,
    entrypoint: merged.entrypoint,
    command: merged.command,
    env: merged.env || {},
    ports: normalizePorts(merged.ports),
    volumes: normalizeVolumes(merged.volumes),
    resources: merged.resources,
    secrets: merged.secrets || inferSecrets(merged.env || {}),
    health,
    diagnostics: normalizeDiagnostics(merged.diagnostics, role),
    dependsOn: merged.dependsOn || [],
    configFiles: merged.configFiles,
    capabilities: merged.capabilities || [],
    sidecars: normalizeSidecars(merged.sidecars || {}),
    scenarioEnv: merged.scenarioEnv || {},
  };
}

function normalizeSidecars(
  rawSidecars: Record<string, RawSidecarSpec>,
): Record<string, SidecarSpec> {
  return Object.fromEntries(
    Object.entries(rawSidecars).map(([name, raw]) => {
      const health = normalizeHealth(raw.healthCheck || raw.health);
      const sidecar: SidecarSpec = {
        image: raw.image,
        source: raw.source,
        buildContext: raw.buildContext,
        dockerfile: raw.dockerfile,
        entrypoint: raw.entrypoint,
        command: raw.command,
        env: raw.env || {},
        ports: normalizePorts(raw.ports),
        volumes: normalizeVolumes(raw.volumes),
        resources: raw.resources,
        secrets: raw.secrets || inferSecrets(raw.env || {}),
        health,
        diagnostics: normalizeDiagnostics(raw.diagnostics, name),
        dependsOn: raw.dependsOn || [],
        configFiles: raw.configFiles,
        capabilities: raw.capabilities || [],
      };
      return [name, sidecar];
    }),
  );
}

/** Normalize port declarations from string or object form */
export function normalizePorts(
  raw: string[] | PortSpec[] | undefined,
): PortSpec[] {
  return (raw || []).map((port) => {
    if (typeof port !== "string") return portSpecSchema.parse(port);
    const protocolSplit = port.split("/");
    const protocol = protocolSplit[1] === "udp" ? "udp" : "tcp";
    const parts = protocolSplit[0].split(":");
    if (parts.length === 1) return { container: parts[0], protocol };
    return {
      host: parts[parts.length - 2],
      container: parts[parts.length - 1],
      protocol,
    };
  });
}

/** Render a normalized {@link PortSpec} as Docker port syntax */
export function renderPortSpec(port: PortSpec): string {
  const base = port.host ? `${port.host}:${port.container}` : port.container;
  return port.protocol === "udp" ? `${base}/udp` : base;
}

/** Normalize volume declarations from string or object form */
export function normalizeVolumes(
  raw: string[] | VolumeSpec[] | undefined,
): VolumeSpec[] {
  return (raw || []).map((volume) => {
    if (typeof volume !== "string") return volumeSpecSchema.parse(volume);
    const parts = volume.split(":");
    if (parts.length < 2) {
      return { kind: "named", source: volume, target: volume };
    }
    const [source, target, mode] = parts;
    return {
      kind: source.startsWith(".") || source.startsWith("/") ? "bind" : "named",
      source,
      target,
      mode,
    };
  });
}

/** Render a structured VolumeSpec back to a colon-separated string. */
export function renderVolumeSpec(volume: VolumeSpec): string {
  return [volume.source, volume.target, volume.mode].filter(Boolean).join(":");
}

function normalizeHealth(
  raw: z.infer<typeof legacyHealthSchema> | undefined,
): HealthProbeSpec | undefined {
  if (!raw) return undefined;
  if (raw.customTest) {
    return { type: "command", customTest: raw.customTest, timeoutSeconds: 60 };
  }
  if (raw.path) {
    return {
      type: "http",
      path: raw.path,
      headers: raw.headers,
      timeoutSeconds: 60,
    };
  }
  return undefined;
}

function normalizeDiagnostics(
  raw: Array<any> | undefined,
  role: string,
): DiagnosticProbeSpec[] {
  return (raw || []).map((probe, index) => {
    if (probe.type) return diagnosticProbeSchema.parse(probe);
    return {
      type: "http",
      name: probe.name || `${role}-${index}`,
      url: probe.url || probe.path || "",
      headers: probe.headers,
    };
  });
}

function validateRoleDeclarations(
  roles: Record<string, unknown>,
  experimentalRoles: Record<string, ExperimentalRoleMetadata>,
  presetName: string,
) {
  for (const role of Object.keys(roles)) {
    if (isKnownServiceRole(role)) continue;
    if (!isExperimentalRole(role)) {
      throw new Error(
        `Invalid topology preset "${presetName}": unknown role "${role}". Experimental roles must use x-<name>.`,
      );
    }
    if (!experimentalRoles[role]) {
      throw new Error(
        `Invalid topology preset "${presetName}": experimental role "${role}" must declare envVar, defaultPort, and runnerExposure in experimentalRoles.`,
      );
    }
  }
}

function validateCapabilities(
  role: string,
  capabilities: string[],
  presetName: string,
) {
  const errors = capabilities
    .map((capability) => validateRoleCapability(role, capability))
    .filter((message): message is string => Boolean(message));
  if (errors.length > 0) {
    throw new Error(
      `Invalid capabilities in topology preset "${presetName}":\n${
        formatList(errors)
      }`,
    );
  }
}

function hostUrlForService(
  role: string,
  service: NormalizedServiceSpec,
  experimentalRoles: Record<string, ExperimentalRoleMetadata>,
): string {
  const port = service.ports[0]?.host ||
    defaultRolePort(role, experimentalRoles);
  return `http://localhost:${port}`;
}

function dockerUrlForService(
  role: string,
  service: NormalizedServiceSpec,
  experimentalRoles: Record<string, ExperimentalRoleMetadata>,
): string {
  const port = service.ports[0]?.container || service.ports[0]?.host ||
    defaultRolePort(role, experimentalRoles);
  return `http://${service.serviceName}:${port}`;
}

function sourceInfo(
  role: string,
  item: {
    name?: string;
    source?: z.infer<typeof sourceBuildSchema>;
    serviceName?: string;
  },
  name = item.name || role,
  serviceName = item.serviceName || defaultServiceName(role),
) {
  const source = item.source!;
  return {
    role,
    serviceName,
    name,
    repo: source.repo,
    ref: source.ref,
    dockerDir: source.dockerDir || ".",
    dockerfile: source.dockerfile || "Dockerfile",
    buildArgs: source.buildArgs || {},
    dockerfileOverlay: source.dockerfileOverlay || "",
    overlayDir: source.overlayDir || "",
  };
}

function inferSecrets(env: Record<string, string>): string[] {
  return Object.keys(env).filter((key) =>
    /(SECRET|TOKEN|PASSWORD|JWT|KEY)/i.test(key)
  );
}

function formatList(items: string[]): string {
  return items.map((item) => `  - ${item}`).join("\n");
}

/** Format a Zod validation error into a human-readable string. */
export function formatZodError(error: z.ZodError): string {
  return error.issues.map((issue) => {
    const path = issue.path.length ? issue.path.join(".") : "(root)";
    return `  - ${path}: ${issue.message}`;
  }).join("\n");
}

const sourceBuildInfoSchema = z.object({
  name: z.string(),
  repo: z.string(),
  ref: z.string(),
  dockerDir: z.string(),
  dockerfile: z.string(),
  buildArgs: stringRecordSchema,
  dockerfileOverlay: z.string(),
  overlayDir: z.string(),
  cloneDir: z.string(),
}).strict();

const manifestHealthProbeSchema = z.object({
  role: z.string(),
  serviceName: z.string(),
  label: z.string(),
  mode: z.enum(["http", "docker-health"]),
  url: z.string().optional(),
  path: z.string().nullable().optional(),
  headers: stringRecordSchema.optional(),
  timeoutSeconds: z.number().int().positive(),
}).strict();

const manifestDiagnosticProbeSchema = z.object({
  name: z.string(),
  role: z.string(),
  serviceName: z.string(),
  url: z.string(),
  headers: stringRecordSchema.optional(),
}).strict();

const topologyManifestV1Schema = z.object({
  version: z.literal(1),
  name: z.string(),
  description: z.string(),
  runDir: z.string(),
  repoRoot: z.string(),
  composeFile: z.string(),
  networkName: z.string(),
  serviceUrls: stringRecordSchema,
  internalUrls: stringRecordSchema,
  serviceNames: stringRecordSchema,
  capabilities: z.array(z.string()),
  capabilitiesByRole: z.record(z.array(z.string())),
  scenarioEnv: stringRecordSchema,
  health: z.array(manifestHealthProbeSchema),
  diagnostics: z.array(manifestDiagnosticProbeSchema),
  sources: z.array(sourceBuildInfoSchema),
}).strict();

const topologyManifestV2Schema = topologyManifestV1Schema.extend({
  version: z.literal(2),
  urls: z.object({
    host: stringRecordSchema,
    docker: stringRecordSchema,
  }).strict(),
  env: z.object({
    hostRunner: stringRecordSchema,
    dockerRunner: stringRecordSchema,
    scenario: stringRecordSchema,
  }).strict(),
  capabilitiesV2: z.object({
    all: z.array(z.string()),
    byRole: z.record(z.array(z.string())),
  }).strict(),
  resources: z.record(resourcesSchema).default({}),
  services: z.record(
    z.object({
      role: z.string(),
      name: z.string(),
      serviceName: z.string(),
      capabilities: z.array(z.string()),
      dependencies: z.object({
        requested: z.array(z.string()),
        composeServiceNames: z.array(z.string()),
      }).strict(),
      secrets: z.array(z.string()),
    }).strict(),
  ),
}).strict();

/** Zod schema for versioned topology manifests
 *
 * @remarks
 * Supports the version 1 and version 2 manifest layouts
 */
export const topologyManifestSchema = z.union([
  topologyManifestV1Schema,
  topologyManifestV2Schema,
]);

/** Validated topology manifest JSON */
export type ParsedTopologyManifest = z.infer<typeof topologyManifestSchema>;

/** Parse and validate a topology manifest JSON value. */
export function parseTopologyManifestJson(
  value: unknown,
  pathLabel: string,
): ParsedTopologyManifest {
  const result = topologyManifestSchema.safeParse(value);
  if (result.success) return result.data;
  throw new Error(
    `Invalid topology manifest ${pathLabel}:\n${formatZodError(result.error)}`,
  );
}
