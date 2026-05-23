/**
 * Runtime and filesystem helpers for local topology execution.
 *
 * These helpers mutate process environment or inspect the local checkout, so
 * they live off the root schema/topology API.
 *
 * @module runtime
 */

export {
  computeRunDir,
  initRunDir,
  neededPorts,
  repoRoot,
  SERVICE_PORTS,
  serviceUrl,
  serviceUrlFromManifest,
} from "./docker_config.ts";
export {
  allocateHostPort,
  allocateHostPorts,
  cleanupStalePortLeases,
  defaultPortLeaseDir,
  hostUrlForPort,
  parsePortRange,
  releaseRunPortLeases,
} from "./port_allocator.ts";
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
export type {
  ClockSource,
  ComputeRunDirOptions,
  EnvSource,
  FileSystemOps,
  InitRunDirOptions,
  ProcessInfo,
  TopologyRunContext,
} from "./docker_config.ts";
export type {
  HostPortAllocationOptions,
  HostPortLease,
  PortRange,
} from "./port_allocator.ts";
export type {
  ResourceIsolationMode,
  RunPortLease,
  RunResourceCleanupState,
  RunResourceEndpoint,
  RunResourceManifest,
} from "./resource_manifest.ts";
