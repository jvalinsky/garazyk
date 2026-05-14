/**
 * Database query helpers for the scenario dashboard.
 */

import { Database } from "sqlite3";
import { Run, ScenarioStatus } from "../services/types.ts";

/**
 * Fetch a single run by ID with all camelCase aliases applied.
 */
export function fetchRun(db: Database, runId: string): Run | undefined {
  return db.prepare(`
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
      binary_mode as binaryMode
    FROM runs
    WHERE id = ?
  `).get(runId) as Run | undefined;
}

/**
 * Fetch the last N runs with all camelCase aliases applied.
 */
export function fetchRuns(db: Database, limit = 10): Run[] {
  return db.prepare(`
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
      binary_mode as binaryMode
    FROM runs
    ORDER BY started_at DESC
    LIMIT ?
  `).all(limit) as Run[];
}

/**
 * Fetch the latest result for each scenario using a deterministic correlated subquery.
 * Guarantees that the returned columns (status, passed, failed, skipped) come from the same
 * row as the maximum started_at timestamp for each scenario.
 */
export function fetchLatestResultPerScenario(
  db: Database,
): Array<{ scenario_id: string; status: ScenarioStatus; passed: number; failed: number; skipped: number }> {
  return db.prepare(`
    SELECT scenario_id, status, passed, failed, skipped
    FROM scenario_results sr
    WHERE started_at = (
      SELECT MAX(started_at)
      FROM scenario_results
      WHERE scenario_id = sr.scenario_id
    )
  `).all() as Array<{
    scenario_id: string;
    status: ScenarioStatus;
    passed: number;
    failed: number;
    skipped: number;
  }>;
}
