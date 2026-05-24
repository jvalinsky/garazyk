/**
 * Shared type definitions for the scenario dashboard
 *
 * @module dashboard_types
 */

/** Service operational status type. */
export type ServiceStatusType = "running" | "stopped" | "starting" | "error";

/** Status of a single ATProto service in the local network */
export interface ServiceStatus {
  /** Internal service name */
  name: string;
  /** Human-readable service label */
  label: string;
  /** Service URL shown in the dashboard */
  url: string;
  /** Exposed port for the service */
  port: number;
  /** Current lifecycle state */
  status: ServiceStatusType;
  /** Cached health flag when available */
  healthy?: boolean;
}

/** A scenario discovered via file-system scan */
export interface DiscoveredScenario {
  /** Stable scenario identifier */
  id: string;
  /** Human-readable scenario name */
  name: string;
  /** One-line description extracted from the scenario file header */
  description: string;
  /** Filesystem path to the scenario entry point */
  path: string;
  /** Scenario category used for grouping in the dashboard */
  category: string;
  /** Whether the scenario requires PDS2 */
  needsPds2: boolean;
  /** Required scenarios or capabilities */
  requires?: string[];
  /** Parameter metadata keyed by parameter name */
  parameters?: Record<string, {
    type: "number" | "string" | "boolean";
    default: string | number | boolean;
    description: string;
  }>;
}

/** Result status of a scenario run. */
export type ScenarioStatus = "passed" | "failed" | "skipped" | "running";
/** A single scenario parameter value type. */
export type ScenarioParamValue = string | number | boolean;

/** A single step within a scenario result */
export interface Step {
  /** Step name */
  name: string;
  /** Step status */
  status: ScenarioStatus;
  /** Additional detail for the step */
  detail?: string;
  /** Step duration in milliseconds */
  durationMs?: number;
}

/** Configuration for starting a new run */
export interface RunConfig {
  /** Topology preset name */
  topology: string;
  /** Runner implementation to use */
  runner: "host" | "docker";
  /** Scenario identifiers selected for the run */
  scenarioIds: string[];
  /** Include the PDS2 role set */
  pds2: boolean;
  /** Use locally built binaries instead of Docker images */
  binaryMode: boolean;
  /** Browser client name or preset */
  webClient?: string;
  /** Browser flow depth or preset */
  clientFlow?: string;
  /** Scenario parameter overrides keyed by scenario id */
  scenarioParams?: Record<string, ScenarioParamValue>;
  /** Allow hybrid host and container networking */
  allowHybridNetwork?: boolean;
  /** Enable OpenTelemetry tracing */
  otel?: boolean;
  /** Enable verbose logging */
  verbose?: boolean;
  /** Scenario execution timeout */
  timeout?: number;
  /** Skip setup lifecycle phase */
  noSetup?: boolean;
  /** Use hamownia agent run (NDJSON stdout) instead of scripts/run_scenarios.ts */
  agentMode?: boolean;
}

/** A run record, in progress or historical
 *
 * @remarks
 * Epoch timestamps are stored in milliseconds and the scenario parameter map mirrors the original run configuration
 */
export interface Run {
  /** Run identifier */
  id: string;
  /** Epoch milliseconds when the run started */
  startedAt: number;
  /** Epoch milliseconds when the run finished */
  finishedAt?: number;
  /** Current lifecycle state */
  status: "starting" | "running" | "stopping" | "completed" | "error";
  /** Total scenarios scheduled for the run */
  totalScenarios: number;
  /** Number of passed scenarios */
  passed: number;
  /** Number of failed scenarios */
  failed: number;
  /** Number of skipped scenarios */
  skipped: number;
  /** Total run duration in seconds */
  durationS?: number;
  /** Whether the PDS2 role set was included */
  pds2?: boolean;
  /** Whether the run used local binaries */
  binaryMode?: boolean;
  /** Topology preset used for the run */
  topology?: string;
  /** Runner implementation used for the run */
  runner?: "host" | "docker";
  /** Browser client selected for the run */
  webClient?: string;
  /** Browser flow depth or preset selected for the run */
  clientFlow?: string;
  /** Scenario identifiers included in the run */
  scenarioIds?: string[];
  /** Directory containing run artifacts */
  runDir?: string;
  /** Directory containing generated reports */
  reportsDir?: string;
  /** Path to the run log */
  logPath?: string;
  /** Path to the run resource manifest, when the network setup writes one */
  manifestPath?: string;
  /** Docker Compose project name, when Docker mode is used */
  composeProject?: string;
  /** PID of the spawned run process */
  childPid?: number;
  /** Process exit code when available */
  exitCode?: number;
  /** Epoch milliseconds when the run stopped */
  stoppedAt?: number;
  /** Reason the run stopped */
  stopReason?: string;
  /** Scenario parameter overrides keyed by scenario id */
  scenarioParams?: Record<string, ScenarioParamValue>;
  /** Allow hybrid host and container networking */
  allowHybridNetwork?: boolean;
  /** Enable OpenTelemetry tracing */
  otel?: boolean;
  /** Enable verbose logging */
  verbose?: boolean;
  /** Scenario execution timeout */
  timeout?: number;
  /** Skip setup lifecycle phase */
  noSetup?: boolean;
  /** Whether the run used hamownia agent mode (NDJSON stdout). */
  agentMode?: boolean;
}

