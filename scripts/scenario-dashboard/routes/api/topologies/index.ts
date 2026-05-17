import { Handlers } from "$fresh/server.ts";
import { listTopologies } from "../../../services/topology_service.ts";

/** API handler for the topology list. */
export const handler: Handlers = {
  async GET(_req) {
    const topologies = await listTopologies();
    return new Response(JSON.stringify({ topologies }), {
      headers: { "Content-Type": "application/json" },
    });
  },
};
