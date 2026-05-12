import { Handlers } from "$fresh/server.ts";
import { networkManager } from "../../../services/network_manager.ts";

export const handler: Handlers = {
  async GET(_req) {
    const status = await networkManager.healthCheck();
    return new Response(JSON.stringify({ services: status }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
