import { Handlers } from "$fresh/server.ts";
import { runManager } from "../../../../services/run_manager.ts";

export const handler: Handlers = {
  async POST(_req, ctx) {
    const runId = ctx.params.runId;
    const result = await runManager.restartRun(runId);
    
    if ("error" in result) {
      return new Response(JSON.stringify({ error: result.error }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify(result), {
      status: 202,
      headers: { "Content-Type": "application/json" },
    });
  },
};
