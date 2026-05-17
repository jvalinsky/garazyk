/**
 * Generic Docker Engine, Compose, health, event, stats, and runner utilities.
 *
 * Garazyk's ATProto network orchestration is intentionally outside the root
 * package API. Use `@garazyk/hamownia/atproto-network` for scenario-network
 * lifecycle management.
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
export {
  buildDockerRunnerArgs,
  DOCKER_RUNNER_TIMEOUT_EXIT_CODE,
  runScenarioInDocker,
} from "./docker_runner.ts";
export type { DockerRunnerOptions } from "./docker_runner.ts";
