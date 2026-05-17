/** API: /api/runs/[runId]/progress — GET run progress. @module api/runs/[runId]/progress */
import { Handlers } from "$fresh/server.ts";
import { join } from "@std/path";
import { db } from "../../../../db/index.ts";
import { fetchRun } from "../../../../db/queries.ts";

/** GET /api/runs/[runId]/progress — returns progress snapshot for a run. */
export const handler: Handlers = {
  async GET(_req, ctx) {
    const { runId } = ctx.params;
    const run = fetchRun(db, runId);
    if (!run) {
      return new Response(
        JSON.stringify({
          exists: false,
          runId,
          total: 0,
          completed: 0,
          currentScenario: null,
          currentScenarioId: null,
          elapsedMs: 0,
          updatedAt: Date.now(),
          now: Date.now(),
          running: false,
        }),
        { status: 404, headers: { "Content-Type": "application/json" } },
      );
    }

    const now = Date.now();
    const elapsedMs = Math.max(0, now - run.startedAt);
    const progressPath = run.runDir
      ? join(run.runDir, "progress.json")
      : undefined;

    if (progressPath) {
      try {
        const content = await Deno.readTextFile(progressPath);
        const progress = JSON.parse(content);
        if (progress.runId && progress.runId !== runId) {
          throw new Error(`progress run id mismatch: ${progress.runId}`);
        }
        return new Response(
          JSON.stringify({
            exists: true,
            ...progress,
            runId,
            elapsedMs,
            now,
            running: run.status === "running" || run.status === "starting" ||
              run.status === "stopping",
          }),
          {
            headers: { "Content-Type": "application/json" },
          },
        );
      } catch {
        // Fall through to the DB/log based fallback.
      }
    }

    {
      let lastActivity = run.startedAt || now;
      try {
        if (run.logPath) {
          const stat = await Deno.stat(run.logPath);
          lastActivity = stat.mtime?.getTime() ?? lastActivity;
        }
      } catch {
        // no log file yet
      }

      return new Response(
        JSON.stringify({
          exists: false,
          runId,
          total: run.totalScenarios ?? 0,
          completed: (run.passed ?? 0) + (run.failed ?? 0) + (run.skipped ?? 0),
          currentScenario: null,
          currentScenarioId: null,
          elapsedMs,
          updatedAt: lastActivity,
          now,
          running: run.status === "running" || run.status === "starting" ||
            run.status === "stopping",
        }),
        {
          headers: { "Content-Type": "application/json" },
        },
      );
    }
  },
};
