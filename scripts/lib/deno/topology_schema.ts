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

export const sourceBuildSchema = z.object({
  repo: z.string().min(1),
  ref: z.string().min(1),
  dockerDir: z.string().optional(),
  dockerfile: z.string().optional(),
  buildArgs: stringRecordSchema.optional(),
  dockerfileOverlay: z.string().optional(),
  overlayDir: z.string().optional(),
}).strict();

const legacyHealthSchema = z.object({
  path: z.string().nullable(),
  customTest: stringArraySchema.optional(),
  headers: stringRecordSchema.optional(),
}).strict();

export const portSpecSchema = z.object({
  host: z.string().optional(),
  container: z.string(),
  protocol: z.enum(["tcp", "udp"]).default("tcp"),
}).strict();

export type PortSpec = z.infer<typeof portSpecSchema>;

export const volumeSpecSchema = z.object({
  kind: z.enum(["named", "bind"]),
  source: z.string(),
  target: z.string(),
  mode: z.string().optional(),
}).strict();

export type VolumeSpec = z.infer<typeof volumeSpecSchema>;

export const resourcesSchema = z.object({
  cpu: z.string().optional(),
  memory: z.string().optional(),
  localDisk: z.string().optional(),
}).strict();

export type ResourceHints = z.infer<typeof resourcesSchema>;

export const httpHealthProbeSchema = z.object({
  type: z.literal("http"),
  url: z.string().optional(),
  path: z.string().optional(),
  headers: stringRecordSchema.optional(),
  timeoutSeconds: z.number().int().positive().default(60),
}).strict();

export const dockerHealthProbeSchema = z.object({
  type: z.literal("docker"),
  serviceName: z.string().min(1),
  timeoutSeconds: z.number().int().positive().default(60),
}).strict();

export const commandHealthProbeSchema = z.object({
  type: z.literal("command"),
  customTest: stringArraySchema.min(1),
  timeoutSeconds: z.number().int().positive().default(60),
}).strict();

export const healthProbeSchema = z.discriminatedUnion("type", [
  httpHealthProbeSchema,
  dockerHealthProbeSchema,
  commandHealthProbeSchema,
]);

export type HealthProbeSpec = z.infer<typeof healthProbeSchema>;

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

export type DiagnosticProbeSpec = z.infer<typeof diagnosticProbeSchema>;

export const scenarioRequirementSchema = z.object({
  role: z.string().min(1).optional(),
  capability: z.string().min(1),
}).strict();

export type ScenarioRequirement = z.infer<typeof scenarioRequirementSchema>;

