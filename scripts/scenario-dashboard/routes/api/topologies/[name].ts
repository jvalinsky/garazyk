import { Handlers } from "$fresh/server.ts";
import { getTopologyPreview } from "../../../services/topology_service.ts";

export const handler: Handlers = {
  async GET(_req, ctx) {
    const name = ctx.params.name;
    try {
      const preview = await getTopologyPreview(name);
      return new Response(JSON.stringify(preview), {
        headers: { "Content-Type": "application/json" },
      });
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      return new Response(JSON.stringify({ error: message }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }
  },
};
