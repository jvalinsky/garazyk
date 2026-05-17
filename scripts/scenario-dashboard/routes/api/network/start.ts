import { Handlers } from "$fresh/server.ts";
import { networkManager } from "../../../services/network_manager.ts";

/** API handler for starting the network. */
export const handler: Handlers = {
  async POST(req) {
    const body = await req.json().catch(() => ({}));
    const pds2 = body.pds2 || false;

    try {
      await networkManager.startAll({ pds2 });
      const status = networkManager.getStatus();
      return new Response(JSON.stringify({ services: status }), {
        headers: { "Content-Type": "application/json" },
      });
    } catch (e) {
      return new Response(JSON.stringify({ error: String(e) }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }
  },
};
