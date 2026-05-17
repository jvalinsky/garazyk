/** API: /api/runs/[runId] — GET run status by ID. @module api/runs/[runId] */
import { Handlers } from "$fresh/server.ts";

/** Response shape for run status endpoint. */
interface RunStatusResponse {
  status: string;
  passed: number;
  failed: number;
  skipped: number;
}

/** GET /api/runs/[runId] — returns run status and result counts. */
export const handler: Handlers<RunStatusResponse> = {
  GET(_req, ctx) {
    const { runId } = ctx.params;

    try {
      const run = fetchRun(db, runId);

      if (!run) {
        return new Response(
          JSON.stringify({ status: "not_found", passed: 0, failed: 0, skipped: 0 }),
          {
            status: 404,
            headers: { "Content-Type": "application/json" },
          },
        );
      }

      return new Response(
        JSON.stringify({
          status: run.status,
          passed: run.passed,
          failed: run.failed,
          skipped: run.skipped,
        }),
        {
          headers: { "Content-Type": "application/json" },
        },
      );
    } catch (e) {
      console.error("Error fetching run status:", e);
      return new Response(JSON.stringify({ status: "error", passed: 0, failed: 0, skipped: 0 }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }
  },
};
