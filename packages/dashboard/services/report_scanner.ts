/**
 * Report Scanner — scans existing JSON report files and imports them into SQLite.
 * Parses filenames in the format: YYYYMMDD-HHMMSS-scenario_name.json
 */

import { join } from "@std/path";
import type { Database } from "sqlite3";
import { z } from "zod";
import type { Run } from "./types.ts";
import { getDashboardPaths } from "../paths.ts";

const nonNegativeInteger = z.number().int().nonnegative().finite();
const nonNegativeNumber = z.number().nonnegative().finite();

const reportFileSchema = z.object({
  scenario: z.string().min(1),
  started_at: nonNegativeNumber,
  finished_at: nonNegativeNumber,
  duration_s: nonNegativeNumber,
  steps: z.array(z.object({
    name: z.string(),
    status: z.string(),
    detail: z.string().optional(),
    duration_ms: nonNegativeNumber.optional(),
  })),
  summary: z.object({
    passed: nonNegativeInteger,
    failed: nonNegativeInteger,
    skipped: nonNegativeInteger,
    total: nonNegativeInteger,
  }),
  ok: z.boolean(),
  artifacts: z.record(z.unknown()).optional(),
  metadata: z.record(z.unknown()).optional(),
});

/** Internal report file structure parsed from JSON. */
type ReportFile = z.infer<typeof reportFileSchema>;

interface ReadReportFileResult {
  filename: string;
  report: ReportFile;
}

function scenarioIdFromFilename(filename: string): string {
  const match = filename.match(/^(\d+)/);
  return match ? match[1] : "00";
}

async function readRunReportFiles(
  reportsDir: string,
): Promise<ReadReportFileResult[]> {
  const reports: ReadReportFileResult[] = [];
  for await (const entry of Deno.readDir(reportsDir)) {
    if (!entry.isFile || !entry.name.endsWith(".json")) continue;
    if (
      entry.name === "overall-summary.json" ||
      entry.name.endsWith("-progress.json")
    ) continue;

    const report = await readRunReportFile(reportsDir, entry.name);
    if (report) reports.push(report);
  }
  return reports;
}

async function readRunReportFile(
  reportsDir: string,
  filename: string,
): Promise<ReadReportFileResult | undefined> {
  const filePath = join(reportsDir, filename);
  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(await Deno.readTextFile(filePath));
  } catch (e) {
    console.error(
      `[report_scanner] Skipping invalid report ${filename}: ${
        e instanceof Error ? e.message : String(e)
      }`,
    );
    return undefined;
  }

  const parsedReport = reportFileSchema.safeParse(parsedJson);
  if (!parsedReport.success) {
    const diagnostics = parsedReport.error.issues.map((issue) => {
      const path = issue.path.length === 0 ? "<root>" : issue.path.join(".");
      return `${path}: ${issue.message}`;
    }).join("; ");
    console.error(
      `[report_scanner] Skipping invalid report ${filename}: ${diagnostics}`,
    );
    return undefined;
  }

  return { filename, report: parsedReport.data };
}

