/**
 * Report Scanner — scans existing JSON report files and imports them into SQLite.
 * Parses filenames in the format: YYYYMMDD-HHMMSS-scenario_name.json
 */

import { join, fromFileUrl } from "$std/path/mod.ts";
import { Database } from "sqlite3";

const REPORTS_DIR = join(
  fromFileUrl(new URL("../../scenarios/reports", import.meta.url)),
);

interface ReportFile {
  scenario: string;
  started_at: number;
  finished_at: number;
  duration_s: number;
  steps: Array<{
    name: string;
    status: string;
    detail: string;
    duration_ms: number;
  }>;
  summary: {
    passed: number;
    failed: number;
    skipped: number;
    total: number;
  };
  ok: boolean;
}

function parseFilename(filename: string): { timestamp: string; scenarioName: string } | null {
  // Format: 20260507-183659-account_lifecycle_&_identity.json
  const match = filename.match(/^(\d{8}-\d{6})-(.+)\.json$/);
  if (!match) return null;
  return { timestamp: match[1], scenarioName: match[2] };
}

function timestampToUnix(ts: string): number {
  // 20260507-183659 -> Unix timestamp
  const year = parseInt(ts.substring(0, 4));
  const month = parseInt(ts.substring(4, 6)) - 1;
  const day = parseInt(ts.substring(6, 8));
  const hour = parseInt(ts.substring(9, 11));
  const min = parseInt(ts.substring(11, 13));
  const sec = parseInt(ts.substring(13, 15));
  return Math.floor(new Date(Date.UTC(year, month, day, hour, min, sec)).getTime() / 1000);
}

export async function scanReports(db: Database): Promise<number> {
  let imported = 0;

  // Create tables if they don't exist
  const { SCHEMA } = await import("../db/schema.ts");
  db.exec(SCHEMA);

  try {
    // Group reports by run timestamp
    const runGroups: Map<string, Array<{ filename: string; parsed: ReturnType<typeof parseFilename> }>> = new Map();

    for await (const entry of Deno.readDir(REPORTS_DIR)) {
      if (!entry.isFile || !entry.name.endsWith(".json")) continue;
      const parsed = parseFilename(entry.name);
      if (!parsed) continue;

      // The "runs" subdirectory contains logs, skip those
      if (entry.name.includes("/runs/")) continue;

      if (!runGroups.has(parsed.timestamp)) {
        runGroups.set(parsed.timestamp, []);
      }
      runGroups.get(parsed.timestamp)!.push({ filename: entry.name, parsed });
    }

    for (const [timestamp, files] of runGroups) {
      const runId = timestamp;
      const startedAt = timestampToUnix(timestamp);

      // Check if this run already exists
      const existing = db.prepare("SELECT id FROM runs WHERE id = ?").get<[string]>(runId);
      if (existing) continue;

      let totalPassed = 0;
      let totalFailed = 0;
      let totalSkipped = 0;
      let finishedAt = startedAt;
      let runOk = true;

      // Begin transaction
      db.exec("BEGIN TRANSACTION");

      try {
        for (const file of files) {
          const filePath = join(REPORTS_DIR, file.filename);
          const content = await Deno.readTextFile(filePath);
          const report: ReportFile = JSON.parse(content);

          const scenarioId = file.parsed!.scenarioName.replace(/_&_?/g, "_").replace(/^(\d+)_/, "$1");
          // Try to extract numeric ID from the scenario name
          const idMatch = file.parsed!.scenarioName.match(/^(\d+)/);

          totalPassed += report.summary.passed;
          totalFailed += report.summary.failed;
          totalSkipped += report.summary.skipped;

          if (report.finished_at > finishedAt) {
            finishedAt = report.finished_at;
          }

          if (!report.ok) runOk = false;

          db.prepare(
            `INSERT INTO scenario_results (run_id, scenario_id, scenario_name, status, passed, failed, skipped, duration_ms, steps_json, started_at, finished_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
          ).run(
            runId,
            idMatch ? idMatch[1] : "00",
            report.scenario,
            report.ok ? "passed" : "failed",
            report.summary.passed,
            report.summary.failed,
            report.summary.skipped,
            Math.round(report.duration_s * 1000),
            JSON.stringify(report.steps),
            report.started_at,
            report.finished_at,
          );
        }

        // Insert the run record
        db.prepare(
          `INSERT INTO runs (id, started_at, finished_at, status, total_scenarios, passed, failed, skipped, duration_s)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).run(
          runId,
          startedAt,
          finishedAt,
          "completed",
          files.length,
          totalPassed,
          totalFailed,
          totalSkipped,
          finishedAt - startedAt,
        );

        db.exec("COMMIT");
        imported++;
      } catch (e) {
        db.exec("ROLLBACK");
        console.error(`Error importing run ${runId}:`, e);
      }
    }
  } catch (e) {
    console.error("Error scanning reports directory:", e);
  }

  return imported;
}
