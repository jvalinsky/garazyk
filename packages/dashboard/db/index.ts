/** Database initialization — opens the SQLite DB, applies schema and migrations, scans reports. @module db */
import { Database } from "sqlite3";
import { SCHEMA } from "./schema.ts";
import { runMigrations } from "./migrations.ts";
import { scanReports } from "../services/report_scanner.ts";
import { getDashboardPaths } from "../paths.ts";

const DB_PATH = getDashboardPaths().dashboardDbPath;

const isBuild = Deno.args.includes("build");
const buildDb = {
  prepare: () => ({ all: () => [], run: () => ({}), get: () => null }),
  exec: () => {},
} as unknown as Database;

// Export a placeholder or the real DB depending on mode
/** Singleton SQLite database handle (or stub during build). */
export const db: Database = isBuild ? buildDb : new Database(DB_PATH);

if (!isBuild) {
  // Initialize base schema first
  db.exec(SCHEMA);

  // Apply migrations for new features
  runMigrations(db);

  // Scan reports in background — do not block server startup
  setTimeout(async () => {
    try {
      const n = await scanReports(db);
      if (n > 0) console.log(`[db] Imported ${n} report(s) on startup`);
    } catch (e) {
      console.error("[db] scanReports failed on startup:", e);
    }
  }, 0);
}
