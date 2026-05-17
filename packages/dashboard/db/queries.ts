/**
 * Database query helpers for the scenario dashboard.
 */

import type { Database } from "sqlite3";
import type {
  Run,
  ScenarioParamValue,
  ScenarioStatus,
} from "../services/types.ts";

interface RunRow extends Omit<Run, "binaryMode" | "pds2" | "scenarioParams"> {
  binaryMode?: number | boolean;
  pds2?: number | boolean;
  scenarioIdsJson?: string | null;
  scenarioParamsJson?: string | null;
  scenarioParams?: Record<string, ScenarioParamValue>;
}

/** Normalize epoch timestamps: second-based values are converted to ms. */
export function normalizeEpochMs(
  value: number | null | undefined,
): number | undefined {
  if (value === null || value === undefined) return undefined;
  return value < 10_000_000_000 ? value * 1000 : value;
}

function normalizeRun(row: RunRow | undefined): Run | undefined {
  if (!row) return undefined;
  const { scenarioIdsJson, scenarioParamsJson, ...base } = row;
  const run = {
    ...base,
    startedAt: normalizeEpochMs(row.startedAt) ?? row.startedAt,
    finishedAt: normalizeEpochMs(row.finishedAt),
    stoppedAt: normalizeEpochMs(row.stoppedAt),
    pds2: Boolean(row.pds2),
    binaryMode: Boolean(row.binaryMode),
    scenarioIds: row.scenarioIds ?? parseStringArrayJson(scenarioIdsJson),
    scenarioParams: row.scenarioParams ??
      parseScenarioParamsJson(scenarioParamsJson),
  };
  return run;
}

/**
 * Fetch a single run by ID with all camelCase aliases applied.
 */
export function fetchRun(db: Database, runId: string): Run | undefined {
  const row = db.prepare(`
    SELECT
      id,
      started_at as startedAt,
      finished_at as finishedAt,
      passed,
      failed,
      skipped,
      total_scenarios as totalScenarios,
      duration_s as durationS,
      status,
      pds2,
      binary_mode as binaryMode,
      topology,
      runner,
      web_client as webClient,
      client_flow as clientFlow,
      scenario_ids_json as scenarioIdsJson,
      run_dir as runDir,
      reports_dir as reportsDir,
      log_path as logPath,
      compose_project as composeProject,
      manifest_path as manifestPath,
      child_pid as childPid,
      exit_code as exitCode,
      stopped_at as stoppedAt,
      stop_reason as stopReason,
      scenario_params_json as scenarioParamsJson
    FROM runs
    WHERE id = ?
  `).get(runId) as RunRow | undefined;
  return normalizeRun(row);
}

/**
 * Fetch the last N runs with all camelCase aliases applied.
 */
export function fetchRuns(db: Database, limit = 10): Run[] {
  const rows = db.prepare(`
    SELECT
      id,
      started_at as startedAt,
      finished_at as finishedAt,
      passed,
      failed,
      skipped,
      total_scenarios as totalScenarios,
      duration_s as durationS,
      status,
      pds2,
      binary_mode as binaryMode,
      topology,
      runner,
      web_client as webClient,
      client_flow as clientFlow,
      scenario_ids_json as scenarioIdsJson,
      run_dir as runDir,
      reports_dir as reportsDir,
      log_path as logPath,
      compose_project as composeProject,
      manifest_path as manifestPath,
      child_pid as childPid,
      exit_code as exitCode,
      stopped_at as stoppedAt,
      stop_reason as stopReason,
      scenario_params_json as scenarioParamsJson
    FROM runs
    ORDER BY started_at DESC
    LIMIT ?
  `).all(limit) as RunRow[];
  return rows.map((row) => normalizeRun(row)!);
}

/**
 * Fetch the latest result for each scenario using a window function.
 */
export function fetchLatestResultPerScenario(
  db: Database,
): Array<
  {
    scenario_id: string;
    status: ScenarioStatus;
    passed: number;
    failed: number;
    skipped: number;
  }
> {
  return db.prepare(`
    SELECT scenario_id, status, passed, failed, skipped
    FROM (
      SELECT scenario_id, status, passed, failed, skipped,
        ROW_NUMBER() OVER (PARTITION BY scenario_id ORDER BY started_at DESC, id DESC) AS rn
      FROM scenario_results
    )
    WHERE rn = 1
  `).all() as Array<{
    scenario_id: string;
    status: ScenarioStatus;
    passed: number;
    failed: number;
    skipped: number;
  }>;
}

function parseStringArrayJson(
  value: string | null | undefined,
): string[] | undefined {
  if (!value) return undefined;
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) &&
        parsed.every((item) => typeof item === "string")
      ? parsed
      : undefined;
  } catch {
    return undefined;
  }
}

function parseScenarioParamsJson(
  value: string | null | undefined,
): Record<string, ScenarioParamValue> | undefined {
  if (!value) return undefined;
  try {
    const parsed = JSON.parse(value);
    if (
      parsed === null || typeof parsed !== "object" || Array.isArray(parsed)
    ) return undefined;

    const params: Record<string, ScenarioParamValue> = {};
    for (const [key, paramValue] of Object.entries(parsed)) {
      if (
        typeof paramValue === "string" || typeof paramValue === "number" ||
        typeof paramValue === "boolean"
      ) {
        params[key] = paramValue;
      }
    }
    return params;
  } catch {
    return undefined;
  }
}
