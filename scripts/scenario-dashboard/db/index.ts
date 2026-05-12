import { join, fromFileUrl } from "$std/path/mod.ts";
import { Database } from "sqlite3";
import { scanReports } from "../services/report_scanner.ts";

const DB_PATH = join(
  fromFileUrl(new URL("../../scenarios/reports/dashboard.db", import.meta.url)),
);

export const db = new Database(DB_PATH);

// Initialize schema and import any existing reports
await scanReports(db);
