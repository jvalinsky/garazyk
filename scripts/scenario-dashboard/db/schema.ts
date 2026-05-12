/**
 * SQLite schema for the scenario dashboard.
 * Stores run history and scenario results.
 */

export const SCHEMA = `
CREATE TABLE IF NOT EXISTS runs (
  id TEXT PRIMARY KEY,
  started_at INTEGER NOT NULL,
  finished_at INTEGER,
  status TEXT NOT NULL DEFAULT 'running',
  total_scenarios INTEGER DEFAULT 0,
  passed INTEGER DEFAULT 0,
  failed INTEGER DEFAULT 0,
  skipped INTEGER DEFAULT 0,
  duration_s REAL,
  git_commit TEXT,
  pds2 INTEGER DEFAULT 0,
  binary_mode INTEGER DEFAULT 0,
  diagnostics_dir TEXT
);

CREATE TABLE IF NOT EXISTS scenario_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id TEXT NOT NULL REFERENCES runs(id),
  scenario_id TEXT NOT NULL,
  scenario_name TEXT NOT NULL,
  status TEXT NOT NULL,
  passed INTEGER DEFAULT 0,
  failed INTEGER DEFAULT 0,
  skipped INTEGER DEFAULT 0,
  duration_ms INTEGER,
  steps_json TEXT NOT NULL,
  artifacts_json TEXT,
  started_at INTEGER,
  finished_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_scenario_results_run ON scenario_results(run_id);
CREATE INDEX IF NOT EXISTS idx_scenario_results_scenario ON scenario_results(scenario_id);

CREATE TABLE IF NOT EXISTS services (
  name TEXT PRIMARY KEY,
  container_id TEXT,
  port INTEGER,
  url TEXT,
  status TEXT NOT NULL DEFAULT 'stopped',
  last_health_check INTEGER,
  last_error TEXT
);
`;
