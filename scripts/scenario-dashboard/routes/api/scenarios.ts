/**
 * API: /api/scenarios
 * GET — list all discoverable scenarios
 * POST — run selected scenarios
 */

import { Handlers } from "$fresh/server.ts";
import { getScenarios } from "../../services/scenario_discovery.ts";
import { join, fromFileUrl } from "$std/path/mod.ts";
import { db } from "../../db/index.ts";

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

    const now = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    const runId = `${now.getUTCFullYear()}${pad(now.getUTCMonth()+1)}${pad(now.getUTCDate())}-${pad(now.getUTCHours())}${pad(now.getUTCMinutes())}${pad(now.getUTCSeconds())}`;
    const startedAt = Math.floor(now.getTime() / 1000);

    // Insert pending run
    try {
      db.prepare(`
        INSERT INTO runs (id, started_at, status, total_scenarios, passed, failed, skipped)
        VALUES (?, ?, 'running', ?, 0, 0, 0)
      `).run(runId, startedAt, ids.length);
    } catch (e) {
      console.error("Failed to insert run record", e);
    }

    // Run async
    (async () => {
      const scriptPath = join(
        fromFileUrl(new URL("../../../../run_scenarios.ts", import.meta.url))
      );
      const args = ["run", "-A", scriptPath, "--no-setup", "--run-id", runId, ...ids];
      if (pds2) args.push("--pds2");

      const command = new Deno.Command("deno", {
        args,
        stdout: "inherit",
        stderr: "inherit",
      });
      const { code } = await command.output();

      // Scan reports to finalize DB
      const { scanReports } = await import("../../services/report_scanner.ts");
      await scanReports(db);
    })();

    return new Response(JSON.stringify({
      message: "Run initiated",
      runId,
      scenarioIds: ids,
      pds2,
    }), {
      status: 202,
      headers: { "Content-Type": "application/json" },
    });
  },
};
