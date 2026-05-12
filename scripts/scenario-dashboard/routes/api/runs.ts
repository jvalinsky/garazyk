/**
 * API: /api/runs
 * GET — list past runs
 */

import { Handlers } from "$fresh/server.ts";

export const handler: Handlers = {
  GET(_req) {
    // Will be wired to SQLite when DB layer is complete
    return new Response(JSON.stringify({ runs: [] }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
