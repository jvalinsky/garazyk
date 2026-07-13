#!/usr/bin/env -S deno run -A
import { dirname, fromFileUrl, join } from "$std/path/mod.ts";
import { start } from "$fresh/server.ts";
import manifest from "./fresh.gen.ts";
import { getDashboardSecurity } from "./services/dashboard_security.ts";
import { runManager } from "./services/run_manager.ts";

const dir = dirname(fromFileUrl(import.meta.url));
const security = getDashboardSecurity();

// Recover any active run state from previous session
await runManager.recover();

await start(manifest, {
  plugins: [],
  staticDir: join(dir, "static"),
  router: {
    trailingSlash: false,
  },
  server: { hostname: security.host, port: security.port },
});
