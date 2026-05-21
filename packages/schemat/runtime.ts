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
} from "./docker_config.ts";
export type {
  ClockSource,
  ComputeRunDirOptions,
  EnvSource,
  FileSystemOps,
  InitRunDirOptions,
  ProcessInfo,
  TopologyRunContext,
} from "./docker_config.ts";
