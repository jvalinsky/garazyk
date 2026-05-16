/**
 * API: /api/scenarios
 * GET — list all discoverable scenarios
 * POST — run selected scenarios
 * @module api/scenarios
 */

import { Handlers } from "$fresh/server.ts";
import { getScenarios } from "../../services/scenario_discovery.ts";
import { runManager } from "../../services/run_manager.ts";

/** GET /api/scenarios — returns list of all discoverable scenarios. POST /api/scenarios — starts a run with selected scenario IDs. */
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

    // Wrap in RunConfig for the new RunManager
    const result = await runManager.startRun({
      topology: "garazyk-default", // Default for legacy callers
      runner: "host",
      scenarioIds: ids,
      pds2,
      binaryMode: false,
    });

    if ("conflict" in result) {
      return new Response(JSON.stringify({ error: result.conflict }), {
        status: 409,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      message: "Run initiated",
      runId: result.runId,
      scenarioIds: ids,
      pds2,
    }), {
      status: 202,
      headers: { "Content-Type": "application/json" },
    });
  },
};
