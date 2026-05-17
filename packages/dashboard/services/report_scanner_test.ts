import { assertEquals } from "@std/assert";
import { join } from "@std/path";
import { Database } from "sqlite3";
import { SCHEMA } from "../db/schema.ts";
import { configureDashboardPaths } from "../paths.ts";
import { importRunReports, scanReports } from "./report_scanner.ts";
import type { Run } from "./types.ts";

interface RunTotalsRow {
  total_scenarios: number;
  passed: number;
  failed: number;
  skipped: number;
}

interface ScenarioResultRow {
  scenario_id: string;
  scenario_name: string;
  passed: number;
  failed: number;
  skipped: number;
}

function createTestDb(): Database {
  const db = new Database(":memory:");
  db.exec(SCHEMA);
  return db;
}

function validReport(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    scenario: "account lifecycle",
    started_at: 1_700_000_000,
    finished_at: 1_700_000_004,
    duration_s: 4,
    steps: [
      {
        name: "create account",
        status: "passed",
        detail: "ok",
        duration_ms: 25,
      },
    ],
    summary: {
      passed: 2,
      failed: 0,
      skipped: 1,
      total: 3,
    },
    ok: true,
    metadata: {
      scenario_id: "01",
    },
    ...overrides,
  };
}

async function writeReport(
  reportsDir: string,
  filename: string,
  report: Record<string, unknown>,
): Promise<void> {
  await Deno.writeTextFile(join(reportsDir, filename), JSON.stringify(report));
}

async function withDiagnostics(
  fn: () => Promise<void>,
): Promise<string[]> {
  const diagnostics: string[] = [];
  const originalError = console.error;
  console.error = (...data: unknown[]) => {
    diagnostics.push(data.map(String).join(" "));
  };

  try {
    await fn();
  } finally {
    console.error = originalError;
  }

  return diagnostics;
}

Deno.test("importRunReports skips invalid report files with diagnostics", async () => {
  const db = createTestDb();
  const reportsDir = await Deno.makeTempDir();
  try {
    db.prepare(
      "INSERT INTO runs (id, started_at, status) VALUES (?, ?, ?)",
    ).run("run-1", 1_700_000_000_000, "running");

    await writeReport(
      reportsDir,
      "20260507-183659-01_account_lifecycle.json",
      validReport(),
    );
    await writeReport(
      reportsDir,
      "20260507-183659-02_bad_counts.json",
      validReport({
        scenario: "bad counts",
        summary: {
          passed: "NaN",
          failed: 0,
          skipped: 0,
          total: 0,
        },
      }),
    );
    await Deno.writeTextFile(
      join(reportsDir, "20260507-183659-03_broken.json"),
      "{",
    );

    const run: Run = {
      id: "run-1",
      startedAt: 1_700_000_000_000,
      status: "running",
      totalScenarios: 0,
      passed: 0,
      failed: 0,
      skipped: 0,
      reportsDir,
    };

    const diagnostics = await withDiagnostics(async () => {
      assertEquals(await importRunReports(db, run), 1);
    });

    assertEquals(diagnostics.length, 2);
    assertEquals(
      diagnostics.some((line) => line.includes("02_bad_counts.json")),
      true,
    );
    assertEquals(
      diagnostics.some((line) => line.includes("03_broken.json")),
      true,
    );

    const totals = db.prepare(
      "SELECT total_scenarios, passed, failed, skipped FROM runs WHERE id = ?",
    ).get<RunTotalsRow>("run-1");
    assertEquals(totals, {
      total_scenarios: 1,
      passed: 2,
      failed: 0,
      skipped: 1,
    });

    const rows = db.prepare(
      "SELECT scenario_id, scenario_name, passed, failed, skipped FROM scenario_results",
    ).all<ScenarioResultRow>();
    assertEquals(rows, [
      {
        scenario_id: "01",
        scenario_name: "account lifecycle",
        passed: 2,
        failed: 0,
        skipped: 1,
      },
    ]);
  } finally {
    db.close();
    await Deno.remove(reportsDir, { recursive: true });
  }
});

Deno.test("scanReports imports only validated report files", async () => {
  const db = createTestDb();
  const rootDir = await Deno.makeTempDir();
  const reportsDir = join(rootDir, "scripts", "scenarios", "reports");
  try {
    await Deno.mkdir(reportsDir, { recursive: true });
    await Deno.writeTextFile(join(rootDir, "scripts", "run_scenarios.ts"), "");
    configureDashboardPaths({ rootDir });

    await writeReport(
      reportsDir,
      "20260507-183659-01_account_lifecycle.json",
      validReport(),
    );
    await writeReport(
      reportsDir,
      "20260507-183659-02_bad_duration.json",
      validReport({
        scenario: "bad duration",
        duration_s: null,
      }),
    );

    const diagnostics = await withDiagnostics(async () => {
      assertEquals(await scanReports(db), 1);
    });

    assertEquals(diagnostics.length, 1);
    assertEquals(diagnostics[0].includes("02_bad_duration.json"), true);

    const totals = db.prepare(
      "SELECT total_scenarios, passed, failed, skipped FROM runs WHERE id = ?",
    ).get<RunTotalsRow>("20260507-183659");
    assertEquals(totals, {
      total_scenarios: 1,
      passed: 2,
      failed: 0,
      skipped: 1,
    });

    const rows = db.prepare(
      "SELECT scenario_id, scenario_name, passed, failed, skipped FROM scenario_results",
    ).all<ScenarioResultRow>();
    assertEquals(rows, [
      {
        scenario_id: "01",
        scenario_name: "account lifecycle",
        passed: 2,
        failed: 0,
        skipped: 1,
      },
    ]);
  } finally {
    db.close();
    await Deno.remove(rootDir, { recursive: true });
  }
});
