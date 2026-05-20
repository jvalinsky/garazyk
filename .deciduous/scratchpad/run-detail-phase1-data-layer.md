# Phase 1: Data Layer — ScenarioResult type, query, service endpoint

## Goal
Add the data access layer needed to fetch per-scenario results for a given run.

## Changes

### 1. `services/types.ts` — Add ScenarioResult type

```ts
export interface ScenarioStep {
  name: string;
  status: "passed" | "failed" | "skipped";
  detail: string;
  duration_ms: number;
}

export interface ScenarioResult {
  scenarioId: string;
  scenarioName: string;
  status: ScenarioStatus;
  passed: number;
  failed: number;
  skipped: number;
  durationMs: number | null;
  steps: ScenarioStep[];
  artifacts: Record<string, unknown> | null;
  startedAt: number | null;
  finishedAt: number | null;
}
```

### 2. `db/queries.ts` — Add fetchScenarioResults

```ts
export function fetchScenarioResults(db: Database, runId: string): ScenarioResult[] {
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
  `).all(runId);
  return rows.map(normalizeScenarioResult);
}
```

The `normalizeScenarioResult` function parses `steps_json` and `artifacts_json` from strings.

### 3. `dashboard_server.ts` — Add GET /api/runs/:id/results endpoint

Returns `{ results: ScenarioResult[] }` for a given run ID.
Calls `fetchScenarioResults(db, runId)`.

## Verification
- `deno check` on modified files
- Query returns correct shape for existing data
