/**
 * Pure topology schemas, presets, registry, manifests, and compose compilation.
 *
 * Runtime helpers that touch the filesystem, process environment, or git live
 * under `@garazyk/schemat/runtime`.
 *
 * @module schemat
 */

export {
  loadTopologyPreset,
  resolvePreset,
  resolveTopology,
  TopologyRegistry,
} from "./topology.ts";
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
export {
  compileTopology,
  renderComposeYaml,
  validatePreset,
} from "./topology_compiler.ts";
export {
  CAPABILITY_REGISTRY,
  DEFAULT_PORTS,
  DEFAULT_SERVICE_NAMES,
  defaultRolePort,
  defaultServiceName,
  isExperimentalCapability,
  isExperimentalRole,
  isKnownServiceRole,
  KNOWN_SERVICE_ROLES,
  ROLE_ENV_REGISTRY,
  roleEnvKey,
  validateRoleCapability,
} from "./topology_registry.ts";
export { listTopologyPresets } from "./topology_list.ts";
export {
  ROLE_TO_ENV,
  ROLE_TO_PORT,
  ROLE_TO_SERVICE,
} from "./topology_types.ts";

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
  TopologyPreset,
  TopologyResolveOptions,
  VolumeSpec,
  WebClientTopology,
} from "./topology.ts";
export type {
  ResolvedTopologyService,
  ResourceHints,
  SourceBuildSpec,
} from "./topology_schema.ts";
export type { CompilerOptions, CompilerResult } from "./topology_compiler.ts";
export type {
  ExperimentalRoleMetadata,
  KnownServiceRole,
  ServiceRoleKey,
} from "./topology_registry.ts";
export type { TopologyPresetSummary } from "./topology_list.ts";

export {
  main as renderWebClientComposeMain,
  prepareSourceBuildContext,
  renderWebClientCompose,
  writeSourceDockerfile,
} from "./web_client_compose.ts";
export type { WebClientComposeOptions } from "./web_client_compose.ts";
