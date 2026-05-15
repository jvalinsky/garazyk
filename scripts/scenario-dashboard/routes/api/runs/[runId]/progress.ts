import { Handlers } from "$fresh/server.ts";
import { join, fromFileUrl } from "$std/path/mod.ts";
import { db } from "../../../../db/index.ts";
import { fetchRun } from "../../../../db/queries.ts";

export const handler: Handlers = {
  async GET(_req, ctx) {
    const { runId } = ctx.params;

    const repoRoot = fromFileUrl(new URL("../../../../../../", import.meta.url));
    const progressPath = join(repoRoot, "scripts", "scenarios", "reports", `${runId}-progress.json`);

    const run = fetchRun(db, runId);
    const now = Date.now();
    const elapsedMs = run ? (now - run.startedAt * 1000) : 0;

    try {
      const content = await Deno.readTextFile(progressPath);
      const progress = JSON.parse(content);
      return new Response(JSON.stringify({
        exists: true,
        ...progress,
        elapsedMs,
        now,
      }), {
        headers: { "Content-Type": "application/json" },
      });
    } catch {
      const logPath = join(repoRoot, "scenarios", "reports", "runs", runId, "run.log");
      let lastActivity = run?.startedAt ? run.startedAt * 1000 : now;
      try {
        const stat = await Deno.stat(logPath);
        lastActivity = stat.mtime?.getTime() ?? lastActivity;
      } catch {
        // no log file yet
      }

      return new Response(JSON.stringify({
        exists: false,
        runId,
        total: run?.totalScenarios ?? 0,
        completed: 0,
        currentScenario: null,
        currentScenarioId: null,
        elapsedMs,
        updatedAt: lastActivity,
        now,
        running: run?.status === "running",
      }), {
        headers: { "Content-Type": "application/json" },
      });
    }
  },
};
