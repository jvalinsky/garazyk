/**
 * Shared types for ATProto network topologies.
 *
 * @module topology_types
 */

import {
  DEFAULT_PORTS,
  DEFAULT_SERVICE_NAMES,
  KnownServiceRole,
  ROLE_ENV_REGISTRY,
  roleEnvKey,
} from "./topology_registry.ts";
import type {
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

/** Browser test flow depth: none, smoke, login, or deep */
export type BrowserFlow = "none" | "smoke" | "login" | "deep";
/** Alias for known ATProto service roles */
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
};

/** Inherited adapter reference used to reuse another role definition */
export interface InheritedAdapter {
  /** Role name to inherit from */
  inherit: string;
}

/** Git source used to build a Docker image from source
 *
 * @remarks
 * `repo` and `ref` are required; `dockerDir` and `dockerfile` fall back to the usual Docker defaults
 */
export interface SourceBuild {
  /** Repository URL, for example `"https://github.com/bluesky-social/atproto"` */
  repo: string;
  /** Git ref such as a branch, tag, or SHA */
  ref: string;
  /** Subdirectory containing the Dockerfile
   *
   * @defaultValue "."
   */
  dockerDir?: string;
  /** Dockerfile name
   *
   * @defaultValue "Dockerfile"
   */
  dockerfile?: string;
  /** Build arguments passed as `--build-arg` */
  buildArgs?: Record<string, string>;
  /** Dockerfile fragment appended before the build */
  dockerfileOverlay?: string;
  /** Directory copied into the build context for overlay files */
  overlayDir?: string;
}

/** Sidecar container configuration attached to a service adapter
 *
 * @remarks
 * Sidecars are resolved alongside their parent service and may use either an image or a source build
 */
export interface SidecarAdapter {
  /** Container image to run */
  image?: string;
  /** Source build used when the sidecar is built locally */
  source?: SourceBuild;
  /** Entrypoint or command arguments for the sidecar */
  command?: string[];
  /** Environment variables injected into the sidecar */
  env?: Record<string, string>;
  /** Port mappings exposed by the sidecar */
  ports?: string[];
  /** Volume mappings mounted into the sidecar */
  volumes?: string[];
  /** Config files materialized for the sidecar */
  configFiles?: Record<string, string>;
  /** Health check definition used to monitor the sidecar */
  healthCheck?: {
    path: string | null;
    customTest?: string[];
    headers?: Record<string, string>;
  };
  /** Upstream dependencies referenced by name */
  dependsOn?: string[];
  /** Additional probes collected for diagnostics */
  diagnostics?: DiagnosticProbeConfig[];
}

/** Primary service definition for a topology role
 *
 * @remarks
 * `name`, `healthCheck`, and `capabilities` define the runtime contract; `serviceName` defaults to the registry name when omitted
 */
export interface ServiceAdapter {
  /** Known service role, or an experimental role key */
  role?: ServiceRole;
  /** Human-readable service label */
  name: string;
  /** Compose service name used by Docker and manifests */
  serviceName?: string;
  /** Container-specific overrides merged before resolution */
  container?: Partial<ServiceAdapter>;
  /** Container image to run */
  image?: string;
  /** Source build used when the service is built locally */
  source?: SourceBuild;
  /** Build context path for locally built images */
  buildContext?: string;
  /** Dockerfile name for locally built images */
  dockerfile?: string;
  /** Entrypoint command passed to the container */
  entrypoint?: string[];
  /** Command arguments passed to the container */
  command?: string[];
  /** Environment variables injected into the container */
  env?: Record<string, string>;
  /** Port mappings exposed by the service */
  ports?: string[];
  /** Volume mappings mounted into the service */
  volumes?: string[];
  /** Primary health check used by the runner */
  healthCheck: {
    path: string | null;
    customTest?: string[];
    headers?: Record<string, string>;
  };
  /** Capability flags advertised by this service */
  capabilities: string[];
  /** Upstream dependencies referenced by role or service name */
  dependsOn?: string[];
  /** Named sidecars started with the service */
  sidecars?: Record<string, SidecarAdapter>;
  /** Additional probes collected for diagnostics */
  diagnostics?: DiagnosticProbeConfig[];
  /** Scenario environment variables exported from the service */
  scenarioEnv?: Record<string, string>;
}

