/** Strongly typed TypeScript authoring helpers for topology presets. @module topology_authoring */
import { Cap, Role } from "./topology_registry.ts";
import type { CapabilityForRole, RoleKey } from "./topology_registry.ts";
import {
  normalizeTopologyPreset,
  parseTopologyPresetJson,
} from "./topology_schema.ts";
import type {
  DiagnosticProbeSpec,
  InheritedServiceSpec,
  NormalizedTopologyPreset,
  PortSpec,
  ResourceHints,
  SourceBuildSpec,
  TopologyServiceJson,
  TopologySidecarJson,
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

/** Canonical topology type stored in the registry. */
export type RegisteredTopologyPreset = NormalizedTopologyPreset;

export type { InheritedServiceSpec, NormalizedTopologyPreset };

/** Role-scoped scenario requirement emitted by the typed authoring helpers. */
export interface ScenarioRequirement<R extends RoleKey = RoleKey> {
  /** Service role that must provide the capability. */
  role: R;
  /** Capability required by the scenario. */
  capability: CapabilityInput<R>;
}

/** Unique symbol branding a direct Docker Compose service reference. */
export declare const serviceRefBrand: unique symbol;

/** Branded direct Docker Compose service reference for sidecars/support services. */
export type ServiceRef = string & { readonly [serviceRefBrand]: true };

/** Create a branded direct Docker Compose service dependency reference. */
export function serviceRef(name: string): ServiceRef {
  return name as ServiceRef;
}

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

/** Numeric port value accepted by the `port(...)` helper. */
export type PortValue = number;
/** Authoring object form for a Docker port mapping. */
export interface PortMappingInput {
  /** Optional host port. Defaults to the container port when omitted by the helper. */
  host?: PortValue;
  /** Container port. */
  container: PortValue;
  /** Transport protocol. */
  protocol?: "tcp" | "udp";
}
/** Port input accepted by the `port(...)` helper. */
export type PortInput = number | PortMappingInput;

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
  ports?: readonly PortSpec[];
  /** Volume mappings. */
  volumes?: readonly VolumeSpec[];
  /** Resource hints. */
  resources?: ResourceHints;
  /** Secret names. */
  secrets?: readonly string[];
  /** Typed health probe. */
  health?: AuthoringHealth;
  /** Diagnostic probes. */
  diagnostics?: readonly AuthoringDiagnosticProbe[];
  /** Direct Docker Compose service dependencies. */
  dependsOn?: readonly ServiceRef[];
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
  ports?: readonly PortSpec[];
  /** Volume mappings. */
  volumes?: readonly VolumeSpec[];
  /** Resource hints. */
  resources?: ResourceHints;
  /** Secret names. */
  secrets?: readonly string[];
  /** Typed health probe. */
  health?: AuthoringHealth;
  /** Diagnostic probes. */
  diagnostics?: readonly AuthoringDiagnosticProbe[];
  /** Direct Docker Compose service dependencies. */
  dependsOn?: readonly ServiceRef[];
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

function pds3(
  input: AuthoringServiceInput<typeof Role.pds3>,
): AuthoringServiceSpec<"pds3"> {
  return service(Role.pds3, input);
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

function beskid(
  input: AuthoringServiceInput<typeof Role.beskid>,
): AuthoringServiceSpec<"beskid"> {
  return service(Role.beskid, input);
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
  pds3,
  relay,
  appview,
  mikrus,
  beskid,
  chat,
  video,
  ui,
  backfill,
} as const;

/** Create a role-scoped required scenario capability. */
export function requires<R extends RoleKey>(
  role: R,
  capability: CapabilityInput<R>,
): ScenarioRequirement<R> {
  return { role, capability };
}

/** Create a role-scoped optional scenario capability. */
export function optional<R extends RoleKey>(
  role: R,
  capability: CapabilityInput<R>,
): ScenarioRequirement<R> {
  return { role, capability };
}

/** Validate and normalize a typed topology definition into the raw preset shape. */
export function defineTopology<const Definition extends TopologyDefinition>(
  definition: Definition,
): RegisteredTopologyPreset {
  const roles: Record<string, TopologyServiceJson | InheritedServiceSpec> = {};
  for (const [roleKey, value] of Object.entries(definition.roles)) {
    if (value === undefined) continue;
    roles[roleKey] = "inherit" in value ? value : serviceToRaw(roleKey, value);
  }

  const raw = parseTopologyPresetJson({
    name: definition.name,
    description: definition.description,
    roles,
    webClient: definition.webClient,
    networkAliases: definition.networkAliases,
  }, `defineTopology:${definition.name}`);
  return normalizeTopologyPreset(raw);
}

function serviceToRaw<R extends RoleKey>(
  roleKey: string,
  input: AuthoringServiceSpec<R>,
): TopologyServiceJson {
  return {
    role: input.role || roleKey,
    name: input.name,
    serviceName: input.serviceName,
    ...sourceToRaw(input.source),
    entrypoint: copyArray(input.entrypoint),
    command: copyArray(input.command),
    env: input.env,
    ports: copyArray(input.ports),
    volumes: copyArray(input.volumes),
    resources: input.resources,
    secrets: copyArray(input.secrets),
    health: normalizeHealthInput(input.health),
    diagnostics: copyDiagnostics(input.diagnostics),
    dependsOn: copyServiceRefs(input.dependsOn),
    dependsOnRoles: copyArray(input.dependsOnRoles),
    configFiles: input.configFiles,
    capabilities: [...input.capabilities],
    sidecars: sidecarsToRaw(input.sidecars),
    scenarioEnv: input.scenarioEnv,
  };
}

function sidecarsToRaw(
  sidecars: Record<string, AuthoringSidecarSpec> | undefined,
): Record<string, TopologySidecarJson> | undefined {
  if (!sidecars) return undefined;
  return Object.fromEntries(
    Object.entries(sidecars).map((
      [name, sidecar],
    ) => [name, sidecarToRaw(sidecar)]),
  );
}

function sidecarToRaw(input: AuthoringSidecarSpec): TopologySidecarJson {
  return {
    ...sourceToRaw(input.source),
    entrypoint: copyArray(input.entrypoint),
    command: copyArray(input.command),
    env: input.env,
    ports: copyArray(input.ports),
    volumes: copyArray(input.volumes),
    resources: input.resources,
    secrets: copyArray(input.secrets),
    health: normalizeHealthInput(input.health),
    diagnostics: copyDiagnostics(input.diagnostics),
    dependsOn: copyServiceRefs(input.dependsOn),
    dependsOnRoles: copyArray(input.dependsOnRoles),
    configFiles: input.configFiles,
    capabilities: copyArray(input.capabilities),
  };
}

function sourceToRaw(
  input: ServiceSource,
): Pick<
  TopologyServiceJson,
  "image" | "source" | "buildContext" | "dockerfile"
> {
  if (input.kind === "image") return { image: input.image };
  if (input.kind === "git") return { source: input.source };
  return { buildContext: input.buildContext, dockerfile: input.dockerfile };
}

function normalizeHealthInput(
  input: AuthoringHealth | undefined,
): TopologyServiceJson["health"] {
  if (!input) return undefined;
  if (input.type === "none") return { path: null };
  if (input.type === "command") {
    return { path: null, customTest: [...input.customTest] };
  }
  return { path: input.path, headers: input.headers };
}

function copyArray<T>(input: readonly T[] | undefined): T[] | undefined {
  return input === undefined ? undefined : [...input];
}

function copyServiceRefs(
  input: readonly ServiceRef[] | undefined,
): string[] | undefined {
  return input === undefined ? undefined : [...input];
}

function copyDiagnostics(
  input: readonly AuthoringDiagnosticProbe[] | undefined,
): TopologyServiceJson["diagnostics"] {
  return input === undefined
    ? undefined
    : [...input] as TopologyServiceJson["diagnostics"];
}
