/**
 * Shared types for the Docker/binary local network modules.
 *
 * @module docker_types
 */

import type { ContainerStatsSampler } from "./container_stats.ts";

/** Options for launching the local Docker or binary network
 *
 * @remarks
 * Major execution paths are controlled by the binary, hybrid-network, and diagnostic flags
 */
export interface LocalNetworkOptions {
  /** Include the PDS2 service set */
  withPds2?: boolean;
  /** Use locally built binaries instead of Docker images */
  useBinary?: boolean;
  /** Leave the network running after the command completes */
  keepRunning?: boolean;
  /** Identifier for the current run */
  runId?: string;
  /** Directory where diagnostics are written */
  diagnosticsDir?: string;
  /** Browser client name or preset to run alongside the topology */
  webClient?: string;
  /** Browser flow depth or preset passed to the web client */
  clientFlow?: string;
  /** Allow host and container networking at the same time */
  allowHybridNetwork?: boolean;
  /** Topology preset name to resolve */
  topology?: string;
  /** Enable OpenTelemetry export */
  otel?: boolean;
  /** Skip the Docker image build stage */
  skipDockerStage?: boolean;
  /** Wait for an existing network instead of starting a new one */
  waitOnly?: boolean;
  /** Collect extra diagnostics on failure or shutdown */
  collectDiagnostics?: boolean;
}

/** Runtime paths and process metadata for a local network run
 *
 * @remarks
 * These paths are derived once per run and must stay stable until teardown completes
 */
export interface RunContext {
  /** Identifier for the current run */
  runId: string;
  /** Directory containing the run outputs */
  runDir: string;
  /** Directory containing diagnostics artifacts */
  diagnosticsDir: string;
  /** Directory containing log files */
  logDir: string;
  /** Path to the file storing the child process PID */
  pidFile: string;
  /** Docker Compose project name */
  composeProject: string;
  /** Base directory for the current execution */
  baseDir: string;
  /** Optional sampler used to collect container statistics */
  statsSampler?: ContainerStatsSampler;
}