// ---------------------------------------------------------------------------
// RunEvent — event-driven lifecycle notifications from RunManager
// ---------------------------------------------------------------------------

/** Event emitted when a run starts. */
export interface RunStartedEvent {
  type: "run_started";
  /** Run identifier */
  runId: string;
  /** Total scenarios scheduled */
  totalScenarios: number;
  /** Epoch milliseconds when the run started */
  startedAt: number;
}

/** Event emitted when a run's lifecycle status changes. */
export interface RunStatusEvent {
  type: "run_status";
  /** Run identifier */
  runId: string;
  /** New lifecycle status */
  status: Run["status"];
}

/** Event emitted when a scenario within a run begins executing. */
export interface ScenarioStartedEvent {
  type: "scenario_started";
  /** Run identifier */
  runId: string;
  /** Scenario identifier */
  scenarioId: string;
  /** Human-readable scenario name */
  scenarioName: string;
}

/** Event emitted when a scenario within a run finishes. */
export interface ScenarioFinishedEvent {
  type: "scenario_finished";
  /** Run identifier */
  runId: string;
  /** Scenario identifier */
  scenarioId: string;
  /** Human-readable scenario name */
  scenarioName: string;
  /** Final scenario status */
  status: ScenarioStatus;
  /** Number of passed assertions */
  passed: number;
  /** Number of failed assertions */
  failed: number;
  /** Number of skipped assertions */
  skipped: number;
  /** Scenario duration in milliseconds */
  durationMs?: number;
}

/** Event emitted when a run completes successfully. */
export interface RunCompletedEvent {
  type: "run_completed";
  /** Run identifier */
  runId: string;
  /** Process exit code */
  exitCode: number;
  /** Epoch milliseconds when the run finished */
  finishedAt: number;
  /** Total passed scenarios */
  passed: number;
  /** Total failed scenarios */
  failed: number;
  /** Total skipped scenarios */
  skipped: number;
}

/** Event emitted when a run fails. */
export interface RunFailedEvent {
  type: "run_failed";
  /** Run identifier */
  runId: string;
  /** Process exit code (0 if not available) */
  exitCode: number;
  /** Epoch milliseconds when the run finished */
  finishedAt: number;
  /** Reason the run failed */
  reason: string;
}

/** Event emitted for each line of log output from a running process. */
export interface LogLineEvent {
  type: "log_line";
  /** Run identifier */
  runId: string;
  /** Single line of log output (no trailing newline) */
  line: string;
}

/** Discriminated union of all events emitted by RunManager. */
export type RunEvent =
  | RunStartedEvent
  | RunStatusEvent
  | ScenarioStartedEvent
  | ScenarioFinishedEvent
  | RunCompletedEvent
  | RunFailedEvent
  | LogLineEvent;

/** A single step within a scenario report JSON. */
export interface ScenarioStep {
  /** Step name */
  name: string;
  /** Step status */
  status: "passed" | "failed" | "skipped";
  /** Failure message or detail text */
  detail: string;
  /** Step duration in milliseconds */
  duration_ms: number;
}

/** Result of a single scenario within a run */
export interface ScenarioResult {
  /** Primary key for the result record */
  id: number;
  /** Parent run identifier */
  runId: string;
  /** Scenario identifier */
  scenarioId: string;
  /** Human-readable scenario name */
  scenarioName: string;
  /** Final scenario status */
  status: ScenarioStatus;
  /** Number of passed assertions or steps */
  passed: number;
  /** Number of failed assertions or steps */
  failed: number;
  /** Number of skipped assertions or steps */
  skipped: number;
  /** Scenario duration in milliseconds */
  durationMs?: number;
  /** Serialized step list JSON */
  stepsJson: string;
  /** Serialized artifact metadata JSON */
  artifactsJson?: string;
  /** Epoch milliseconds when the scenario started */
  startedAt?: number;
  /** Epoch milliseconds when the scenario finished */
  finishedAt?: number;
}

/** Parsed scenario result with deserialized steps and artifacts. */
export interface ScenarioResultView {
  /** Scenario identifier */
  scenarioId: string;
  /** Human-readable scenario name */
  scenarioName: string;
  /** Final scenario status */
  status: ScenarioStatus;
  /** Number of passed assertions or steps */
  passed: number;
  /** Number of failed assertions or steps */
  failed: number;
  /** Number of skipped assertions or steps */
  skipped: number;
  /** Scenario duration in milliseconds */
  durationMs: number | null;
  /** Parsed step list */
  steps: ScenarioStep[];
  /** Parsed artifact metadata, or null */
  artifacts: Record<string, unknown> | null;
}
