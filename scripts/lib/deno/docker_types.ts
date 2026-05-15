/**
 * Shared types for the Docker/binary local network modules.
 *
 * @module docker_types
 */

import type { ContainerStatsSampler } from "./container_stats.ts";

export interface LocalNetworkOptions {
  withPds2?: boolean;
  useBinary?: boolean;
  keepRunning?: boolean;
  runId?: string;
  diagnosticsDir?: string;
  webClient?: string;
  clientFlow?: string;
  allowHybridNetwork?: boolean;
  topology?: string;
  otel?: boolean;
  skipDockerStage?: boolean;
  waitOnly?: boolean;
  collectDiagnostics?: boolean;
}

export interface RunContext {
  runId: string;
  runDir: string;
  diagnosticsDir: string;
  logDir: string;
  pidFile: string;
  composeProject: string;
  baseDir: string;
  statsSampler?: ContainerStatsSampler;
}
