import { start } from "$fresh/server.ts";
import {
  configureDashboardPaths,
  type DashboardPathOptions,
  getDashboardPaths,
} from "./paths.ts";
import { db } from "./db/index.ts";
import { scanReports } from "./services/report_scanner.ts";

/** Options for starting the scenario dashboard web server. */
export interface DashboardServerOptions extends DashboardPathOptions {
  /** HTTP port. Defaults to DASHBOARD_PORT, then 3001. */
  port?: number;
}

/** Start the Fresh scenario dashboard server. */
export async function startDashboard(
  options: DashboardServerOptions = {},
): Promise<void> {
  configureDashboardPaths(options);
  const paths = getDashboardPaths();
  const port = options.port ?? dashboardPortFromEnv();

  const [{ default: manifest }, { runManager }] = await Promise.all([
    import("./fresh.gen.ts"),
    import("./services/run_manager.ts"),
  ]);

  await runManager.recover();

  // Scan reports in background — do not block server startup
  scanReports(db).catch((e) =>
    console.error("[server] scanReports failed:", e)
  );

  await start(manifest, {
    plugins: [],
    staticDir: paths.staticDir,
    router: {
      trailingSlash: false,
    },
    server: { port },
  });
}

function dashboardPortFromEnv(): number {
  const raw = Deno.env.get("DASHBOARD_PORT");
  if (!raw) return 3001;

  const port = Number.parseInt(raw, 10);
  return Number.isFinite(port) ? port : 3001;
}
