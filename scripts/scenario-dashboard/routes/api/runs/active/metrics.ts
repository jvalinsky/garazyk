import { Handlers } from "$fresh/server.ts";
import { networkManager } from "../../../../services/network_manager.ts";

export const handler: Handlers = {
  async GET(_req) {
    const stats = await networkManager.getContainerStats();
    return new Response(JSON.stringify({ stats }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
