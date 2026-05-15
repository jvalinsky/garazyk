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
      return new Response(JSON.stringify({ error: e.message }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }
  },
};
