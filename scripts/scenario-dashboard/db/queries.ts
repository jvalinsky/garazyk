/**
 * Database query helpers for the scenario dashboard.
 */

import { Database } from "sqlite3";
import {
  Run,
  ScenarioResult,
  ScenarioResultView,
  ScenarioStatus,
  ScenarioStep,
} from "../services/types.ts";

/** Normalize epoch timestamps: second-based values are converted to ms. */
export function normalizeEpochMs(
  value: number | null | undefined,
): number | undefined {
  if (value === null || value === undefined) return undefined;
  return value < 10_000_000_000 ? value * 1000 : value;
}

/** Parse dashboard run IDs like 2026-05-24T05-06-45-159 into epoch ms. */
export function parseRunIdEpochMs(
  runId: string | undefined,
): number | undefined {
  if (!runId) return undefined;
  const match = runId.match(
    /^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2})-?(\d{2})(?:-?(\d{2}))?/,
  );
  if (!match) return undefined;
  const [, year, month, day, hour, minute, second] = match;
  const epoch = Date.UTC(
    Number(year),
    Number(month) - 1,
    Number(day),
    Number(hour),
    Number(minute),
    second ? Number(second) : 0,
  );
  return Number.isFinite(epoch) ? epoch : undefined;
}

function normalizeRun(row: Run | undefined): Run | undefined {
  if (!row) return undefined;
  const storedStartedAt = normalizeEpochMs(row.startedAt) ?? row.startedAt;
  const runIdStartedAt = parseRunIdEpochMs(row.id);
  const startedAt = runIdStartedAt !== undefined &&
      Math.abs(storedStartedAt - runIdStartedAt) > 24 * 60 * 60 * 1000
    ? runIdStartedAt
    : storedStartedAt;
  const finishedAt = normalizeEpochMs(row.finishedAt);
  const stoppedAt = normalizeEpochMs(row.stoppedAt);
  const durationFinishedAt =
    typeof row.durationS === "number" && row.durationS >= 0
      ? startedAt + row.durationS * 1000
      : undefined;
  const run = {
    ...row,
    startedAt,
    finishedAt: finishedAt !== undefined && finishedAt >= startedAt
      ? finishedAt
      : durationFinishedAt,
    stoppedAt: stoppedAt !== undefined && stoppedAt >= startedAt
      ? stoppedAt
      : undefined,
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
      scenario_params_json as scenarioParamsJson,
      allow_hybrid_network as allowHybridNetwork,
      otel,
      verbose,
      timeout,
      no_setup as noSetup,
      agent_mode as agentMode
    FROM runs
    WHERE id = ?
  `).get(runId) as Run | undefined;
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
      scenario_params_json as scenarioParamsJson,
      allow_hybrid_network as allowHybridNetwork,
      otel,
      verbose,
      timeout,
      no_setup as noSetup,
      agent_mode as agentMode
    FROM runs
    ORDER BY started_at DESC
    LIMIT ?
  `).all(limit) as Run[];
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

/**
 * Fetch all scenario results for a given run, parsed into view model shape.
 * Steps and artifacts are deserialized from JSON strings.
 */
export function fetchScenarioResults(
  db: Database,
  runId: string,
): ScenarioResultView[] {
  const rows = db.prepare(`
    SELECT
      scenario_id,
      scenario_name,
      status,
      passed,
      failed,
      skipped,
      duration_ms,
      steps_json,
      artifacts_json,
      started_at,
      finished_at
    FROM scenario_results
    WHERE run_id = ?
    ORDER BY id
  `).all(runId) as Array<{
    scenario_id: string;
    scenario_name: string;
    status: ScenarioStatus;
    passed: number;
    failed: number;
    skipped: number;
    duration_ms: number | null;
    steps_json: string;
    artifacts_json: string | null;
    started_at: number | null;
    finished_at: number | null;
  }>;

  return rows.map((row): ScenarioResultView => {
    let steps: ScenarioStep[] = [];
    try {
      steps = JSON.parse(row.steps_json) as ScenarioStep[];
    } catch {
      // Malformed JSON — leave empty
    }

    let artifacts: Record<string, unknown> | null = null;
    if (row.artifacts_json) {
      try {
        artifacts = JSON.parse(row.artifacts_json) as Record<string, unknown>;
      } catch {
        // Malformed — leave null
      }
    }

    return {
      scenarioId: row.scenario_id,
      scenarioName: row.scenario_name,
      status: row.status,
      passed: row.passed,
      failed: row.failed,
      skipped: row.skipped,
      durationMs: row.duration_ms,
      steps,
      artifacts,
    };
  });
}
