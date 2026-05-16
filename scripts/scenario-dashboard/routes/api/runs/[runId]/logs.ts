import { Handlers } from "$fresh/server.ts";
import { db } from "../../../../db/index.ts";
import { fetchRun } from "../../../../db/queries.ts";

export const handler: Handlers = {
  async GET(_req, ctx) {
    const { runId } = ctx.params;
    const run = fetchRun(db, runId);
    const logPath = run?.logPath;

    if (!run || !logPath) {
      return new Response("Run logs are not available.", { status: 404 });
    }

    try {
      const content = await Deno.readTextFile(logPath);
      return new Response(content, {
        headers: { "Content-Type": "text/plain" },
      });
    } catch (e) {
      if (e instanceof Deno.errors.NotFound) {
        console.log(`[api] Logs not found at: ${logPath}`);
        return new Response("Waiting for logs to start...", { status: 404 });
      }
      console.error(`[api] Error reading logs for ${runId}:`, e);
      return new Response("Error reading logs: " + (e as Error).message, { status: 500 });
    }
  },
};
