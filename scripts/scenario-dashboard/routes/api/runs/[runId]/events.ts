import { Handlers } from "$fresh/server.ts";
import { db } from "../../../../db/index.ts";
import { fetchRunEvents } from "../../../../db/queries.ts";

/** API handler for persisted run timeline events. */
export const handler: Handlers = {
  GET(_req, ctx) {
    const { runId } = ctx.params;
    try {
      const events = fetchRunEvents(db, runId);
      return Response.json(events);
    } catch (e) {
      console.error(`[api] Error fetching events for ${runId}:`, e);
      return new Response(
        JSON.stringify({ error: (e as Error).message }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }
  },
};
