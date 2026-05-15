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
};

export interface InheritedAdapter {
  inherit: string;
}

export interface SourceBuild {
  repo: string;
  ref: string;
  dockerDir?: string;
  dockerfile?: string;
  buildArgs?: Record<string, string>;
  dockerfileOverlay?: string;
  overlayDir?: string;
}

export interface SidecarAdapter {
  image?: string;
  source?: SourceBuild;
  command?: string[];
  env?: Record<string, string>;
  ports?: string[];
  volumes?: string[];
  configFiles?: Record<string, string>;
  healthCheck?: {
    path: string | null;
    customTest?: string[];
    headers?: Record<string, string>;
  };
  dependsOn?: string[];
  diagnostics?: DiagnosticProbeConfig[];
}

export interface ServiceAdapter {
  role?: ServiceRole;
  name: string;
  serviceName?: string;
  container?: Partial<ServiceAdapter>;
  image?: string;
  source?: SourceBuild;
  buildContext?: string;
  dockerfile?: string;
  entrypoint?: string[];
  command?: string[];
  env?: Record<string, string>;
  ports?: string[];
  volumes?: string[];
  healthCheck: {
    path: string | null;
    customTest?: string[];
    headers?: Record<string, string>;
  };
  capabilities: string[];
  dependsOn?: string[];
  sidecars?: Record<string, SidecarAdapter>;
  diagnostics?: DiagnosticProbeConfig[];
  scenarioEnv?: Record<string, string>;
}

export interface TopologyPreset {
  name: string;
  description: string;
  roles: Partial<Record<ServiceRole, ServiceAdapter | InheritedAdapter>>;
  webClient?: WebClientTopology;
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
  capabilities: Set<string>;
  capabilitiesByRole: Record<string, Set<string>>;
  manifest?: TopologyManifest;
  resolved?: ResolvedTopology;
}

export interface SourceBuildInfo {
  name: string;
  repo: string;
  ref: string;
  dockerDir: string;
  dockerfile: string;
  buildArgs: Record<string, string>;
  dockerfileOverlay: string;
  overlayDir: string;
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
