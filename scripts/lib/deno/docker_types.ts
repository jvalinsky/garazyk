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
  onSessionStarted?: (session: NetworkSession) => void | Promise<void>;
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

export interface NetworkSession {
  runId: string;
  runDir: string;
  diagnosticsDir: string;
  composeProject: string;
  composeFiles: string[];
  topologyManifestPath?: string;
  withPds2: boolean;
  useBinary: boolean;
}
