/**
 * Topology models, registry resolution, manifests, and compose compilation.
 *
 * Runtime helpers that touch the filesystem, process environment, or git live
 * under `@garazyk/schemat/runtime`.
 *
 * @module schemat
 */

// Topology model and schema
export * from "./logging.ts";
export {
  DEFAULT_ADMIN_PASSWORD,
  DEFAULT_MOCK_TWILIO_PORT,
} from "./topology_presets.ts";
export {
  loadTopologyPreset,
  resolvePreset,
  resolveTopology,
  TopologyRegistry,
} from "./topology.ts";

// Compose and manifest I/O
export {
  createTopologyManifest,
  defaultPortForRole,
  dependencyInfoForService,
  internalUrlForRole,
  loadTopologyManifest,
  parsePortMapping,
  publicUrlForRole,
  publicUrlForRoleWithHostPort,
  roleToEnvKey,
  sanitizeTopologyName,
  serviceNameForRole,
  writeTopologyManifest,
} from "./topology_manifest.ts";
export {
  compileTopology,
  renderComposeYaml,
  validatePreset,
} from "./topology_compiler.ts";
export {
  applyRunResourceEnvironment,
  applyRunResourceManifestPath,
  createRunResourceManifest,
  loadRunResourceManifest,
  mockProviderUrlsFromResourceManifest,
  resourceManifestPathForRunDir,
  serviceUrlsFromResourceManifest,
  updateRunResourceManifest,
  writeRunResourceManifest,
} from "./resource_manifest.ts";
export {
  allocateHostPort,
  allocateHostPorts,
  cleanupStalePortLeases,
  defaultPortLeaseDir,
  hostUrlForPort,
  parsePortRange,
  releaseRunPortLeases,
} from "./port_allocator.ts";

// Registry and resolution
export {
  Cap,
  CAPABILITY_REGISTRY,
  DEFAULT_PORTS,
  DEFAULT_SERVICE_NAMES,
  defaultRolePort,
  defaultServiceName,
  isExperimentalCapability,
  isExperimentalRole,
  isKnownServiceRole,
  KNOWN_SERVICE_ROLES,
  Role,
  ROLE_ENV_REGISTRY,
  roleEnvKey,
  validateRoleCapability,
} from "./topology_registry.ts";
export {
  defineTopology,
  health,
  optional,
  port,
  requires,
  role,
  serviceRef,
  source,
  volume,
} from "./topology_authoring.ts";
export { listTopologyPresets } from "./topology_list.ts";

export {
  ROLE_TO_ENV,
  ROLE_TO_PORT,
  ROLE_TO_SERVICE,
} from "./topology_types.ts";

// Types
export type {
  BrowserFlow,
  ContainerSpec,
  DiagnosticProbeConfig,
  DiagnosticProbeSpec,
  HealthProbeSpec,
  InheritedAdapter,
  NormalizedServiceSpec,
  PortSpec,
  ResolvedTopology,
  ServiceAdapter,
  ServiceRole,
  SidecarAdapter,
  SidecarSpec,
  SourceBuild,
  SourceBuildInfo,
  Topology,
  TopologyDiagnosticProbe,
  TopologyHealthProbe,
  TopologyManifest,
  TopologyManifestV1,
  TopologyManifestV2,
  TopologyPreset,
  TopologyResolveOptions,
  VolumeSpec,
  WebClientTopology,
} from "./topology.ts";
export type {
  InheritedServiceSpec,
  NormalizedTopologyPreset,
  ResolvedTopologyService,
  ResourceHints,
  SourceBuildSpec,
} from "./topology_schema.ts";
export type {
  CompilerOptions,
  CompilerResult,
  OtelOptions,
} from "./topology_compiler.ts";
export type {
  ResourceIsolationMode,
  RunPortLease,
  RunResourceCleanupState,
  RunResourceEndpoint,
  RunResourceManifest,
} from "./resource_manifest.ts";
export type {
  HostPortAllocationOptions,
  HostPortLease,
  PortRange,
} from "./port_allocator.ts";
export type {
  AnyCapability,
  CapabilityForRole,
  ExperimentalRoleMetadata,
  KnownServiceRole,
  RoleCapabilityMap,
  RoleKey,
  ServiceRoleKey,
} from "./topology_registry.ts";
export type {
  AuthoringDiagnosticProbe,
  AuthoringHealth,
  AuthoringRoleMap,
  AuthoringServiceInput,
  AuthoringServiceSpec,
  AuthoringSidecarSpec,
  CapabilityInput,
  CommandHealth,
  ExperimentalCapability,
  GitSource,
  HttpHealth,
  ImageSource,
  LocalBuildSource,
  NoHealth,
  PortInput,
  PortMappingInput,
  PortValue,
  RegisteredTopologyPreset,
  ScenarioRequirement,
  ServiceRef,
  serviceRefBrand,
  ServiceSource,
  TopologyDefinition,
} from "./topology_authoring.ts";
export type { TopologyPresetSummary } from "./topology_list.ts";
