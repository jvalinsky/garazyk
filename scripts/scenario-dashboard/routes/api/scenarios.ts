/**
 * API: /api/scenarios
 * GET — list all discoverable scenarios
 * POST — run selected scenarios
 */

import { Handlers } from "$fresh/server.ts";
import { getScenarios } from "../../services/scenario_discovery.ts";

export const handler: Handlers = {
  async GET(_req) {
    const scenarios = await getScenarios();
    return new Response(JSON.stringify({ scenarios }), {
      headers: { "Content-Type": "application/json" },
    });
  },

  async POST(req) {
    const body = await req.json();
    const ids: string[] = body.ids || [];
    const pds2: boolean = body.pds2 || false;

    if (ids.length === 0) {
      return new Response(JSON.stringify({ error: "No scenario IDs provided" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // For now, return a placeholder response.
    // Actual execution will be wired up in the Run Manager step.
    return new Response(JSON.stringify({
      message: "Run initiated",
      runId: `run-${Date.now()}`,
      scenarioIds: ids,
      pds2,
    }), {
      status: 202,
      headers: { "Content-Type": "application/json" },
    });
  },
};
