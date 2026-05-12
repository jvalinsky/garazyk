#!/usr/bin/env -S deno run -A
import { dirname, fromFileUrl, join } from "$std/path/mod.ts";
import dev from "$fresh/dev.ts";

const dir = dirname(fromFileUrl(import.meta.url));

const port = parseInt(Deno.env.get("DASHBOARD_PORT") || "3001");

await dev(import.meta.url, "fresh.gen.ts", {
  plugins: [],
  staticDir: join(dir, "static"),
  router: {
    trailingSlash: false,
  },
  server: { port },
});