export function parseScenarioRequirement(value: string | ScenarioRequirement): ScenarioRequirement {
  if (typeof value !== "string") return scenarioRequirementSchema.parse(value);
  const [role, capability, extra] = value.split(":");
  if (extra !== undefined) {
    throw new Error(`Invalid scenario requirement "${value}": expected role:capability`);
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

export const rawSidecarSpecSchema = containerPrimitiveSchema.extend({
  capabilities: z.array(z.string()).optional(),
});

export type RawSidecarSpec = z.infer<typeof rawSidecarSpecSchema>;

export const rawServiceSpecSchema = containerPrimitiveSchema.extend({
  role: z.string().optional(),
  name: z.string().min(1),
  serviceName: z.string().optional(),
  container: containerPrimitiveSchema.partial().optional(),
  capabilities: z.array(z.string()).default([]),
  sidecars: z.record(rawSidecarSpecSchema).optional(),
  scenarioEnv: stringRecordSchema.optional(),
}).strict();

export type RawServiceSpec = z.infer<typeof rawServiceSpecSchema>;

export const inheritedServiceSchema = z.object({ inherit: z.string().min(1) }).strict();
export type InheritedServiceSpec = z.infer<typeof inheritedServiceSchema>;

export const experimentalRoleSchema = z.object({
  envVar: z.string().regex(/^[A-Z][A-Z0-9_]*$/),
  defaultPort: z.string().regex(/^\d+$/),
  runnerExposure: z.enum(["host", "docker", "both", "none"]),
}).strict();

export const rawTopologyPresetV1Schema = z.object({
  name: z.string().min(1),
  description: z.string().min(1),
  roles: z.record(z.union([rawServiceSpecSchema, inheritedServiceSchema])),
  experimentalRoles: z.record(experimentalRoleSchema).optional(),
  webClient: z.unknown().optional(),
  networkAliases: z.record(z.array(z.string())).optional(),
}).strict();

export type RawTopologyPresetV1 = z.infer<typeof rawTopologyPresetV1Schema>;

export interface NormalizedTopologyPreset {
  name: string;
  description: string;
  roles: Record<string, NormalizedServiceSpec | InheritedServiceSpec>;
  experimentalRoles: Record<string, ExperimentalRoleMetadata>;
  networkAliases?: Record<string, string[]>;
  webClient?: unknown;
}

export interface ContainerSpec {
  image?: string;
  source?: z.infer<typeof sourceBuildSchema>;
  buildContext?: string;
  dockerfile?: string;
  entrypoint?: string[];
  command?: string[];
  env: Record<string, string>;
  ports: PortSpec[];
  volumes: VolumeSpec[];
  resources?: ResourceHints;
  secrets: string[];
  health?: HealthProbeSpec;
  diagnostics: DiagnosticProbeSpec[];
  dependsOn: string[];
  configFiles?: Record<string, string>;
}

export interface SidecarSpec extends ContainerSpec {
  capabilities: string[];
}

export interface NormalizedServiceSpec extends ContainerSpec {
  role: string;
  name: string;
  serviceName: string;
  capabilities: string[];
  sidecars: Record<string, SidecarSpec>;
  scenarioEnv: Record<string, string>;
}

export interface ResolvedTopologyService extends Omit<NormalizedServiceSpec, "env"> {
  urls: {
    host: string;
    docker: string;
  };
  env: {
    containerEnv: Record<string, string>;
    hostRunnerEnv: Record<string, string>;
    dockerRunnerEnv: Record<string, string>;
    scenarioEnv: Record<string, string>;
  };
  dependencies: {
    requested: string[];
    composeServiceNames: string[];
  };
}

export interface ResolvedTopology {
  name: string;
  description: string;
  services: Record<string, ResolvedTopologyService>;
  experimentalRoles: Record<string, ExperimentalRoleMetadata>;
  capabilities: string[];
  capabilitiesByRole: Record<string, string[]>;
  urls: {
    host: Record<string, string>;
    docker: Record<string, string>;
  };
  env: {
    hostRunner: Record<string, string>;
    dockerRunner: Record<string, string>;
    scenario: Record<string, string>;
  };
  serviceNames: Record<string, string>;
  health: Array<HealthProbeSpec & { role: string; serviceName: string; label: string }>;
  diagnostics: Array<DiagnosticProbeSpec & { role: string; serviceName: string }>;
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

export function parseRawTopologyPresetV1(value: unknown, pathLabel: string): RawTopologyPresetV1 {
  const result = rawTopologyPresetV1Schema.safeParse(value);
  if (result.success) return result.data;
  throw new Error(`Invalid topology preset ${pathLabel}:\n${formatZodError(result.error)}`);
}

export function normalizeTopologyPreset(raw: RawTopologyPresetV1): NormalizedTopologyPreset {
  const experimentalRoles = raw.experimentalRoles || {};
  validateRoleDeclarations(raw.roles, experimentalRoles, raw.name);

  const roles: Record<string, NormalizedServiceSpec | InheritedServiceSpec> = {};
  for (const [roleKey, value] of Object.entries(raw.roles)) {
    if ("inherit" in value) {
      roles[roleKey] = value;
      continue;
    }
    roles[roleKey] = normalizeService(roleKey, value);
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
    const dockerUrl = dockerUrlForService(role, service, preset.experimentalRoles);
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
      if (sidecar.source) sources.push(sourceInfo(role, sidecar, sidecarName, sidecarName));
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

function normalizeService(role: string, raw: RawServiceSpec): NormalizedServiceSpec {
  const container = raw.container || {};
  const merged = { ...container, ...raw, container: undefined } as RawServiceSpec;
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

export function normalizePorts(raw: string[] | PortSpec[] | undefined): PortSpec[] {
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

export function renderPortSpec(port: PortSpec): string {
  const base = port.host ? `${port.host}:${port.container}` : port.container;
  return port.protocol === "udp" ? `${base}/udp` : base;
}

export function normalizeVolumes(raw: string[] | VolumeSpec[] | undefined): VolumeSpec[] {
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
    return { type: "http", path: raw.path, headers: raw.headers, timeoutSeconds: 60 };
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

function validateCapabilities(role: string, capabilities: string[], presetName: string) {
  const errors = capabilities
    .map((capability) => validateRoleCapability(role, capability))
    .filter((message): message is string => Boolean(message));
  if (errors.length > 0) {
    throw new Error(
      `Invalid capabilities in topology preset "${presetName}":\n${formatList(errors)}`,
    );
  }
}

function hostUrlForService(
  role: string,
  service: NormalizedServiceSpec,
  experimentalRoles: Record<string, ExperimentalRoleMetadata>,
): string {
  const port = service.ports[0]?.host || defaultRolePort(role, experimentalRoles);
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
  item: { name?: string; source?: z.infer<typeof sourceBuildSchema>; serviceName?: string },
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
  return Object.keys(env).filter((key) => /(SECRET|TOKEN|PASSWORD|JWT|KEY)/i.test(key));
}

function formatList(items: string[]): string {
  return items.map((item) => `  - ${item}`).join("\n");
}

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

export const topologyManifestSchema = z.union([topologyManifestV1Schema, topologyManifestV2Schema]);

export type ParsedTopologyManifest = z.infer<typeof topologyManifestSchema>;

export function parseTopologyManifestJson(
  value: unknown,
  pathLabel: string,
): ParsedTopologyManifest {
  const result = topologyManifestSchema.safeParse(value);
  if (result.success) return result.data;
  throw new Error(`Invalid topology manifest ${pathLabel}:\n${formatZodError(result.error)}`);
}
