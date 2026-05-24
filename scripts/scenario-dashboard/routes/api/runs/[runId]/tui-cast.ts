import { Handlers } from "$fresh/server.ts";
import { db } from "../../../../db/index.ts";
import { fetchRun } from "../../../../db/queries.ts";
import { resolveRunArtifact, RUN_ARTIFACTS } from "../../../../lib/artifacts.ts";

/** Serve TUI asciicast recording for a run when present. */
export const handler: Handlers = {
  async GET(_req, ctx) {
    const { runId } = ctx.params;
    const run = fetchRun(db, runId);
    if (!run) {
      return new Response("Run not found", { status: 404 });
    }

    const castPath = await resolveRunArtifact(run.runDir, RUN_ARTIFACTS.tuiCast);
    if (!castPath) {
      return new Response("TUI recording not available for this run.", {
        status: 404,
      });
    }

    try {
      const content = await Deno.readTextFile(castPath);
      return new Response(content, {
        headers: {
          "Content-Type": "application/x-ndjson",
          "Cache-Control": "no-cache",
        },
      });
    } catch (e) {
      console.error(`[api] Error reading cast for ${runId}:`, e);
      return new Response("Error reading TUI recording", { status: 500 });
    }
  },
};
