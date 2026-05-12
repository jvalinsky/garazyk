import { Handlers } from "$fresh/server.ts";
import { networkManager } from "../../../services/network_manager.ts";

export const handler: Handlers = {
  async POST(_req) {
    try {
      await networkManager.stopAll();
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
