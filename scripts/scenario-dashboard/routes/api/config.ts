/** Dashboard launch configuration exposed to the browser. @module api/config */
import { Handlers } from "$fresh/server.ts";
import { isAgentLaunchFromEnv } from "../../services/dashboard_launch.ts";
import { getDashboardSecurity } from "../../services/dashboard_security.ts";

/** GET /api/config — read-only launch flags for the web UI. */
export const handler: Handlers = {
  GET() {
    return Response.json(
      {
        agentLaunch: isAgentLaunchFromEnv(),
        mutationCapability: getDashboardSecurity().mutationCapability,
      },
      { headers: { "Cache-Control": "no-store" } },
    );
  },
};
