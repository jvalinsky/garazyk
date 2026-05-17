/** Database initialization — opens the SQLite DB, applies schema and migrations, scans reports. @module db */
import { Database } from "sqlite3";
import { SCHEMA } from "./schema.ts";
import { runMigrations } from "./migrations.ts";
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

}
