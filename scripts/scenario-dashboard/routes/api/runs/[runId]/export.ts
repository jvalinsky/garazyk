import { Handlers } from "$fresh/server.ts";
import { db } from "../../../../../db/index.ts";
import { exportRunBundle } from "../../../../../lib/export_run_lib.ts";

/** Generate or refresh run replay export and return index.html. */
export const handler: Handlers = {
  async GET(_req, ctx) {
    const { runId } = ctx.params;
    try {
      const { indexPath } = await exportRunBundle(db, runId);
      const html = await Deno.readTextFile(indexPath);
      return new Response(html, {
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-cache",
        },
      });
    } catch (e) {
      const msg = (e as Error).message;
      const status = msg.includes("not found") ? 404 : 500;
      return new Response(msg, { status });
    }
  },
};
