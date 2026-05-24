/**
 * Shared run replay export logic for CLI and API.
 *
 * @module lib/export_run_lib
 */

import { join } from "$std/path/mod.ts";
import type { Database } from "sqlite3";
import { fetchRun, fetchRunEvents } from "../db/queries.ts";
import { buildExportHtml } from "./export_html.ts";
import { resolveRunArtifact, RUN_ARTIFACTS } from "./artifacts.ts";

export interface ExportRunResult {
  indexPath: string;
  outDir: string;
}

/** Build export bundle for a run; returns path to index.html. */
export async function exportRunBundle(
  db: Database,
  runId: string,
): Promise<ExportRunResult> {
  const run = fetchRun(db, runId);
  if (!run) {
    throw new Error(`Run not found: ${runId}`);
  }

  const events = fetchRunEvents(db, runId);
  const castPath = await resolveRunArtifact(run.runDir, RUN_ARTIFACTS.tuiCast);
  const castContent = castPath ? await Deno.readTextFile(castPath) : undefined;

  const outDir = run.runDir
    ? join(run.runDir, "export")
    : join("scripts/scenarios/reports/exports", runId);

  await Deno.mkdir(outDir, { recursive: true });

  const html = buildExportHtml({
    runId,
    castContent,
    events,
    startedAt: run.startedAt,
  });

  const indexPath = join(outDir, "index.html");
  await Deno.writeTextFile(indexPath, html);

  if (castPath) {
    await Deno.copyFile(castPath, join(outDir, "dashboard.cast"));
  }

  await Deno.writeTextFile(
    join(outDir, "events.json"),
    JSON.stringify(events, null, 2),
  );

  const eventsNdjson = await resolveRunArtifact(run.runDir, RUN_ARTIFACTS.eventsNdjson);
  if (eventsNdjson) {
    await Deno.copyFile(eventsNdjson, join(outDir, "events.ndjson"));
  }

  return { indexPath, outDir };
}
