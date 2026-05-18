/**
 * Generic Docker Engine, Compose, health, event, and stats utilities.
 *
 * Scenario Docker execution has moved to `@garazyk/hamownia/docker-runner`.
 * ATProto network orchestration is at `@garazyk/hamownia/atproto-network`.
 *
 * @module laweta
 */

export {
  composeProjectName,
  composeServiceName,
  cpuPercent,
  createDockerClient,
  DockerApiClient,
  DockerApiError,
  findPortConflicts,
  findStaleProjectsOnPorts,
  formatMemory,
  healthStatus,
  memoryLimit,
  memoryUsage,
  parseDockerLogBuffer,
} from "./docker_api.ts";
export type {
  ContainerInspect,
  ContainerLogsOptions,
  ContainerStats,
  ContainerSummary,
  DockerEvent,
  DockerVersion,
  PortConflict,
} from "./docker_api.ts";
export {
  buildContainerEventFilters,
  ContainerEventWatcher,
  DockerEventParser,
} from "./docker_events.ts";
export type {
  ContainerCrashEvent,
  ContainerEventWatcherOptions,
  ContainerHealthEvent,
  ContainerState,
  WatcherEvent,
} from "./docker_events.ts";
export {
  waitForHttp,
  waitForService,
  waitForServiceCLI,
} from "./docker_health.ts";
export { ContainerStatsSampler } from "./container_stats.ts";
export type {
  ContainerStatsSnapshot,
  MemoryPressureAlert,
  StatsSamplerOptions,
} from "./container_stats.ts";
export { composeDown, composeUp } from "./docker_compose.ts";
