/**
 * Shared Type Definitions
 */

export type ServiceStatusType = "running" | "stopped" | "starting" | "error";

export interface ServiceStatus {
  name: string;
  label: string;
  url: string;
  port: number;
  status: ServiceStatusType;
  healthy?: boolean;
}

export interface DiscoveredScenario {
  id: string;
  name: string;
  path: string;
  category: string;
  needsPds2: boolean;
}

export type ScenarioStatus = "passed" | "failed" | "skipped" | "running";

export interface Step {
  name: string;
  status: ScenarioStatus;
  detail?: string;
  durationMs?: number;
}

export interface Run {
  id: string;
  startedAt: number;
  finishedAt?: number;
  status: "running" | "completed" | "error";
  totalScenarios: number;
  passed: number;
  failed: number;
  skipped: number;
  durationS?: number;
  pds2?: boolean;
  binaryMode?: boolean;
}

export interface ScenarioResult {
  id: number;
  runId: string;
  scenarioId: string;
  scenarioName: string;
  status: ScenarioStatus;
  passed: number;
  failed: number;
  skipped: number;
  durationMs?: number;
  stepsJson: string;
  artifactsJson?: string;
  startedAt?: number;
  finishedAt?: number;
}
