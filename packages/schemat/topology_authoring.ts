/** Strongly typed TypeScript authoring helpers for topology presets. @module topology_authoring */
import { Cap, Role } from "./topology_registry.ts";
import type { CapabilityForRole, RoleKey } from "./topology_registry.ts";
import {
  normalizePorts,
  normalizeVolumes,
  parseRawTopologyPresetV1,
} from "./topology_schema.ts";
import type {
  DiagnosticProbeSpec,
  InheritedServiceSpec,
  PortSpec,
  RawServiceSpec,
  RawSidecarSpec,
  RawTopologyPresetV1,
  ResourceHints,
  ScenarioRequirement,
  SourceBuildSpec,
  VolumeSpec,
} from "./topology_schema.ts";
import type { WebClientTopology } from "./topology_types.ts";

export { Cap, Role };
export type { CapabilityForRole, RoleKey };

/** Experimental capability syntax accepted by the runtime registry. */
export type ExperimentalCapability = `x-${string}:${string}`;
/** Capabilities accepted for a specific role in TypeScript topology authoring. */
export type CapabilityInput<R extends RoleKey> =
  | CapabilityForRole<R>
  | ExperimentalCapability;

/** Service image source for typed topology authoring. */
export interface ImageSource {
  /** Source discriminator. */
  kind: "image";
  /** Container image reference. */
  image: string;
}

/** Git source build for typed topology authoring. */
export interface GitSource {
  /** Source discriminator. */
  kind: "git";
  /** Git repository build source. */
  source: SourceBuildSpec;
}

/** Local Docker build source for typed topology authoring. */
export interface LocalBuildSource {
  /** Source discriminator. */
  kind: "localBuild";
  /** Build context path. */
  buildContext: string;
  /** Dockerfile name or path relative to the context. */
  dockerfile?: string;
}

/** Discriminated service source used by typed topology authoring. */
export type ServiceSource = ImageSource | GitSource | LocalBuildSource;

/** HTTP health probe authoring form. */
export interface HttpHealth {
  /** Health probe discriminator. */
  type: "http";
  /** Path checked inside the service. */
  path: string;
  /** Optional HTTP headers. */
  headers?: Record<string, string>;
}

/** Command health probe authoring form. */
export interface CommandHealth {
  /** Health probe discriminator. */
  type: "command";
  /** Docker healthcheck command. */
  customTest: readonly string[];
}

/** Explicitly disabled health probe authoring form. */
export interface NoHealth {
  /** Health probe discriminator. */
  type: "none";
}

/** Typed health probe input accepted by role builders. */
export type AuthoringHealth = HttpHealth | CommandHealth | NoHealth;

/** Existing health-check shape accepted by topology JSON presets. */
export interface LegacyHealthInput {
  /** HTTP path, or null for command/no health. */
  path: string | null;
  /** Optional Docker healthcheck command. */
  customTest?: readonly string[];
  /** Optional HTTP headers. */
  headers?: Record<string, string>;
}

/** Numeric or string port value. */
export type PortValue = string | number;
/** Authoring object form for a Docker port mapping. */
export interface PortMappingInput {
  /** Optional host port. Defaults to the container port when omitted by the helper. */
  host?: PortValue;
  /** Container port. */
  container: PortValue;
  /** Transport protocol. */
  protocol?: "tcp" | "udp";
}
/** Port input accepted by typed topology authoring. */
export type PortInput = string | number | PortMappingInput;
/** Volume input accepted by typed topology authoring. */
export type VolumeInput = string | VolumeSpec;

/** Diagnostic probe accepted by typed topology authoring. */
export type AuthoringDiagnosticProbe =
  | DiagnosticProbeSpec
  | {
    /** Probe name. */
    name?: string;
    /** Relative path appended to the service URL. */
    path?: string;
    /** Absolute probe URL. */
    url?: string;
    /** Optional HTTP headers. */
    headers?: Record<string, string>;
  };