/** Authoritative topology preset before resolution
 *
 * @remarks
 * Role entries may be concrete adapters or inheritance markers; experimental roles must also be declared in the preset metadata
 */
export interface TopologyPreset {
  /** Preset name used in CLI flags and manifests */
  name: string;
  /** Human-readable description of the preset */
  description: string;
  /** Service definitions keyed by role */
  roles: Partial<Record<ServiceRole, ServiceAdapter | InheritedAdapter>>;
  /** Optional browser client attached to the preset */
  webClient?: WebClientTopology;
  /** Additional host aliases keyed by service name */
  networkAliases?: Record<string, string[]>;
}

/** Diagnostic probe configuration for lightweight HTTP checks */
export interface DiagnosticProbeConfig {
  /** Probe name used in logs and reports */
  name?: string;
  /** Relative path checked by the probe */
  path?: string;
  /** Absolute URL checked by the probe */
  url?: string;
  /** HTTP headers sent with the request */
  headers?: Record<string, string>;
}

/** Browser client definition attached to a topology
 *
 * @remarks
 * `browserFlow` keys must match the runner flow names; `allowHybridNetwork` opts into mixed host and container access
 */
export interface WebClientTopology {
  /** Browser client name used in manifests and reports */
  name: string;
  /** Source repository for the browser client */
  source: string;
  /** Git ref used to build the browser client */
  ref: string;
  /** Build preset name used by the web client pipeline */
  buildPreset: "garazyk-ui" | "social-app" | "witchsky";
  /** Command used to serve the browser client */
  serveCommand: string[];
  /** Public URL exposed to browsers */
  publicUrl: string;
  /** Internal URL exposed inside the container network */
  internalUrl: string;
  /** Environment variables injected into the browser client */
  env: Record<string, string>;
  /** Health check settings for the browser client */
  healthCheck: {
    url: string;
    intervalSeconds: number;
    timeoutSeconds: number;
    retries: number;
    startPeriodSeconds: number;
  };
  /** OAuth redirect URLs allowed for the client */
  oauthRedirects: string[];
  /** Capability flags advertised by the browser client */
  capabilities: string[];
  /** Browser flows used by scenario runners */
  browserFlow: {
    smoke: string;
    login: string;
    deep: string;
  };
  /** Enable mixed host and container networking */
  allowHybridNetwork?: boolean;
}

/** Resolved topology view consumed by runners, dashboards, and reports
 *
 * @remarks
 * Map keys are role names unless otherwise noted; `manifest` and `resolved` describe the same topology snapshot at different stages
 */
export interface Topology {
  /** Preset used to produce this topology */
  preset?: TopologyPreset;
  /** Browser client attached to the resolved topology */
  webClient?: WebClientTopology;
  /** Public service URLs keyed by role */
  serviceUrls: Record<string, string>;
  /** Internal service URLs keyed by role */
  internalUrls: Record<string, string>;
  /** Compose service names keyed by role */
  serviceNames: Record<string, string>;
  /** All capabilities available in the topology */
  capabilities: Set<string>;
  /** Capabilities grouped by role */
  capabilitiesByRole: Record<string, Set<string>>;
  /** Serialized manifest when the topology has been written to disk */
  manifest?: TopologyManifest;
  /** Fully resolved topology snapshot */
  resolved?: ResolvedTopology;
}

/** Normalized source build metadata captured in a manifest
 *
 * @remarks
 * All paths and build arguments are fully resolved and safe to serialize
 */
export interface SourceBuildInfo {
  /** Service or sidecar name that owns the source build */
  name: string;
  /** Repository URL used for the build */
  repo: string;
  /** Git ref used for the build */
  ref: string;
  /** Dockerfile directory after normalization */
  dockerDir: string;
  /** Dockerfile name after normalization */
  dockerfile: string;
  /** Build arguments applied at image build time */
  buildArgs: Record<string, string>;
  /** Dockerfile overlay content after normalization */
  dockerfileOverlay: string;
  /** Overlay directory after normalization */
  overlayDir: string;
  /** Local clone directory used for the build */
  cloneDir: string;
}

/** Health probe entry recorded in a topology manifest
 *
 * @remarks
 * `mode` determines whether `url` or `path` is meaningful; `serviceName` is the compose service target
 */
