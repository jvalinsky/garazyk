/**
 * API: /api/runs
 * GET — list past runs
 */

import { Handlers } from "$fresh/server.ts";
import { db } from "../../db/index.ts";

export const handler: Handlers = {
  GET(_req) {
    const runs = db.prepare(`
      SELECT id, started_at as startedAt, finished_at as finishedAt, passed, failed, skipped, total_scenarios as total, duration_s as durationS 
      FROM runs 
      ORDER BY started_at DESC
    `).all();
    
    return new Response(JSON.stringify({ runs }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