/** Sidecar configuration accepted by typed topology authoring. */
export interface AuthoringSidecarSpec {
  /** Container image, git source, or local build source. */
  source: ServiceSource;
  /** Entrypoint command. */
  entrypoint?: readonly string[];
  /** Command arguments. */
  command?: readonly string[];
  /** Environment variables. */
  env?: Record<string, string>;
  /** Port mappings. */
  ports?: readonly PortInput[];
  /** Volume mappings. */
  volumes?: readonly VolumeInput[];
  /** Resource hints. */
  resources?: ResourceHints;
  /** Secret names. */
  secrets?: readonly string[];
  /** Typed health probe. */
  health?: AuthoringHealth;
  /** Existing topology health-check shape. */
  healthCheck?: LegacyHealthInput;
  /** Diagnostic probes. */
  diagnostics?: readonly AuthoringDiagnosticProbe[];
  /** Direct Docker Compose service dependencies. */
  dependsOn?: readonly string[];
  /** Topology role dependencies. */
  dependsOnRoles?: readonly RoleKey[];
  /** Config files materialized for the sidecar. */
  configFiles?: Record<string, string>;
  /** Capability flags advertised by the sidecar. */
  capabilities?: readonly string[];
}

/** Role service configuration accepted by typed topology authoring. */
export interface AuthoringServiceInput<R extends RoleKey> {
  /** Human-readable service label. */
  name: string;
  /** Compose service name override. */
  serviceName?: string;
  /** Container image, git source, or local build source. */
  source: ServiceSource;
  /** Entrypoint command. */
  entrypoint?: readonly string[];
  /** Command arguments. */
  command?: readonly string[];
  /** Environment variables. */
  env?: Record<string, string>;
  /** Port mappings. */
  ports?: readonly PortInput[];
  /** Volume mappings. */
  volumes?: readonly VolumeInput[];
  /** Resource hints. */
  resources?: ResourceHints;
  /** Secret names. */
  secrets?: readonly string[];
  /** Typed health probe. */
  health?: AuthoringHealth;
  /** Existing topology health-check shape. */
  healthCheck?: LegacyHealthInput;
  /** Diagnostic probes. */
  diagnostics?: readonly AuthoringDiagnosticProbe[];
  /** Direct Docker Compose service dependencies. */
  dependsOn?: readonly string[];
  /** Topology role dependencies resolved to service names during compilation. */
  dependsOnRoles?: readonly RoleKey[];
  /** Config files materialized for the container. */
  configFiles?: Record<string, string>;
  /** Capability flags restricted to this role. */
  capabilities: readonly CapabilityInput<R>[];
  /** Named sidecars started with the service. */
  sidecars?: Record<string, AuthoringSidecarSpec>;
  /** Scenario environment variables exported by the service. */
  scenarioEnv?: Record<string, string>;
}

/** Role service definition returned by role-specific builders. */
export interface AuthoringServiceSpec<R extends RoleKey>
  extends AuthoringServiceInput<R> {
  /** Built-in role for the service. */
  role: R;
}

/** Role map accepted by {@link defineTopology}. */
export type AuthoringRoleMap = {
  readonly [R in RoleKey]?:
    | AuthoringServiceSpec<R>
    | InheritedServiceSpec;
};

/** Topology definition accepted by {@link defineTopology}. */
export interface TopologyDefinition {
  /** Preset name. */
  name: string;
  /** Human-readable preset description. */
  description: string;
  /** Service definitions keyed by topology role. */
  roles: AuthoringRoleMap;
  /** Optional browser client payload preserved in the raw preset. */
  webClient?: WebClientTopology;
  /** Additional host aliases keyed by Compose service name. */
  networkAliases?: Record<string, string[]>;
}

function image(image: string): ImageSource {
  return { kind: "image", image };
}

function git(source: SourceBuildSpec): GitSource {
  return { kind: "git", source };
}

function localBuild(
  input: string | { buildContext: string; dockerfile?: string },
): LocalBuildSource {
  if (typeof input === "string") {
    return { kind: "localBuild", buildContext: input };
  }
  return { kind: "localBuild", ...input };
}

/** Discriminated source helpers for topology authoring. */
export const source = {
  image,
  git,
  localBuild,
} as const;

function httpHealth(
  path: string | { path: string; headers?: Record<string, string> },
): HttpHealth {
  if (typeof path === "string") return { type: "http", path };
  return { type: "http", ...path };
}