export interface TopologyHealthProbe {
  /** Role the probe belongs to */
  role: string;
  /** Compose service name being checked */
  serviceName: string;
  /** Label used in dashboards and logs */
  label: string;
  /** Probe execution mode */
  mode: "http" | "docker-health";
  /** Absolute URL checked by HTTP mode */
  url?: string;
  /** Relative path checked by HTTP mode */
  path?: string | null;
  /** HTTP headers sent with the request */
  headers?: Record<string, string>;
  /** Maximum wait time in seconds
   *
   * @defaultValue 60
   */
  timeoutSeconds: number;
}

/** Diagnostic probe entry recorded in a topology manifest
 *
 * @remarks
 * Diagnostic probes always include the resolved role and compose service name
 */
export interface TopologyDiagnosticProbe {
  /** Probe name shown in reports */
  name: string;
  /** Role the probe belongs to */
  role: string;
  /** Compose service name targeted by the probe */
  serviceName: string;
  /** Absolute URL requested by the probe */
  url: string;
  /** HTTP headers sent with the request */
  headers?: Record<string, string>;
}

/** Versioned topology manifest serialized to disk
 *
 * @remarks
 * Version 1 and 2 share the same core shape; version 2 adds nested URL, env, capability, resource, and service summaries
 */
export interface TopologyManifest {
  /** Manifest format version */
  version: 1 | 2;
  /** Topology name */
  name: string;
  /** Topology description */
  description: string;
  /** Run directory used when the manifest was generated */
  runDir: string;
  /** Repository root used for resolution */
  repoRoot: string;
  /** Compose file used to launch the topology */
  composeFile: string;
  /** Docker network name for the run */
  networkName: string;
  /** Public service URLs keyed by role */
  serviceUrls: Record<string, string>;
  /** Internal service URLs keyed by role */
  internalUrls: Record<string, string>;
  /** Compose service names keyed by role */
  serviceNames: Record<string, string>;
  /** Capabilities available in the topology */
  capabilities: string[];
  /** Capabilities grouped by role */
  capabilitiesByRole: Record<string, string[]>;
  /** Scenario environment variables exported by the topology */
  scenarioEnv: Record<string, string>;
  /** Health probes captured for the topology */
  health: TopologyHealthProbe[];
  /** Diagnostic probes captured for the topology */
  diagnostics: TopologyDiagnosticProbe[];
  /** Source build metadata captured for the topology */
  sources: SourceBuildInfo[];
  /** Version 2 host and docker URL maps keyed by role */
  urls?: {
    host: Record<string, string>;
    docker: Record<string, string>;
  };
  /** Version 2 runner and scenario environment maps */
  env?: {
    hostRunner: Record<string, string>;
    dockerRunner: Record<string, string>;
    scenario: Record<string, string>;
  };
  /** Version 2 capability summary keyed by role */
  capabilitiesV2?: {
    all: string[];
    byRole: Record<string, string[]>;
  };
  /** Version 2 resource hints keyed by role */
  resources?: Record<string, {
    cpu?: string;
    memory?: string;
    localDisk?: string;
  }>;
  /** Version 2 service summary keyed by role */
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

/** Options for resolving a topology preset from disk
 *
 * @remarks
 * Paths are optional and fall back to repository conventions; `includePds2` expands the role set when requested
 */
export interface TopologyResolveOptions {
  /** Repository root used to resolve relative paths */
  repoRoot?: string;
  /** Directory containing topology preset JSON files */
  presetDir?: string;
  /** Run directory used for derived outputs */
  runDir?: string;
  /** Compose file path to load */
  composeFile?: string;
  /** Manifest path to load instead of resolving from presets */
  manifestPath?: string;
  /** Include the PDS2 role set when resolving */
  includePds2?: boolean;
}

/** Default compose service name for each known role */
export const ROLE_TO_SERVICE: Record<ServiceRole, string> = DEFAULT_SERVICE_NAMES;
/** Default host port for each known role */
export const ROLE_TO_PORT: Record<ServiceRole, string> = DEFAULT_PORTS;
/** Default environment variable name for each known role */
export const ROLE_TO_ENV: Record<string, string> = ROLE_ENV_REGISTRY;
