/** API: /api/runs/start — POST to start a new run. @module api/runs/start */
import { Handlers } from "$fresh/server.ts";
import { runManager } from "../../../services/run_manager.ts";
import { RunConfig } from "../../../services/types.ts";

/** POST /api/runs/start — starts a new run with the given RunConfig. */
export const handler: Handlers = {
  async POST(req) {
    const config = await req.json() as RunConfig;
    
    if (!config.scenarioIds || config.scenarioIds.length === 0) {
      return new Response(JSON.stringify({ error: "No scenarios selected" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const result = await runManager.startRun(config);
    
    if ("conflict" in result) {
      return new Response(JSON.stringify({ error: result.conflict }), {
        status: 409,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify(result), {
      status: 202,
      headers: { "Content-Type": "application/json" },
    });
  },
};
