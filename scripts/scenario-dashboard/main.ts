#!/usr/bin/env -S deno run -A
import { dirname, fromFileUrl, join } from "$std/path/mod.ts";
import { start } from "$fresh/server.ts";
import manifest from "./fresh.gen.ts";
import { runManager } from "./services/run_manager.ts";

const dir = dirname(fromFileUrl(import.meta.url));
const port = parseInt(Deno.env.get("DASHBOARD_PORT") || "3001");

// Recover any active run state from previous session
await runManager.recover();

await start(manifest, {
  plugins: [],
  staticDir: join(dir, "static"),
  router: {
    trailingSlash: false,
  },
  server: { port },
});
