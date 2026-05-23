/** Shared types for scenario runner argument parsing. @module run_scenarios_types */

/**
 * Shared types for scenario runner argument parsing
 *
 * @module run_scenarios_types
 */
import type { BrowserFlow } from "@garazyk/schemat";
import type { ResourceIsolationMode } from "@garazyk/schemat";

/** CLI arguments parsed for the scenario runner
 *
 * @remarks
 * Setup and teardown flags change lifecycle behavior, while topology, runner, and browser settings shape the execution environment
 */
export interface RunnerArgs {
  /** Scenario identifiers to run */
  scenarioIds: string[];
  /** List matching scenarios without executing them */
  list: boolean;
  /** Run only setup before exiting */
  setupOnly: boolean;
  /** Run setup before executing scenarios */
  setup: boolean;
  /** Run teardown after scenarios complete */
  teardown: boolean;
  /** Run only teardown before exiting */
  teardownOnly: boolean;
  /** Skip setup even when scenarios are executed */
  noSetup: boolean;
  /** Use locally built binaries instead of Docker images */
  binary: boolean;
  /** Include the PDS2 role set */
  pds2: boolean;
  /** Enable verbose logging */
  verbose: boolean;
  /** Suppress JSON output */
  noJson: boolean;
  /** Leave the network running after the run completes */
  keepRunning: boolean;
  /** Collect diagnostics artifacts */
  collectDiagnostics: boolean;
  /** Maximum run time in seconds */
  timeout: number;
  /** Browser flow depth used by the web client */
  clientFlow: BrowserFlow;
  /** Optional browser client name or preset */
  webClient?: string;
  /** Allow host and container networking together */
  allowHybridNetwork: boolean;
  /** Existing run identifier to reuse */
  runId?: string;
  /** Resource isolation mode for local services */
  isolation: ResourceIsolationMode;
  /** Existing resource manifest to attach to */
  resourceManifest?: string;
  /** Optional START:END port range for dynamic leases */
  portRange?: string;
  /** Directory where diagnostics are written */
  diagnosticsDir?: string;
  /** Directory where reports are written */
  reportsDir?: string;
  /** Topology preset name to resolve */
  topology?: string;
  /** Execution runner to use */
  runner: "host" | "docker";
  /** Enable OpenTelemetry export */
  otel: boolean;
}
