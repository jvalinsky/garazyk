#!/usr/bin/env -S deno run -A
import dev from "$fresh/dev.ts";
import { getDashboardPaths } from "./paths.ts";

const paths = getDashboardPaths();
const port = parseInt(Deno.env.get("DASHBOARD_PORT") || "3001");

await dev(import.meta.url, "fresh.gen.ts", {
  plugins: [],
  staticDir: paths.staticDir,
  router: {
    trailingSlash: false,
  },
  server: { port },
});
