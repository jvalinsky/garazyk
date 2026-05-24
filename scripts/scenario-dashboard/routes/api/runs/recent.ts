/** API: /api/runs/recent - GET recent dashboard runs. @module api/runs/recent */
import { Handlers } from "$fresh/server.ts";
import { db } from "../../../db/index.ts";
import { fetchRuns } from "../../../db/queries.ts";

/** GET /api/runs/recent?limit=N - returns recent run records. */
export const handler: Handlers = {
  GET(req) {
    const url = new URL(req.url);
    const parsedLimit = Number.parseInt(
      url.searchParams.get("limit") ?? "6",
      10,
    );
    const limit = Number.isFinite(parsedLimit)
      ? Math.max(1, Math.min(parsedLimit, 50))
      : 6;

    return new Response(JSON.stringify(fetchRuns(db, limit)), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
