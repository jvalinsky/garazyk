import { Handlers } from "$fresh/server.ts";
import { runManager } from "../../../services/run_manager.ts";

export const handler: Handlers = {
  GET(_req) {
    const activeRun = runManager.getActiveRun();
    return new Response(JSON.stringify({ activeRun: activeRun || null }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
