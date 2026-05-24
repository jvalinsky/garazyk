import { Handlers } from "$fresh/server.ts";
import { networkManager } from "../../../services/network_manager.ts";

/** API handler for stopping the network. */
export const handler: Handlers = {
  async POST(req) {
    const body = await req.json().catch(() => ({}));
    const useBinary = body.runner === "host";

    try {
      await networkManager.stopAll({ useBinary });
      const status = networkManager.getStatus();
      return new Response(JSON.stringify({ services: Object.values(status) }), {
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
