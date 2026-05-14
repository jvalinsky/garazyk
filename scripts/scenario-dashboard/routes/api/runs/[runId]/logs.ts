import { Handlers } from "$fresh/server.ts";
import { join, fromFileUrl } from "$std/path/mod.ts";

export const handler: Handlers = {
  async GET(_req, ctx) {
    const { runId } = ctx.params;
    // scripts/scenario-dashboard/routes/api/runs/[runId]/logs.ts
    // 1: [runId]/, 2: runs/, 3: api/, 4: routes/, 5: scenario-dashboard/, 6: scripts/, 7: garazyk (root)
    // Wait, URL(".") is the dir [runId]/, so URL("..") is runs/, etc.
    // Let's use 6 levels: ../../../../../../
    const repoRoot = fromFileUrl(new URL("../../../../../../", import.meta.url));
    const logPath = join(repoRoot, "scripts", "scenarios", "reports", "logs", `${runId}.log`);

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