function commandHealth(customTest: readonly string[]): CommandHealth {
  return { type: "command", customTest };
}

function noHealth(): NoHealth {
  return { type: "none" };
}

/** Health probe helpers for topology authoring. */
export const health = {
  http: httpHealth,
  command: commandHealth,
  none: noHealth,
} as const;

/** Create a normalized Docker port mapping for topology authoring. */
export function port(input: PortInput): PortSpec {
  if (typeof input === "number") {
    const value = String(input);
    return { host: value, container: value, protocol: "tcp" };
  }
  if (typeof input === "string") return normalizePorts([input])[0];
  return {
    host: input.host === undefined ? undefined : String(input.host),
    container: String(input.container),
    protocol: input.protocol || "tcp",
  };
}

function namedVolume(
  source: string,
  target: string,
  mode?: string,
): VolumeSpec {
  return mode === undefined
    ? { kind: "named", source, target }
    : { kind: "named", source, target, mode };
}

function bindVolume(source: string, target: string, mode?: string): VolumeSpec {
  return mode === undefined
    ? { kind: "bind", source, target }
    : { kind: "bind", source, target, mode };
}

/** Volume helpers for topology authoring. */
export const volume = {
  named: namedVolume,
  bind: bindVolume,
} as const;

function inherit(presetName: string): InheritedServiceSpec {
  return { inherit: presetName };
}

function service<R extends RoleKey>(
  roleKey: R,
  input: AuthoringServiceInput<R>,
): AuthoringServiceSpec<R> {
  return { ...input, role: roleKey };
}

function plc(
  input: AuthoringServiceInput<typeof Role.plc>,
): AuthoringServiceSpec<"plc"> {
  return service(Role.plc, input);
}

function pds(
  input: AuthoringServiceInput<typeof Role.pds>,
): AuthoringServiceSpec<"pds"> {
  return service(Role.pds, input);
}

function pds2(
  input: AuthoringServiceInput<typeof Role.pds2>,
): AuthoringServiceSpec<"pds2"> {
  return service(Role.pds2, input);
}

function relay(
  input: AuthoringServiceInput<typeof Role.relay>,
): AuthoringServiceSpec<"relay"> {
  return service(Role.relay, input);
}

function appview(
  input: AuthoringServiceInput<typeof Role.appview>,
): AuthoringServiceSpec<"appview"> {
  return service(Role.appview, input);
}

function mikrus(
  input: AuthoringServiceInput<typeof Role.mikrus>,
): AuthoringServiceSpec<"mikrus"> {
  return service(Role.mikrus, input);
}

function chat(
  input: AuthoringServiceInput<typeof Role.chat>,
): AuthoringServiceSpec<"chat"> {
  return service(Role.chat, input);
}

function video(
  input: AuthoringServiceInput<typeof Role.video>,
): AuthoringServiceSpec<"video"> {
  return service(Role.video, input);
}

function ui(
  input: AuthoringServiceInput<typeof Role.ui>,
): AuthoringServiceSpec<"ui"> {
  return service(Role.ui, input);
}

function backfill(
  input: AuthoringServiceInput<typeof Role.backfill>,
): AuthoringServiceSpec<"backfill"> {
  return service(Role.backfill, input);
}

/** Role-specific topology service builders. */
export const role = {
  inherit,
  plc,
  pds,
  pds2,
  relay,
  appview,
  mikrus,
  chat,
  video,
  ui,
  backfill,
} as const;

/** Create a role-scoped required scenario capability. */
export function requires<R extends RoleKey>(
  role: R,
  capability: CapabilityInput<R>,
): ScenarioRequirement {
  return { role, capability };
}

/** Create a role-scoped optional scenario capability. */
export function optional<R extends RoleKey>(
  role: R,
  capability: CapabilityInput<R>,
): ScenarioRequirement {
  return { role, capability };
}

