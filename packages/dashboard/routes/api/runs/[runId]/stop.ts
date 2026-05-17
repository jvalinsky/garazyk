import { Handlers } from "$fresh/server.ts";
import { runManager } from "../../../../services/run_manager.ts";

/** API handler for stopping a run. */
export const handler: Handlers = {
  async POST(req, ctx) {
    const runId = ctx.params.runId;
    const body = await req.json().catch(() => ({}));
    const graceful = body.graceful !== false;

    await runManager.stopRun(runId, graceful);

    return new Response(JSON.stringify({ message: "Stop initiated" }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
