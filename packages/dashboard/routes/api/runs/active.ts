/** API: /api/runs/active — GET the currently active run. @module api/runs/active */
import { Handlers } from "$fresh/server.ts";
import { runManager } from "../../../services/run_manager.ts";

/** GET /api/runs/active — returns the active run or null. */
export const handler: Handlers = {
  GET(_req) {
    const activeRun = runManager.getActiveRun();
    return new Response(JSON.stringify({ activeRun: activeRun || null }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