/** Validate and normalize a typed topology definition into the raw preset shape. */
export function defineTopology<const Definition extends TopologyDefinition>(
  definition: Definition,
): RawTopologyPresetV1 {
  const roles: RawTopologyPresetV1["roles"] = {};
  for (const [roleKey, value] of Object.entries(definition.roles)) {
    if (value === undefined) continue;
    roles[roleKey] = "inherit" in value ? value : serviceToRaw(roleKey, value);
  }

  return parseRawTopologyPresetV1({
    name: definition.name,
    description: definition.description,
    roles,
    webClient: definition.webClient,
    networkAliases: definition.networkAliases,
  }, `defineTopology:${definition.name}`);
}

function serviceToRaw<R extends RoleKey>(
  roleKey: string,
  input: AuthoringServiceSpec<R>,
): RawServiceSpec {
  return {
    role: input.role || roleKey,
    name: input.name,
    serviceName: input.serviceName,
    ...sourceToRaw(input.source),
    entrypoint: copyArray(input.entrypoint),
    command: copyArray(input.command),
    env: input.env,
    ports: normalizePortInputs(input.ports),
    volumes: normalizeVolumeInputs(input.volumes),
    resources: input.resources,
    secrets: copyArray(input.secrets),
    healthCheck: normalizeHealthInput(input.health || input.healthCheck),
    diagnostics: copyDiagnostics(input.diagnostics),
    dependsOn: copyArray(input.dependsOn),
    dependsOnRoles: copyArray(input.dependsOnRoles),
    configFiles: input.configFiles,
    capabilities: [...input.capabilities],
    sidecars: sidecarsToRaw(input.sidecars),
    scenarioEnv: input.scenarioEnv,
  };
}

function sidecarsToRaw(
  sidecars: Record<string, AuthoringSidecarSpec> | undefined,
): Record<string, RawSidecarSpec> | undefined {
  if (!sidecars) return undefined;
  return Object.fromEntries(
    Object.entries(sidecars).map((
      [name, sidecar],
    ) => [name, sidecarToRaw(sidecar)]),
  );
}

function sidecarToRaw(input: AuthoringSidecarSpec): RawSidecarSpec {
  return {
    ...sourceToRaw(input.source),
    entrypoint: copyArray(input.entrypoint),
    command: copyArray(input.command),
    env: input.env,
    ports: normalizePortInputs(input.ports),
    volumes: normalizeVolumeInputs(input.volumes),
    resources: input.resources,
    secrets: copyArray(input.secrets),
    healthCheck: normalizeHealthInput(input.health || input.healthCheck),
    diagnostics: copyDiagnostics(input.diagnostics),
    dependsOn: copyArray(input.dependsOn),
    dependsOnRoles: copyArray(input.dependsOnRoles),
    configFiles: input.configFiles,
    capabilities: copyArray(input.capabilities),
  };
}

function sourceToRaw(
  input: ServiceSource,
): Pick<RawServiceSpec, "image" | "source" | "buildContext" | "dockerfile"> {
  if (input.kind === "image") return { image: input.image };
  if (input.kind === "git") return { source: input.source };
  return { buildContext: input.buildContext, dockerfile: input.dockerfile };
}

function normalizeHealthInput(
  input: AuthoringHealth | LegacyHealthInput | undefined,
): RawServiceSpec["healthCheck"] {
  if (!input) return undefined;
  if ("type" in input) {
    if (input.type === "none") return { path: null };
    if (input.type === "command") {
      return { path: null, customTest: [...input.customTest] };
    }
    return { path: input.path, headers: input.headers };
  }
  return {
    path: input.path,
    customTest: copyArray(input.customTest),
    headers: input.headers,
  };
}

function normalizePortInputs(
  inputs: readonly PortInput[] | undefined,
): PortSpec[] | undefined {
  return inputs?.map(port);
}

function normalizeVolumeInputs(
  inputs: readonly VolumeInput[] | undefined,
): VolumeSpec[] | undefined {
  return inputs?.map((input) =>
    typeof input === "string" ? normalizeVolumes([input])[0] : input
  );
}

function copyArray<T>(input: readonly T[] | undefined): T[] | undefined {
  return input === undefined ? undefined : [...input];
}

function copyDiagnostics(
  input: readonly AuthoringDiagnosticProbe[] | undefined,
): RawServiceSpec["diagnostics"] {
  return input === undefined
    ? undefined
    : [...input] as RawServiceSpec["diagnostics"];
}