/** Import report files from a run's reports directory into the database. Returns count of imported reports. */
export async function importRunReports(
  db: Database,
  run: Run,
): Promise<number> {
  if (!run.reportsDir) return 0;
  const reports = await readRunReportFiles(run.reportsDir);
  if (reports.length === 0) return 0;

  let totalPassed = 0;
  let totalFailed = 0;
  let totalSkipped = 0;
  let finishedAt = run.startedAt;

  db.exec("BEGIN TRANSACTION");
  try {
    db.prepare("DELETE FROM scenario_results WHERE run_id = ?").run(run.id);

    for (const { filename, report } of reports) {
      const scenarioId = String(
        report.metadata?.scenario_id ?? scenarioIdFromFilename(filename),
      );
      totalPassed += report.summary.passed;
      totalFailed += report.summary.failed;
      totalSkipped += report.summary.skipped;
      const reportFinishedAt = report.finished_at < 10_000_000_000
        ? report.finished_at * 1000
        : report.finished_at;
      if (reportFinishedAt > finishedAt) finishedAt = reportFinishedAt;

      db.prepare(
        `INSERT INTO scenario_results (run_id, scenario_id, scenario_name, status, passed, failed, skipped, duration_ms, steps_json, artifacts_json, started_at, finished_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).run(
        run.id,
        scenarioId,
        report.scenario,
        report.ok ? "passed" : "failed",
        report.summary.passed,
        report.summary.failed,
        report.summary.skipped,
        Math.round(report.duration_s * 1000),
        JSON.stringify(report.steps),
        JSON.stringify(report.artifacts ?? {}),
        report.started_at < 10_000_000_000
          ? report.started_at * 1000
          : report.started_at,
        reportFinishedAt,
      );
    }

    db.prepare(
      `UPDATE runs SET finished_at=?, total_scenarios=?, passed=?, failed=?, skipped=?, duration_s=? WHERE id=?`,
    ).run(
      finishedAt,
      reports.length,
      totalPassed,
      totalFailed,
      totalSkipped,
      Math.max(0, Math.round((finishedAt - run.startedAt) / 1000)),
      run.id,
    );
    db.exec("COMMIT");
    return reports.length;
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

function parseFilename(
  filename: string,
): { timestamp: string; scenarioName: string } | null {
  if (filename.endsWith("-progress.json")) return null;
  // Format: 20260507-183659-01_account_lifecycle.json
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
  return Math.floor(
    new Date(Date.UTC(year, month, day, hour, min, sec)).getTime() / 1000,
  );
}

/** Scan the reports directory for unprocessed reports and import them as historical runs. Returns count of imports. */
export async function scanReports(db: Database): Promise<number> {
  let imported = 0;
  const reportsDir = getDashboardPaths().reportsDir;

  try {
    const reports = await readRunReportFiles(reportsDir);

    // Group reports by run timestamp
    const runGroups: Map<
      string,
      Array<
        ReadReportFileResult & {
          parsed: NonNullable<ReturnType<typeof parseFilename>>;
        }
      >
    > = new Map();

    for (const reportFile of reports) {
      const parsed = parseFilename(reportFile.filename);
      if (!parsed) continue;

      if (!runGroups.has(parsed.timestamp)) {
        runGroups.set(parsed.timestamp, []);
      }
      runGroups.get(parsed.timestamp)!.push({ ...reportFile, parsed });
    }

    for (const [timestamp, files] of runGroups) {
      const runId = timestamp;
      const startedAt = timestampToUnix(timestamp);

      // Check if this run already exists and has results
      const existing = db.prepare("SELECT id, status FROM runs WHERE id = ?")
        .get<
          { id: string; status: string }
        >(runId);
      const hasResults = db.prepare(
        "SELECT COUNT(*) as count FROM scenario_results WHERE run_id = ?",
      ).get<{ count: number }>(runId);

      if (
        existing && existing.status === "completed" && hasResults &&
        hasResults.count > 0
      ) {
        continue;
      }

      let totalPassed = 0;
      let totalFailed = 0;
      let totalSkipped = 0;
      let finishedAt = startedAt;

      // Begin transaction
      db.exec("BEGIN TRANSACTION");

      try {
        // Clear any partial data for this run id
        db.prepare("DELETE FROM scenario_results WHERE run_id = ?").run(runId);

        // Insert stub runs record first to satisfy FK constraint on scenario_results
        db.prepare(
          `INSERT OR REPLACE INTO runs (id, started_at, finished_at, status, total_scenarios, passed, failed, skipped, duration_s)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        ).run(
          runId,
          startedAt,
          startedAt,
          "running",
          0,
          0,
          0,
          0,
          0,
        );

        for (const file of files) {
          const report = file.report;

          // Extract numeric ID from the scenario name (format: 01_account_lifecycle)
          const idMatch = file.parsed.scenarioName.match(/^(\d+)/);
          const scenarioId = idMatch ? idMatch[1] : "00";

          totalPassed += report.summary.passed;
          totalFailed += report.summary.failed;
          totalSkipped += report.summary.skipped;

          if (report.finished_at > finishedAt) {
            finishedAt = report.finished_at;
          }

          db.prepare(
            `INSERT INTO scenario_results (run_id, scenario_id, scenario_name, status, passed, failed, skipped, duration_ms, steps_json, started_at, finished_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          ).run(
            runId,
            scenarioId,
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

        // Update the runs record with final computed values
        db.prepare(
          `UPDATE runs SET finished_at=?, status=?, total_scenarios=?, passed=?, failed=?, skipped=?, duration_s=? WHERE id=?`,
        ).run(
          finishedAt,
          "completed",
          files.length,
          totalPassed,
          totalFailed,
          totalSkipped,
          finishedAt - startedAt,
          runId,
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
