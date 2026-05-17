import { Handlers } from "$fresh/server.ts";
import { networkManager } from "../../../services/network_manager.ts";

/** API handler for network service status. */
export const handler: Handlers = {
  GET(_req) {
    const status = networkManager.getStatus();
    return new Response(JSON.stringify({ services: status }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
