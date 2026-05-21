/** Database schema migrations for the scenario dashboard. @module migrations */
import { Database } from "sqlite3";

/**
 * Migration runner for the dashboard database.
 */
export function runMigrations(db: Database) {
  // 1. Create migration tracking table
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      applied_at INTEGER NOT NULL
    );
  `);

  const currentVersion = getCurrentVersion(db);

  // Migration 1: Expanded run tracking columns
  if (currentVersion < 1) {
    console.log("[db] Applying migration v1: Expand runs table...");
    try {
      addColumns(db, "runs", [
        "topology TEXT",
        "runner TEXT DEFAULT 'host'",
        "web_client TEXT",
        "client_flow TEXT DEFAULT 'none'",
        "scenario_ids_json TEXT",
        "run_dir TEXT",
        "reports_dir TEXT",
        "compose_project TEXT",
        "manifest_path TEXT",
        "log_path TEXT",
        "child_pid INTEGER",
        "exit_code INTEGER",
        "stopped_at INTEGER",
        "stop_reason TEXT",
        "scenario_params_json TEXT",
      ]);
      recordMigration(db, 1);
    } catch (e) {
      console.error("[db] Migration v1 failed:", e);
      throw e;
    }
  }

  // Migration 2: Run events table for state transitions
  if (currentVersion < 2) {
    console.log("[db] Applying migration v2: Create run_events table...");
    try {
      db.exec(`
        CREATE TABLE IF NOT EXISTS run_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          run_id TEXT NOT NULL REFERENCES runs(id),
          event TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          detail_json TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_run_events_run ON run_events(run_id);
      `);
      recordMigration(db, 2);
    } catch (e) {
      console.error("[db] Migration v2 failed:", e);
      throw e;
    }
  }

  // Migration 3: Ensure scenario_params_json exists
  if (currentVersion < 3) {
    console.log("[db] Applying migration v3: Ensure scenario_params_json exists...");
    try {
      addColumns(db, "runs", [
        "scenario_params_json TEXT",
      ]);
      recordMigration(db, 3);
    } catch (e) {
      console.error("[db] Migration v3 failed:", e);
      throw e;
    }
  }

  // Migration 4: Add new run option tracking columns
  if (currentVersion < 4) {
    console.log("[db] Applying migration v4: Add option columns to runs table...");
    try {
      addColumns(db, "runs", [
        "allow_hybrid_network INTEGER DEFAULT 0",
        "otel INTEGER DEFAULT 0",
        "verbose INTEGER DEFAULT 0",
        "timeout INTEGER DEFAULT 120",
        "no_setup INTEGER DEFAULT 0",
      ]);
      recordMigration(db, 4);
    } catch (e) {
      console.error("[db] Migration v4 failed:", e);
      throw e;
    }
  }
}

function getCurrentVersion(db: Database): number {
  try {
    const row = db.prepare("SELECT MAX(version) as v FROM schema_migrations").get() as {
      v: number | null;
    };
    return row?.v || 0;
  } catch {
    return 0;
  }
}

function recordMigration(db: Database, version: number) {
  db.prepare("INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)").run(
    version,
    Date.now(),
  );
}

function addColumns(db: Database, table: string, columns: string[]) {
  // Get existing columns
  const info = db.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name: string }>;
  const existing = new Set(info.map((col) => col.name));

  for (const columnDef of columns) {
    const name = columnDef.split(" ")[0];
    if (!existing.has(name)) {
      db.exec(`ALTER TABLE ${table} ADD COLUMN ${columnDef}`);
    }
  }
}
